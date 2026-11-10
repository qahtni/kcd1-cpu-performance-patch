#!/usr/bin/env bash
# Unit tests for Install-/Uninstall-Linux-SteamDeck.sh against fake Steam setups (no real game,
# no real Steam is touched: HOME points into a temp folder, pgrep is a stand-in).
#   bash test_linux_install.sh BUILT_FOLDER     (dist/single/CPUPerformancePatch, made by build_release.sh)
set -u
PKG=$(cd "$1" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; [ -n "${OUT:-}" ] && sed 's/^/       | /' "$T/out" | tail -n 25; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
mkdir -p "$T/bin"
cat > "$T/bin/pgrep" <<'P'
#!/bin/bash
case "$1 $2" in
  "-x steam") n=$(cat "$FAKE/steam_left" 2>/dev/null || echo 0)
              if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$FAKE/steam_left"; echo 4242; exit 0; fi; exit 1;;
  "-f "*) [ -e "$FAKE/game" ] && { echo 4343; exit 0; }; exit 1;;
esac
exit 1
P
chmod 755 "$T/bin/pgrep"

setup() {  # fresh fake home: Steam root + second library holding the game and its prefix
  rm -rf "$T/h" "$T/lib2" "$T/fake"; mkdir -p "$T/fake"
  H=$T/h; ST=$H/.local/share/Steam; L2=$T/lib2
  GAME=$L2/steamapps/common/KingdomComeDeliverance; B=$GAME/Bin/Win64
  REG=$L2/steamapps/compatdata/379430/pfx/user.reg
  LC1=$ST/userdata/111/config/localconfig.vdf; LC2=$ST/userdata/222/config/localconfig.vdf
  mkdir -p "$ST/steamapps" "$B" "$(dirname "$REG")" "$(dirname "$LC1")" "$(dirname "$LC2")" "$H/.steam"
  ln -s "$ST" "$H/.steam/steam"
  printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' "$ST" "$L2" > "$ST/steamapps/libraryfolders.vdf"
  echo exe > "$B/KingdomCome.exe"
  printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n\n#arch=win64\n\n[Control Panel\\\\Desktop] 1793000000\n#time=1dc4e0000000000\n"ActiveWndTrkTimeout"=dword:00000000\n\n[Software\\\\Wine\\\\DllOverrides] 1793000000\n#time=1dc4e0000000000\n"atl100"="native,builtin"\n"msvcp140"="native,builtin"\n\n[Software\\\\Wine\\\\Drivers] 1793000000\n"Audio"="pulse"\n' > "$REG"
  for u in 1 2; do
    f=$LC1; [ $u = 2 ] && f=$LC2
    {
      printf '"UserLocalConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n\t\t\t\t"apps"\n\t\t\t\t{\n'
      printf '\t\t\t\t\t"220"\n\t\t\t\t\t{\n\t\t\t\t\t\t"LastPlayed"\t\t"1700000000"\n\t\t\t\t\t\t"LaunchOptions"\t\t"-novid \\"quoted\\""\n\t\t\t\t\t}\n'
      [ $u = 1 ] && printf '\t\t\t\t\t"379430"\n\t\t\t\t\t{\n\t\t\t\t\t\t"LastPlayed"\t\t"1793894029"\n\t\t\t\t\t\t"cloud"\n\t\t\t\t\t\t{\n\t\t\t\t\t\t\t"last_sync_state"\t\t"synchronized"\n\t\t\t\t\t\t}\n\t\t\t\t\t\t"LaunchOptions"\t\t"+exec user.cfg -devmode"\n\t\t\t\t\t\t"Playtime2wks"\t\t"969"\n\t\t\t\t\t}\n'
      printf '\t\t\t\t}\n\t\t\t\t"other"\t\t"x"\n\t\t\t}\n\t\t}\n\t}\n\t"friends"\n\t{\n\t\t"x"\t\t"y"\n\t}\n}\n'
    } > "$f"
  done
  touch -d "1 hour ago" "$LC2"   # the account in use is the newest one
  cp -p "$REG" "$T/fake/reg.orig"; cp -p "$LC1" "$T/fake/lc1.orig"; cp -p "$LC2" "$T/fake/lc2.orig"
}
run() {  # run SCRIPT [args]; stdin from $IN if set; output in $T/out, status in RC
  env -u DISPLAY -u WAYLAND_DISPLAY HOME="$H" PATH="$T/bin:$PATH" FAKE="$T/fake" KCP_TERM=1 bash "$@" < "${IN:-/dev/null}" > "$T/out" 2>&1; RC=$?
}
run_tty() {  # same with a terminal (script), answers in $1
  local cmd; printf -v cmd '%q ' env -u DISPLAY -u WAYLAND_DISPLAY HOME="$H" PATH="$T/bin:$PATH" FAKE="$T/fake" KCP_TERM=1 bash "$@"
  { sleep 1; printf '%s\n' "$ANSWER"; sleep 3; } | script -qec "$cmd" /dev/null > "$T/out" 2>&1; RC=$?
}
cat > "$T/lo.py" <<'P'
import re, sys
s = open(sys.argv[1]).read()
i = s.find('"379430"')
if i < 0: print("<none>"); sys.exit()
d, j = 0, s.index("{", i)
for k in range(j, len(s)):
    d += {"{": 1, "}": -1}.get(s[k], 0)
    if d == 0: break
