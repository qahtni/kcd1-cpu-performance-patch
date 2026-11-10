# CPU Performance Patch

A small plugin for **Kingdom Come: Deliverance** (the first game) that removes wasted processor work in towns: far sun shadows that are redrawn far more often than needed, and a texture search that never finds anything. Windows, Steam Deck and Linux. No game file is changed.

## What it does

In towns the game is held back by the processor, not the graphics card: one thread prepares every draw call, and a large share of them are for shadows that are far away.

**1. Far shadows (on by default).** The sun's shadows are drawn in rings around you ("cascades"). The game redraws the two outer rings, everything further than about 27 m, together on every second frame: one frame is cheap, the next one is expensive. With the patch the outer rings are redrawn every 8th and every 16th frame, never both in the same frame, and at once when you move or turn far enough to need it. Near shadows are untouched and still redrawn every frame.

**2. Texture loading (off by default).** On almost every texture load the game searches its whole list of loaded textures for one to throw out, and that search never finds anything it can use. `trim 0` skips the search. Textures then stay loaded until the game's own memory limit steps in, so the game uses about 3 GB more video memory. Suggested for cards with 12 GB or more.

How it works in detail: [HOW-IT-WORKS.md](HOW-IT-WORKS.md).

## Measured

Riding through Rattay, the same recorded ride each time, 1080p:

| Machine | Settings | Game | Shadow part | Both parts |
|---|---|---|---|---|
| Windows, Ryzen 7 5800X3D + RTX 4070 | Very High preset | 90 fps | 112 fps (+24 %) | 119 fps (+32 %) |
| Linux (Bazzite, Proton), Radeon RX 9070 XT | high | 71 fps | 82 fps (+15 %) | 91 fps (+27 %) |
| Windows, same PC | Low preset | 177 fps | not measured | 189 fps (+7 %) |

On the Windows PC at Very High, frames slower than 16.7 ms went from about 830 to about 100 with the shadow part and about 20 with both parts (of 8200). Where the graphics card is the limit (open country, 4K) the gain is small.

**What you may notice:** the far shadows follow the sun and moving things in steps of 8 or 16 frames. Shadows of people and animals further than about 27 m away can move a little less smoothly. `stagger 2,4,16` in `KCDPerf.ini` is gentler and about 3 % slower.

## Download

`CPUPerformancePatch-1.0.0.7z` from the Releases page. It contains:

- `install/KCDPerf.asi`: the patch. When the game starts it finds the shadow and texture code in `WHGame.dll` and changes it in memory only.
- `install/KCDPerf.ini`: the settings, a text file with explanations.
- `install/version.dll`: [Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader) 10.0.2 by ThirteenAG (MIT license, included). It loads `.asi` plugins.
- Installers and uninstallers for Windows and Steam Deck / Linux. They are plain text: open them in a text editor to see exactly what they do.

## Requirements

- Kingdom Come: Deliverance, Steam version 1.9.8. On any other version the plugin finds nothing it knows, changes nothing and says so in its log.
- Windows: nothing else.
- Steam Deck / Linux: Proton must load `version.dll` from the game folder: `WINEDLLOVERRIDES="version=n,b"`. The installer sets this for you.

## Install

- **Windows:** extract the archive anywhere and double-click **Install-Windows.bat**. It finds the game in your Steam libraries; if it can't, drag the game folder onto it.
- **Steam Deck / Linux:** extract the archive, exit Steam, open a terminal in the extracted folder and run `bash Install-Linux-SteamDeck.sh`. It copies the files and sets the launch option and the Proton prefix override.
- **By hand:** copy `install\KCDPerf.asi`, `install\KCDPerf.ini` and `install\version.dll` into `Bin\Win64` (the folder with `KingdomCome.exe`). Steam Deck / Linux only: set the launch options to `WINEDLLOVERRIDES="version=n,b" %command%`.

After starting the game, `Bin\Win64\KCDPerf.log` says `smart: on, periods 1/2/8/16`. The full instructions are in `README.txt` inside the archive.

## Settings

`Bin\Win64\KCDPerf.ini`, read when the game starts:

| Line | Meaning |
|---|---|
| `smart 1` | far shadow patch on (`smart 0` = off) |
| `stagger 2,8,16` | redraw shadow rings 2, 3 and 4 every 2nd, 8th and 16th frame (the game: `2,2,2`) |
| `trim 1` | texture search like the game (`trim 0` = skip it, about 3 GB more video memory) |

Everything off, same as the game: `smart 0`, `stagger 2,2,2`, `trim 1`. Without the file the plugin uses the values in the table.

## Steam Deck / Linux: the HD Sound Pack

If the free HD Sound Pack DLC is installed, the game unpacks a whole 45-74 MB sound bank each time it loads a sound, and under Proton that causes short hitches (measured: frames slower than 20 ms halved without it). On Linux and Steam Deck, turn the DLC off in Steam (Properties > DLC), or move `Data/Sounds_HD.pak` out of the game folder. On Windows it makes no measurable difference.

## Uninstall

`CPUPerformancePatch-Uninstall.bat` (Windows) or `bash CPUPerformancePatch-Uninstall.sh` (Steam Deck / Linux, Steam closed) in the game folder, or the uninstallers in the extracted archive. By hand: delete `KCDPerf.asi`, `KCDPerf.ini`, `KCDPerf.log` and `version.dll` from `Bin\Win64` (keep `version.dll` if you use other `.asi` mods).

## Compatibility and limits

- Made for the Steam version 1.9.8. Tested on Windows 11 and on Linux with Proton (Bazzite).
- Not tested: GOG and Epic copies (the plugin refuses code it does not recognise and logs it).
- Works together with the author's other mods, installed in any order: [30 FPS Grass & Water Fix](https://github.com/qahtni/kcd1-30fps-grass-fix), [Native DLSS Support](https://github.com/qahtni/kcd1-dlss) and [Far Contact Shadows](https://github.com/qahtni/kcd1-far-contact-shadows). The plugin mods share one `version.dll`; each uninstaller removes it only when no other `.asi` plugin is left.
- The far shadow patch needs the game's own setting `e_ShadowsSparseGSMUpdate` at 1, which is the default.

## Building from source

Needs mingw-w64 (x86_64-w64-mingw32-gcc).

```sh
src/build.sh                                                        # -> src/out/KCDPerf.asi
release/build_release.sh /path/to/dinput8.dll /path/to/UAL-LICENSE   # -> dist/CPUPerformancePatch-1.0.0.7z
bash release/test_linux_install.sh dist/single/CPUPerformancePatch  # installer tests against fake Steam setups
```

`build_release.sh` takes `dinput8.dll` from `Ultimate-ASI-Loader-NoPDB_x64.zip` of [Ultimate ASI Loader v10.0.2](https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/tag/v10.0.2) and that project's license file; neither is stored in this repository.

## Credits

- By mrtaxerman.
- [Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader) by ThirteenAG (MIT license), see [THIRD_PARTY.md](THIRD_PARTY.md).

## License

The code in this repository is released into the public domain under [The Unlicense](LICENSE). Game files are not included and not covered; `src/kcd_perf.c` holds short byte patterns of the game's `WHGame.dll`, used only to find the code it changes.
