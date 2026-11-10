#!/usr/bin/env bash
# Builds dist/CPUPerformancePatch-1.0.0.7z (the archive published on Nexus and GitHub Releases).
# usage: release/build_release.sh UAL_DINPUT8_DLL UAL_LICENSE
#   UAL_DINPUT8_DLL = dinput8.dll from Ultimate ASI Loader v10.0.2, Ultimate-ASI-Loader-NoPDB_x64.zip
#                     (https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/tag/v10.0.2), shipped as version.dll
#   UAL_LICENSE     = that project's LICENSE file (MIT)
# Needs src/out/KCDPerf.asi (run src/build.sh first), release/KCDPerf.ini and 7z.
# Fills @ASI_SHA@ @UAL_SHA@ @ASI_SIZE@ @UAL_SIZE@ and inlines launch_option.py at @LAUNCH_OPTION_PY@.
# .bat/README get CRLF; .sh stay LF and executable.
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: $0 UAL_DINPUT8_DLL UAL_LICENSE"; exit 2; }
UAL=$(realpath "$1"); LIC=$(realpath "$2")
cd "$(dirname "$0")/.."
R=release; OUT=dist/CPUPerformancePatch-1.0.0.7z; S=dist/single/CPUPerformancePatch
ASI=src/out/KCDPerf.asi
[ -f "$ASI" ] || { echo "$ASI missing: run src/build.sh first"; exit 1; }
[ "$(sha256sum "$UAL" | cut -d' ' -f1)" = 57ec56390c92a18b82f58855e63c93985e254d1e29d5f75cbc28dc08f96c8a12 ] ||
  { echo "$UAL is not dinput8.dll of Ultimate ASI Loader v10.0.2 (x64)"; exit 1; }
ASI_SHA=$(sha256sum "$ASI" | cut -d' ' -f1); UAL_SHA=$(sha256sum "$UAL" | cut -d' ' -f1)
rm -rf dist/single; mkdir -p "$S/install"
cp -p "$ASI" "$S/install/KCDPerf.asi"; sed 's/\r$//; s/$/\r/' "$R/KCDPerf.ini" > "$S/install/KCDPerf.ini"; cp -p "$UAL" "$S/install/version.dll"
sed 's/\r$//; s/$/\r/' "$LIC" > "$S/install/Ultimate-ASI-Loader-LICENSE.txt"
fill() { sed -e "s/@ASI_SHA@/$ASI_SHA/; s/@UAL_SHA@/$UAL_SHA/; s/@ASI_SIZE@/$(stat -c %s "$ASI")/; s/@UAL_SIZE@/$(stat -c %s "$UAL")/" "$1"; }
for f in Install-Windows.bat Uninstall-Windows.bat README.txt; do fill "$R/$f" | sed 's/\r$//; s/$/\r/' > "$S/$f"; done
for f in Install-Linux-SteamDeck.sh Uninstall-Linux-SteamDeck.sh; do
  fill "$R/$f" | python3 -I -c 'import sys; s=sys.stdin.read(); py=open(sys.argv[1]).read().rstrip("\n"); assert s.count("@LAUNCH_OPTION_PY@\n")==1; sys.stdout.write(s.replace("@LAUNCH_OPTION_PY@\n", py+"\n"))' "$R/launch_option.py" > "$S/$f"
  chmod 755 "$S/$f"; bash -n "$S/$f"
done
! grep -l '@[A-Z_]*@' "$S"/*.sh "$S"/*.bat "$S"/README.txt
rm -f "$OUT"; (cd dist/single && 7z a -t7z -mx=9 "$OLDPWD/$OUT" CPUPerformancePatch >/dev/null)
7z t "$OUT" >/dev/null && echo "built $OUT $(stat -c %s "$OUT") bytes, sha256 $(sha256sum "$OUT" | cut -c1-12)"
echo "test the Linux installers: bash release/test_linux_install.sh $S"
