# How it works

Everything here was measured on the Steam version 1.9.8 with a recorded ride through Rattay, replayed with the game's own time demo.

## The cause: two far shadow rings redrawn on every second frame

The sun's shadow is split into five cascades, each covering about three times the distance of the one before (roughly 3, 9, 27, 81 and 243 m). The engine has a "sparse update" table that says how often each cascade is redrawn: cascades 0 and 1 every frame, cascades 2, 3 and 4 every 2nd frame. Cascades 3 and 4 share the same frame. At the Very High preset they carry about 1900 and 4700 shadow casters per redraw, so every second frame pays for about 6600 extra objects and the frame times alternate (11 ms / 17 ms in a town on the test PC). The thread that submits draw calls is the limit there, so this shows up directly as frame rate.

Raising the periods in the table does nothing in the stock game: on a skipped frame the game empties the cascade's caster list, and an empty list forbids the next skip. So a cascade is redrawn every 2nd frame whatever its period says.

## The fix

`KCDPerf.asi` replaces the call that sets up each sun cascade (`InitShadowFrustum_SUN_Conserv`) with its own decision per cascade and frame:

- a cascade that is not due keeps its old shadow map and its old projection, and the game's caster gathering for it is skipped;
- cascade 2 is redrawn every 2nd frame (as before), cascade 3 every 8th, cascade 4 every 16th, on different frames;
- a cascade is redrawn early, but not more often than every 2nd frame, when the camera has moved more than 5 % of the cascade's size or turned more than 10 degrees since its last redraw;
- at most one of the far cascades is redrawn per frame; the other waits one frame;
- a cascade that the engine's own shadow cache handles is never skipped.

The "empty list forbids the next skip" jump is removed (6 bytes), because the plugin itself knows whether a cascade has been drawn. Everything is done in memory; the code sites are found by byte patterns that must match exactly once, otherwise nothing is changed.

## The texture search

`CPlanningTextureStreamer::TrimTexture` walks the whole list of trimmable textures looking for one in the same pool, on nearly every mip request, because the pool probe before it can never succeed in this build. `trim 0` makes the function return "nothing found" at once (one aligned 8-byte write). The request then takes the normal allocation path, and the streamer's own memory-pressure trimming still works. The texture pool then fills up to its limit instead of staying about 3 GB below it.

## What was tried and left out

- The engine's own shadow cache (`r_ShadowsCache`): only 1.5 to 5 % on top, with visible defects (walls under eaves darkening during each refill, no character shadows from cached cascades).
- Skipping empty per-draw state calls on the render thread, changing the batching mode, occlusion settings: no measurable gain.
- Repacking the game's archives without compression: no confirmed gain.

## Testing

- The release plugin was run on Linux (Bazzite, Proton) with no settings file: all code sites found, cascade 3 redrawn 1 frame in 8 and cascade 4 1 frame in 16 while standing, settings switched while the game ran, clean exit. The same code with its measuring tools was benchmarked on Windows 11 and Bazzite (numbers in the README).
- [release/test_linux_install.sh](release/test_linux_install.sh): tests of the Linux installer and uninstaller against fake Steam setups (Steam running or closed, several libraries, launch options already set, a foreign `version.dll`, a damaged download, the settings file kept on update, the other plugin mods installed next to it).
