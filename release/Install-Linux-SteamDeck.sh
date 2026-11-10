#!/usr/bin/env bash
# CPU Performance Patch 1.0.0 - installer for Steam Deck / Linux (Proton).
#   bash Install-Linux-SteamDeck.sh [game folder]
# Run it from the extracted archive, wherever that is (for example Downloads).
# It finds the game itself: in every Steam library (native and Flatpak Steam, SD cards and other
# drives Steam knows about), else in ~/Games (Heroic, Lutris). A game folder given as the first
# argument wins over all of that.
# What it does (nothing else):
#   1. Checks the game is closed.
#   2. Copies install/KCDPerf.asi (the patch), install/KCDPerf.ini (its settings, kept if you
#      already have one) and install/version.dll (Ultimate ASI Loader) to Bin/Win64, next to
#      KingdomCome.exe. A different version.dll that is already there is left alone.
#   3. Steam/Proton: adds the line "version"="native,builtin" to the game's Proton prefix
#      (DLL overrides in user.reg, backup kept), so Proton loads version.dll from the game folder.
#   4. Steam: puts WINEDLLOVERRIDES="version=n,b" in front of the game's launch options (the same
#      setting, kept by Steam even if the prefix is reset). Steam has to be closed for this: it
#      rewrites its settings file when it exits. If Steam is running, the installer asks you to close
#      it, or tells you what to type into the launch options yourself. Backup kept.
#   5. Copies the uninstaller to the game folder as CPUPerformancePatch-Uninstall.sh.
# No game file is changed.
set -u