m = re.search(r'"LaunchOptions"\s+"((?:[^"\\]|\\.)*)"', s[j:k])
print(m.group(1) if m else "<none>")
P
lo() { python3 -I "$T/lo.py" "$1"; }
WANT='WINEDLLOVERRIDES=\"version=n,b\" %command% +exec user.cfg -devmode'
asi_sha() { sha256sum "$PKG/install/$1" | cut -d' ' -f1; }
regline() { grep -cxF '"version"="native,builtin"' "$REG"; }
OUT=1

echo "1. install, Steam closed"
setup; run "$PKG/Install-Linux-SteamDeck.sh"
check "exit 0" '[ $RC = 0 ]'
check "plugin + loader copied" '[ "$(sha256sum "$B/KCDPerf.asi" | cut -d" " -f1)" = "$(asi_sha KCDPerf.asi)" ] && [ "$(sha256sum "$B/version.dll" | cut -d" " -f1)" = "$(asi_sha version.dll)" ]'
check "prefix line added once, inside DllOverrides" '[ "$(regline)" = 1 ] && awk "/DllOverrides/{f=1} f&&/^\$/{exit} f&&/\"version\"=\"native,builtin\"/{ok=1} END{exit !ok}" "$REG"'
check "prefix: only that line changed" '[ "$(diff "$T/fake/reg.orig" "$REG" | grep -c "^[<>]")" = 1 ]'
check "launch option user 111" '[ "$(lo "$LC1")" = "$WANT" ]'
check "user 111: only that line changed" '[ "$(diff "$T/fake/lc1.orig" "$LC1" | grep -c "^[<>]")" = 2 ]'
check "launch option user 222 (block created)" '[ "$(lo "$LC2")" = "WINEDLLOVERRIDES=\\\"version=n,b\\\" %command%" ]'
check "other game untouched" 'grep -qF "\"-novid \\\"quoted\\\"\"" "$LC1"'
check "backups kept" '[ -f "$REG.kcdperf-backup" ] && [ -f "$LC1.kcdperf-backup" ]'
check "uninstaller in game folder" '[ -x "$GAME/CPUPerformancePatch-Uninstall.sh" ] || [ -f "$GAME/CPUPerformancePatch-Uninstall.sh" ]'
cp -p "$LC1" "$T/fake/lc1.after"

echo "2. install again"
run "$PKG/Install-Linux-SteamDeck.sh"
check "exit 0, says already set" '[ $RC = 0 ] && grep -q "already set" "$T/out"'
check "no second prefix line" '[ "$(regline)" = 1 ]'
check "launch options unchanged" 'cmp -s "$LC1" "$T/fake/lc1.after"'

echo "3. uninstall from the game folder"
run "$GAME/CPUPerformancePatch-Uninstall.sh"
check "exit 0" '[ $RC = 0 ]'
check "files gone" '[ ! -e "$B/KCDPerf.asi" ] && [ ! -e "$B/version.dll" ] && [ ! -e "$B/Ultimate-ASI-Loader-LICENSE.txt" ] && [ ! -e "$GAME/CPUPerformancePatch-Uninstall.sh" ]'
check "prefix back to the original bytes" 'cmp -s "$REG" "$T/fake/reg.orig"'
check "user 111 back to the original bytes" 'cmp -s "$LC1" "$T/fake/lc1.orig"'
check "user 222 has no override left" '! grep -q WINEDLLOVERRIDES "$LC2"'
check "game exe still there" '[ -f "$B/KingdomCome.exe" ]'

