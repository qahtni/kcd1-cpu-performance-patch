CPU PERFORMANCE PATCH 1.0.0
Kingdom Come: Deliverance (Steam, 1.9.8)
Author: mrtaxerman

In towns the game is held back by the processor, not the graphics card: one
thread prepares every draw call, and a large share of them are for shadows
that are far away. This plugin removes two pieces of wasted work. No game
file is changed and the picture settings stay as they are.

1. FAR SHADOWS (on by default)
The sun's shadows are drawn in rings around you ("cascades"). The game
redraws the two outer rings, everything further than about 27 m, together
on every second frame: one frame is cheap, the next one is expensive. With
the patch the outer rings are redrawn every 8th and every 16th frame, never
both in the same frame, and at once when you move or turn far enough to
need it. Near shadows are untouched and still redrawn every frame.

2. TEXTURE LOADING (off by default, for graphics cards with a lot of memory)
On almost every texture load the game searches its whole list of loaded
textures for one to throw out, and that search never finds anything it can
use. Setting "trim 0" skips the search. Textures then stay loaded until the
game's own memory limit steps in, so the game uses about 3 GB more video
memory. Suggested for cards with 12 GB or more.

MEASURED
Riding through Rattay, the same recorded ride each time, 1080p:
- Windows, Ryzen 7 5800X3D + RTX 4070, Very High preset:
    90 fps  ->  112 fps with the shadow part (+24 %)  ->  119 fps with both parts (+32 %)
    frames slower than 16.7 ms: about 830  ->  about 100  ->  about 20 (of 8200)
- Linux (Bazzite, Proton), Radeon RX 9070 XT, high settings:
    71 fps  ->  82 fps with the shadow part  ->  91 fps with both parts
- Windows, Low preset: 177 fps -> 189 fps (few far shadows to save there).
Where the graphics card is the limit (open country, 4K) the gain is small.

WHAT YOU MAY NOTICE
The far shadows follow the sun and moving things in steps of 8 or 16 frames.
Shadows of people and animals further than about 27 m away can move a
little less smoothly. If that bothers you, set "stagger 2,4,16" in
KCDPerf.ini (about 3 % slower).

FILES IN THIS ARCHIVE
- install\KCDPerf.asi: the patch, a small plugin. When the game starts it
  finds the shadow and texture code in WHGame.dll and changes it in memory
  only.
- install\KCDPerf.ini: the settings, a text file with explanations.
- install\version.dll: Ultimate ASI Loader 10.0.2 by ThirteenAG (MIT
  license, install\Ultimate-ASI-Loader-LICENSE.txt). It loads .asi plugins.
- Install-Windows.bat, Uninstall-Windows.bat
- Install-Linux-SteamDeck.sh, Uninstall-Linux-SteamDeck.sh
  Plain text: open them in a text editor to see exactly what they do.

INSTALL (WINDOWS)
1. Extract the archive anywhere, for example to Downloads.
2. Double-click Install-Windows.bat in the extracted folder.
It finds the game in your Steam libraries and copies KCDPerf.asi,
KCDPerf.ini and version.dll to Bin\Win64. If it can't find the game, drag
the game folder onto Install-Windows.bat. Windows needs no launch options.

INSTALL ON STEAM DECK / LINUX
1. Switch to Desktop Mode and extract the archive anywhere, for example to
   Downloads.
2. Exit Steam: right-click the Steam icon in the taskbar > Exit Steam.
3. Right-click an empty spot in the extracted folder > Open Terminal Here,
   type
     bash Install-Linux-SteamDeck.sh
   and press Enter.
It finds the game in every Steam library (SD card included, also Flatpak
Steam) and in ~/Games (Heroic, Lutris), copies the three files to Bin/Win64
and tells Proton to load version.dll from the game folder. Proton prefers
its own built-in version.dll otherwise, and the patch would not load. It
does that in two places:
- the game's launch options in Steam get WINEDLLOVERRIDES="version=n,b" in
  front of what is already there. Steam must be closed for this, because
  Steam rewrites its settings when it exits. If Steam is still running, the
  installer asks you to close it, or you can skip that step;
- the game's Proton prefix gets the same setting (works without closing
  Steam, but only after the game has been started once).
If neither was possible, the installer says so and shows the exact launch
options to type in: right-click the game > Properties > General > Launch
Options. For a game somewhere else, add its folder:
  bash Install-Linux-SteamDeck.sh "/path/to/KingdomComeDeliverance"

INSTALL BY HAND (NO SCRIPT)
To open the game folder: in Steam, right-click Kingdom Come: Deliverance >
Manage > Browse local files.
1. Copy install\KCDPerf.asi, install\KCDPerf.ini and install\version.dll
   into Bin\Win64 (the folder with KingdomCome.exe).
2. Steam Deck / Linux only: set the game's launch options to
     WINEDLLOVERRIDES="version=n,b" %command%
   If there was something in the box already, keep it after %command%,
   for example: WINEDLLOVERRIDES="version=n,b" %command% -devmode

CHECK THAT IT WORKS
After starting the game, Bin\Win64\KCDPerf.log says
"smart: on, periods 1/2/8/16".

SETTINGS (Bin\Win64\KCDPerf.ini, read when the game starts)
  smart 1          far shadow patch on (smart 0 = off)
  stagger 2,8,16   redraw the shadow rings 2, 3 and 4 every 2nd, 8th and
                   16th frame (the game: 2,2,2)
  trim 1           texture search like the game (trim 0 = skip it, about
                   3 GB more video memory)
Everything off, same as the game: smart 0, stagger 2,2,2, trim 1.
Without the file the plugin uses the values above.

STEAM DECK / LINUX: THE HD SOUND PACK
If the free "HD Sound Pack" DLC is installed, the game unpacks a whole
45-74 MB sound bank each time it loads a sound, and under Proton that causes
short hitches (measured: frames slower than 20 ms halved without it). On
Linux and Steam Deck, turn the DLC off: Steam > right-click the game >
Properties > DLC > untick HD Sound Pack (or move Data/Sounds_HD.pak out of
the game folder). On Windows it makes no measurable difference.

OTHER MODS BY THE SAME AUTHOR
All of them can be installed together, in any order: 30 FPS Grass & Water
Fix, Native DLSS Support, Far Contact Shadows. The plugin mods share one
version.dll. Each uninstaller removes it only when no other .asi plugin is
left in Bin\Win64.

UNINSTALL
- With the script: in the game folder, double-click
  CPUPerformancePatch-Uninstall.bat (Windows), or run
    bash CPUPerformancePatch-Uninstall.sh
  (Steam Deck / Linux, with Steam closed). Uninstall-Windows.bat /
  Uninstall-Linux-SteamDeck.sh in the extracted archive do the same.
- By hand: delete KCDPerf.asi, KCDPerf.ini, KCDPerf.log and version.dll from
  Bin\Win64 (keep version.dll if you use other .asi mods). On Linux also
  remove WINEDLLOVERRIDES="version=n,b" from the launch options.

GOOD TO KNOW
- Made for the Steam version 1.9.8. On any other version the plugin finds
  nothing it knows, changes nothing and says so in KCDPerf.log.
- The far shadow patch needs the game's own setting e_ShadowsSparseGSMUpdate
  at 1, which is the default.
- Works next to other mods; pak mods and the Mods folder are not involved.
  If you already use another ASI loader as version.dll, the installer leaves
  it alone and the patch loads through it.
- Tested on Windows 11 and on Linux with Proton (Bazzite).

CHANGES
1.0.0
- First release.
