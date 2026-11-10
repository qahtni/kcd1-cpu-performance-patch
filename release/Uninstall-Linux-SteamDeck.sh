#!/usr/bin/env bash
# CPU Performance Patch 1.0.0 - uninstaller for Steam Deck / Linux (Proton).
#   bash CPUPerformancePatch-Uninstall.sh            (in the game folder, put there by the installer)
#   bash Uninstall-Linux-SteamDeck.sh [game folder] (in the extracted archive)
# What it does (nothing else):
#   1. Checks the game is closed.
#   2. Deletes Bin/Win64/KCDPerf.asi, KCDPerf.ini, KCDPerf.log and KCDPerf.cmd.
#   3. Deletes Bin/Win64/version.dll if it is the loader this mod installed and no other .asi
#      plugin is left there (another plugin would still need it).
#   4. If the loader was deleted: removes the line "version"="native,builtin" from the game's
#      Proton prefix and WINEDLLOVERRIDES="version=n,b" from its Steam launch options (Steam has to
#      be closed for that; backups kept).
set -u

if [ ! -t 1 ] && [ -z "${KCP_TERM:-}" ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
  command -v konsole >/dev/null && KCP_TERM=1 exec konsole --hold -e bash "$0" "$@"
  command -v xterm >/dev/null && KCP_TERM=1 exec xterm -hold -e bash "$0" "$@"
fi

UAL_SHA=@UAL_SHA@   # the version.dll this mod installs
LINE='"version"="native,builtin"'
die() { echo; echo "ERROR: $*"; echo "Nothing more was changed."; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
is_game() { [ -f "$1/Bin/Win64/KingdomCome.exe" ]; }
steam_libs() {
  local r
  for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root" \
           "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
    [ -d "$r/steamapps" ] || continue
    echo "$r"; sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$r/steamapps/libraryfolders.vdf" 2>/dev/null
  done
}
find_game() {
  local d lib
  for d in "$SELF" "$SELF/../.."; do is_game "$d" && { (cd "$d" && pwd -P); return; }; done
  steam_libs | while IFS= read -r lib; do d=$lib/steamapps/common/KingdomComeDeliverance; is_game "$d" && (cd "$d" && pwd -P); done
  find "$HOME/Games" -maxdepth 6 -type f -path '*/Bin/Win64/KingdomCome.exe' 2>/dev/null | sed 's|/Bin/Win64/KingdomCome.exe$||'
}
steam_roots() {
  local r
  for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root" \
           "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
    [ -d "$r/userdata" ] && (cd "$r" && pwd -P)
  done | awk '!seen[$0]++'
}
user_configs() {
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
wait_steam_closed() {
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
prefix_busy() {
  local p
  for p in $(pgrep -x wineserver); do
    tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qxF "WINEPREFIX=$1" && return 0
  done
  return 1
}

SELF=$(cd "$(dirname "$0")" && pwd -P)
echo "CPU Performance Patch 1.0.0 - uninstall"
if [ $# -ge 1 ]; then
  is_game "$1" || die "No Kingdom Come: Deliverance in $1 (it needs Bin/Win64/KingdomCome.exe)."
  GAME=$(cd "$1" && pwd -P)
else
  mapfile -t found < <(find_game | awk '!seen[$0]++')
  [ ${#found[@]} -ge 1 ] || die "Kingdom Come: Deliverance not found. Run it with the game folder as the first argument."
  [ ${#found[@]} -eq 1 ] || die "Found more than one copy of the game. Run it with the game folder as the first argument."
  GAME=${found[0]}
fi
echo "Game folder: $GAME"
B=$GAME/Bin/Win64
pgrep -f '[K]ingdomCome\.exe' >/dev/null && die "The game is running. Close it first."

rm -f "$B/KCDPerf.asi" "$B/KCDPerf.ini" "$B/KCDPerf.log" "$B/KCDPerf.cmd" "$B/KCDPerf.frames" && echo "Plugin: Bin/Win64/KCDPerf.asi removed."
LOADER_GONE=0
if [ ! -e "$B/version.dll" ]; then
  echo "Loader: no version.dll there."; LOADER_GONE=1
elif [ "$(sha "$B/version.dll")" != "$UAL_SHA" ]; then
  echo "Loader: Bin/Win64/version.dll is not the file this mod installs. Left alone."
elif [ -n "$(find "$B" "$B/scripts" "$B/plugins" -maxdepth 1 -iname '*.asi' 2>/dev/null | head -n 1)" ]; then
  echo "Loader: another .asi plugin is still in Bin/Win64. version.dll left in place for it."
else
  rm -f "$B/version.dll" "$B/Ultimate-ASI-Loader-LICENSE.txt" && echo "Loader: Bin/Win64/version.dll removed."; LOADER_GONE=1
fi

if [ $LOADER_GONE = 1 ]; then
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    LC_ALL=C grep -qxF "$LINE" "$r" || continue
    pfx=$(dirname "$r")
    for i in 1 2 3 4 5 6 7 8 9 10; do prefix_busy "$pfx" || break; read -r -t 1 _ < /dev/null; done
    prefix_busy "$pfx" && die "Proton is still running for this game. Wait a few seconds and run this again."
    cp -p "$r" "$r.kcdperf-backup" || die "Could not back up $r."
    LC_ALL=C awk -v line="$LINE" '
      /^\[Software\\\\Wine\\\\DllOverrides\]/ {f=1}
      f && /^$/ {f=0}
      f && $0 == line {next}
      {print}' "$r.kcdperf-backup" > "$r.kcdperf-tmp" && mv -f "$r.kcdperf-tmp" "$r" ||
      die "Could not edit $r (backup: $r.kcdperf-backup)."
    echo "Proton prefix: override removed (backup: user.reg.kcdperf-backup)."
  done < <(steam_libs | while IFS= read -r lib; do
             r=$lib/steamapps/compatdata/379430/pfx/user.reg; [ -f "$r" ] && echo "$(cd "$(dirname "$r")" && pwd -P)/user.reg"
           done | awk '!seen[$0]++')
  mapfile -t cfgs < <(user_configs)
  if [ ${#cfgs[@]} -gt 0 ] && command -v python3 >/dev/null && { lo_py check "${cfgs[@]}"; [ $? = 3 ]; }; then
    echo "Steam launch option: not set, nothing to remove."
  elif [ ${#cfgs[@]} -gt 0 ]; then
    if ! command -v python3 >/dev/null || ! wait_steam_closed; then
      echo "Steam launch option: not changed. Remove WINEDLLOVERRIDES=\"version=n,b\" from the game's launch options"
      echo "yourself (Properties > General > Launch Options). Left in place it does nothing without the loader."
    else
      echo "Steam launch option:"
      lo_py remove "${cfgs[@]}"
    fi
  fi
fi

rm -f "$GAME/CPUPerformancePatch-Uninstall.sh"
echo
echo "Done. The game draws its far shadows and streams its textures the stock way again."