echo "4. install, Steam running, no terminal"
setup; echo 1000 > "$T/fake/steam_left"; run "$PKG/Install-Linux-SteamDeck.sh"
check "exit 0, prefix set" '[ $RC = 0 ] && [ "$(regline)" = 1 ]'
check "launch options not touched" 'cmp -s "$LC1" "$T/fake/lc1.orig" && cmp -s "$LC2" "$T/fake/lc2.orig"'
check "tells the user, with their full launch line" 'grep -q "still loads through the Proton prefix" "$T/out" && grep -qF "WINEDLLOVERRIDES=\"version=n,b\" %command% +exec user.cfg -devmode" "$T/out"'

echo "4b. install again with Steam running, launch option already there"
setup; run "$PKG/Install-Linux-SteamDeck.sh"; echo 1000 > "$T/fake/steam_left"; run "$PKG/Install-Linux-SteamDeck.sh"
check "says already set, no prompt, no note" '[ $RC = 0 ] && grep -q "launch option: already set" "$T/out" && ! grep -q "Steam is running" "$T/out"'
echo "4c. uninstall, Steam running, launch option never set"
setup; echo 1000 > "$T/fake/steam_left"; run "$PKG/Install-Linux-SteamDeck.sh"; run "$GAME/CPUPerformancePatch-Uninstall.sh"
check "nothing to remove, no prompt" '[ $RC = 0 ] && grep -q "not set, nothing to remove" "$T/out" && ! grep -q "Steam is running" "$T/out" && cmp -s "$REG" "$T/fake/reg.orig"'

echo "5. install, Steam running, game never started (no prefix)"
setup; rm -rf "$T/lib2/steamapps/compatdata"; echo 1000 > "$T/fake/steam_left"; run "$PKG/Install-Linux-SteamDeck.sh"
check "exit 0, IMPORTANT note" '[ $RC = 0 ] && grep -q "IMPORTANT: the patch will not load yet" "$T/out"'

echo "6. install, no prefix, Steam closed"
setup; rm -rf "$T/lib2/steamapps/compatdata"; run "$PKG/Install-Linux-SteamDeck.sh"
check "launch option set, no IMPORTANT note" '[ $RC = 0 ] && [ "$(lo "$LC1")" = "$WANT" ] && ! grep -q IMPORTANT "$T/out"'

if command -v script >/dev/null; then
  echo "7. install in a terminal, Steam running, user closes it and presses Enter"
  setup; echo 1 > "$T/fake/steam_left"; ANSWER=""; run_tty "$PKG/Install-Linux-SteamDeck.sh"
  check "asked to close Steam" 'grep -q "Close Steam now" "$T/out"'
  check "launch option set after Enter" '[ "$(lo "$LC1")" = "$WANT" ]'
  echo "8. install in a terminal, Steam running, user types S"
  setup; echo 1000 > "$T/fake/steam_left"; ANSWER=s; run_tty "$PKG/Install-Linux-SteamDeck.sh"
  check "skipped, launch options untouched, told what to type" 'cmp -s "$LC1" "$T/fake/lc1.orig" && grep -q "add it yourself" "$T/out"'
else
  echo "7./8. skipped: no 'script' command for a terminal"
fi

echo "9. game running"
setup; touch "$T/fake/game"; run "$PKG/Install-Linux-SteamDeck.sh"
check "refused, nothing changed" '[ $RC = 1 ] && [ ! -e "$B/KCDPerf.asi" ] && cmp -s "$REG" "$T/fake/reg.orig" && cmp -s "$LC1" "$T/fake/lc1.orig"'

echo "10. another version.dll already there"
setup; echo other > "$B/version.dll"; run "$PKG/Install-Linux-SteamDeck.sh"
check "left alone, plugin copied" '[ $RC = 0 ] && [ "$(cat "$B/version.dll")" = other ] && [ -f "$B/KCDPerf.asi" ] && grep -q "different file. Left alone" "$T/out"'
run "$GAME/CPUPerformancePatch-Uninstall.sh"
check "uninstall keeps the other version.dll" '[ "$(cat "$B/version.dll")" = other ] && [ ! -e "$B/KCDPerf.asi" ]'