# Started by double-click (no terminal): reopen in a terminal so the messages stay readable.
if [ ! -t 1 ] && [ -z "${KCP_TERM:-}" ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
  command -v konsole >/dev/null && KCP_TERM=1 exec konsole --hold -e bash "$0" "$@"
  command -v xterm >/dev/null && KCP_TERM=1 exec xterm -hold -e bash "$0" "$@"
fi

ASI_SHA=@ASI_SHA@   # install/KCDPerf.asi
UAL_SHA=@UAL_SHA@   # install/version.dll
LINE='"version"="native,builtin"'
die() { echo; echo "ERROR: $*"; echo "Nothing more was changed."; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
is_game() { [ -f "$1/Bin/Win64/KingdomCome.exe" ]; }
steam_libs() {  # every Steam library folder, one per line
  local r
  for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root" \
           "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
    [ -d "$r/steamapps" ] || continue
    echo "$r"; sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$r/steamapps/libraryfolders.vdf" 2>/dev/null
  done
}
find_game() {  # candidate game folders, one per line
  local d lib
  for d in "$SELF/../.." "$SELF"; do is_game "$d" && { (cd "$d" && pwd -P); return; }; done
  steam_libs | while IFS= read -r lib; do d=$lib/steamapps/common/KingdomComeDeliverance; is_game "$d" && (cd "$d" && pwd -P); done
  find "$HOME/Games" -maxdepth 6 -type f -path '*/Bin/Win64/KingdomCome.exe' 2>/dev/null | sed 's|/Bin/Win64/KingdomCome.exe$||'
}
steam_roots() {  # Steam installs (not libraries), each once
  local r
  for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root" \
           "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
    [ -d "$r/userdata" ] && (cd "$r" && pwd -P)
  done | awk '!seen[$0]++'
}
user_configs() {  # every Steam user's localconfig.vdf
  local r f
  steam_roots | while IFS= read -r r; do
    for f in "$r"/userdata/*/config/localconfig.vdf; do
      [ -f "$f" ] && [ "$(basename "$(dirname "$(dirname "$f")")")" != 0 ] && echo "$(stat -c %Y "$f") $f"
    done
  done | sort -rn | cut -d' ' -f2-   # newest first: the account in use
}
steam_running() { pgrep -x steam >/dev/null; }
lo_py() {  # Steam launch option editor (source: tools/release/launch_option.py)
  python3 -I - "$@" <<'GAF_PY'
@LAUNCH_OPTION_PY@
GAF_PY
}
wait_steam_closed() {  # 0 = Steam is closed now, 1 = the user skipped or nobody can answer
  local a i
  while steam_running; do
    echo "Steam is running. Steam saves its settings when it closes, which would undo this change."
    [ -t 0 ] || return 1
    echo "Close Steam now: Steam menu > Exit (Desktop Mode: right-click the Steam icon in the taskbar > Exit Steam)."
    read -r -p "Press Enter when Steam is closed, or type S and press Enter to skip this step: " a || return 1
    case $a in s|S) return 1;; esac
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do steam_running || break; read -r -t 1 _ < /dev/null; done
  done
  return 0
}
prefix_busy() {  # is a wineserver of this prefix still alive? (it rewrites user.reg when it exits)
  local p
  for p in $(pgrep -x wineserver); do
    tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qxF "WINEPREFIX=$1" && return 0
  done
  return 1
}

SELF=$(cd "$(dirname "$0")" && pwd -P)
echo "CPU Performance Patch 1.0.0 - install"
if [ $# -ge 1 ]; then
  is_game "$1" || die "No Kingdom Come: Deliverance in $1 (it needs Bin/Win64/KingdomCome.exe)."
  GAME=$(cd "$1" && pwd -P)
else
  mapfile -t found < <(find_game | awk '!seen[$0]++')
  if [ ${#found[@]} -eq 0 ]; then
    die "Kingdom Come: Deliverance not found. Run it with the game folder:
  bash Install-Linux-SteamDeck.sh \"/path/to/KingdomComeDeliverance\""
  elif [ ${#found[@]} -eq 1 ]; then
    GAME=${found[0]}
  else
    echo "Found more than one copy of the game:"; for i in "${!found[@]}"; do echo "  $((i + 1))) ${found[$i]}"; done
    [ -t 0 ] || die "Run it again with the game folder as the first argument."
    read -r -p "Install into which one? Number: " n
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#found[@]} ] || die "No such number."
    GAME=${found[$((n - 1))]}
  fi
fi
echo "Game folder: $GAME"
B=$GAME/Bin/Win64
pgrep -f '[K]ingdomCome\.exe' >/dev/null && die "The game is running. Close it first."
[ -f "$SELF/install/KCDPerf.asi" ] && [ -f "$SELF/install/KCDPerf.ini" ] && [ -f "$SELF/install/version.dll" ] || die "The install folder is missing from $SELF."
[ "$(sha "$SELF/install/KCDPerf.asi")" = "$ASI_SHA" ] || die "install/KCDPerf.asi is damaged. Download the mod again."
[ "$(sha "$SELF/install/version.dll")" = "$UAL_SHA" ] || die "install/version.dll is damaged. Download the mod again."

# 1. The two files next to KingdomCome.exe
cp -f "$SELF/install/KCDPerf.asi" "$B/KCDPerf.asi" || die "Could not copy KCDPerf.asi to $B."
echo "Plugin: Bin/Win64/KCDPerf.asi copied."
if [ -e "$B/KCDPerf.ini" ]; then
  echo "Settings: Bin/Win64/KCDPerf.ini is already there. Kept."
else
  cp -f "$SELF/install/KCDPerf.ini" "$B/KCDPerf.ini" || die "Could not copy KCDPerf.ini to $B."
  echo "Settings: Bin/Win64/KCDPerf.ini copied."
fi
if [ -e "$B/version.dll" ] && [ "$(sha "$B/version.dll")" != "$UAL_SHA" ]; then
  echo "Loader: Bin/Win64/version.dll is already there and is a different file. Left alone."
  echo "        If it is an ASI loader, the patch loads through it. Check Bin/Win64/KCDPerf.log after a start."
else
  cp -f "$SELF/install/version.dll" "$B/version.dll" || die "Could not copy version.dll to $B."
  cp -f "$SELF/install/Ultimate-ASI-Loader-LICENSE.txt" "$B/Ultimate-ASI-Loader-LICENSE.txt" 2>/dev/null
  echo "Loader: Bin/Win64/version.dll copied (Ultimate ASI Loader)."
fi

# 2. Proton: let it load version.dll from the game folder (Wine prefers its own copy otherwise)
PFX=0; PFXSEEN=0
while IFS= read -r r; do
  [ -n "$r" ] || continue
  PFXSEEN=1
  pfx=$(dirname "$r")
  for i in 1 2 3 4 5 6 7 8 9 10; do prefix_busy "$pfx" || break; read -r -t 1 _ < /dev/null; done
  prefix_busy "$pfx" && die "Proton is still running for this game. Wait a few seconds and run this again."
  if LC_ALL=C grep -qxF "$LINE" "$r"; then
    echo "Proton prefix: override already set."; PFX=1; continue
  fi
  if LC_ALL=C awk '/^\[Software\\\\Wine\\\\DllOverrides\]/ {f=1; next} f && /^$/ {f=0} f && /^"\*?version"=/ {found=1} END {exit !found}' "$r"; then
    echo "Proton prefix: a different setting for version.dll is already there. Left alone: $r"; continue
  fi
  LC_ALL=C grep -q '^\[Software\\\\Wine\\\\DllOverrides\]' "$r" || { echo "Proton prefix: no DLL override list in $r. Left alone."; continue; }
  cp -p "$r" "$r.kcdperf-backup" || die "Could not back up $r."
  LC_ALL=C awk -v line="$LINE" '
    /^\[Software\\\\Wine\\\\DllOverrides\]/ {f=1}
    f && /^$/ {print line; f=0}
    {print}
    END {if (f) print line}' "$r.kcdperf-backup" > "$r.kcdperf-tmp" && mv -f "$r.kcdperf-tmp" "$r" ||
    die "Could not edit $r (backup: $r.kcdperf-backup)."
  echo "Proton prefix: override added (backup: user.reg.kcdperf-backup)."; PFX=1
done < <(steam_libs | while IFS= read -r lib; do
           r=$lib/steamapps/compatdata/379430/pfx/user.reg; [ -f "$r" ] && echo "$(cd "$(dirname "$r")" && pwd -P)/user.reg"
         done | awk '!seen[$0]++')
[ $PFXSEEN = 1 ] || echo "Proton prefix: none found for this game yet (it appears after the first start)."

# 3. Steam launch option (Steam must be closed)
LO=0; LOSKIP=
mapfile -t cfgs < <(user_configs)
if [ ${#cfgs[@]} -eq 0 ]; then
  echo "Steam launch option: no Steam user settings found."; LOSKIP=nosteam
elif ! command -v python3 >/dev/null; then
  echo "Steam launch option: python3 is missing, so it can't be added automatically."; LOSKIP=nopython
elif lo_py check "${cfgs[@]}"; then
  echo "Steam launch option: already set."; LO=1
elif ! wait_steam_closed; then
  LOSKIP=running
else
  echo "Steam launch option:"
  lo_py add "${cfgs[@]}" && LO=1
fi
if [ $LO = 0 ]; then
  SUG=
  [ ${#cfgs[@]} -gt 0 ] && command -v python3 >/dev/null && SUG=$(lo_py suggest "${cfgs[0]}" 2>/dev/null)
  [ -n "$SUG" ] || SUG='WINEDLLOVERRIDES="version=n,b" %command%'
  echo
  if [ $PFX = 1 ]; then
    echo "Steam launch option: not added. The patch still loads through the Proton prefix setting."
    echo "To add the launch option as well (it survives a reset of the prefix), close Steam and run this"
    echo "again, or add it yourself:"
  else
    echo "IMPORTANT: the patch will not load yet. Close Steam and run this again, or add the launch option yourself:"
  fi
  echo "  Steam: right-click Kingdom Come: Deliverance > Properties > General > Launch Options, and set it to:"
  echo "    $SUG"
  echo "  Heroic/Lutris: add the environment variable WINEDLLOVERRIDES with the value version=n,b"
fi

cp -f "$SELF/Uninstall-Linux-SteamDeck.sh" "$GAME/CPUPerformancePatch-Uninstall.sh" &&
  echo "Uninstaller copied to the game folder: CPUPerformancePatch-Uninstall.sh"
echo
echo "Done. Start the game. Bin/Win64/KCDPerf.log then says \"smart: on\". Settings: Bin/Win64/KCDPerf.ini (a text file)."
echo "If that file does not appear, the loader did not start: see README.txt."