echo "11. damaged download"
setup; cp -a "$PKG" "$T/pkg"; echo x >> "$T/pkg/install/KCDPerf.asi"; run "$T/pkg/Install-Linux-SteamDeck.sh"; rm -rf "$T/pkg"
check "refused, nothing changed" '[ $RC = 1 ] && [ ! -e "$B/KCDPerf.asi" ] && grep -q damaged "$T/out"'

echo "12. uninstall while another .asi plugin remains"
setup; run "$PKG/Install-Linux-SteamDeck.sh"; echo p > "$B/Other.asi"; run "$GAME/CPUPerformancePatch-Uninstall.sh"
check "loader, prefix line and launch option kept" '[ -f "$B/version.dll" ] && [ "$(regline)" = 1 ] && [ "$(lo "$LC1")" = "$WANT" ] && [ ! -e "$B/KCDPerf.asi" ]'

echo "13. prefix already sets version.dll differently"
setup; sed -i 's/^"atl100"=/"version"="builtin"\n"atl100"=/' "$REG"; cp -p "$REG" "$T/fake/reg.orig"; run "$PKG/Install-Linux-SteamDeck.sh"
check "prefix left alone, launch option still set" 'cmp -s "$REG" "$T/fake/reg.orig" && [ "$(lo "$LC1")" = "$WANT" ]'

echo "14. uninstall with Steam running, no terminal"
setup; run "$PKG/Install-Linux-SteamDeck.sh"; echo 1000 > "$T/fake/steam_left"; run "$GAME/CPUPerformancePatch-Uninstall.sh"
check "files + prefix removed, launch option left, user told" '[ ! -e "$B/version.dll" ] && cmp -s "$REG" "$T/fake/reg.orig" && [ "$(lo "$LC1")" = "$WANT" ] && grep -q "Remove WINEDLLOVERRIDES" "$T/out"'

echo "15. settings file"
setup; run "$PKG/Install-Linux-SteamDeck.sh"
check "KCDPerf.ini copied" 'cmp -s "$B/KCDPerf.ini" "$PKG/install/KCDPerf.ini"'
echo "trim 0" > "$B/KCDPerf.ini"; run "$PKG/Install-Linux-SteamDeck.sh"
check "an existing KCDPerf.ini is kept on a second install" '[ $RC = 0 ] && [ "$(cat "$B/KCDPerf.ini")" = "trim 0" ] && grep -q "already there. Kept" "$T/out"'
run "$GAME/CPUPerformancePatch-Uninstall.sh"
check "uninstall removes it" '[ ! -e "$B/KCDPerf.ini" ] && [ ! -e "$B/KCDPerf.asi" ]'

echo "16. next to the other plugin mods (grass + water fix, Native DLSS Support)"
setup; for f in KCDWater.asi KCDDLSS.asi KCDGrassFix.asi.off; do echo x > "$B/$f"; done; cp "$PKG/install/version.dll" "$B/version.dll"; run "$PKG/Install-Linux-SteamDeck.sh"
check "installed, the others untouched" '[ $RC = 0 ] && [ -f "$B/KCDPerf.asi" ] && [ "$(cat "$B/KCDWater.asi")" = x ] && [ "$(cat "$B/KCDDLSS.asi")" = x ] && [ "$(cat "$B/KCDGrassFix.asi.off")" = x ]'
run "$GAME/CPUPerformancePatch-Uninstall.sh"
check "uninstall: the others, loader, prefix line and launch option kept" '[ $RC = 0 ] && [ ! -e "$B/KCDPerf.asi" ] && [ "$(cat "$B/KCDWater.asi")" = x ] && [ "$(cat "$B/KCDDLSS.asi")" = x ] && [ "$(cat "$B/KCDGrassFix.asi.off")" = x ] && [ -f "$B/version.dll" ] && [ "$(regline)" = 1 ] && [ "$(lo "$LC1")" = "$WANT" ]'

echo
echo "passed $PASS, failed $FAIL"
[ $FAIL = 0 ]
