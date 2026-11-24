# Progress

## November 23, 2026 · v0.3 build 3

Added portable stage photos with opacity and locking, fixture-by-fixture cue edits with Simulation preview, soundtrack waveforms, timeline zoom, and manual beat and section markers with optional snapping. Cues can be moved in groups and duplicated at the playhead, with a single undo per action. Build 3 opens existing shows and setups and writes format 2. See [the design tools guide](DESIGN_TOOLS.md).

Xcode 27.0 beta 5 (27A5237l) passed all ten Release tests, including package and setup round trips, cue draft preview and apply, group moves, duplication, undo, and snapping. The ad-hoc signed universal app and ZIP passed strict signature verification and file comparisons. Visual acceptance remains pending.

## November 23, 2026 · v0.2 build 2

Added an opt-in Wi-Fi phone remote with QR pairing, Mac approval, revocation, transport, GO, blackout, and simulated fixture status. Made the separate Light Show Studio GitHub repository public at the user’s request. Added daily and manual stable-release checks. The public feed requires no token and reported that no full release had been published. The Xcode 27A5237l Release run passed seven tests, including localhost pairing and control, and the universal ZIP passed strict signature and file comparison. Phone browser and visual acceptance remain pending. See [phone and update instructions](PHONE_AND_UPDATES.md).

## November 23, 2026 · v0.1 build 1

Implemented the standalone Home, Program, and Show Mode workspaces. The first build adds controller and fixture patching, fixture groups and a stage schematic, portable show files with their soundtrack, reusable setup files, saved looks, cue recording and review, chases, moving-head paths, and an armed Simulation workspace. The app has its own bundle ID, project format, settings and icon.

Xcode 27.0 beta 5 (27A5237l) passed four Release tests covering setup reuse, patch and cue conflict handling, movement and chases, and recording against the real AVPlayer clock. The recording test used muted audio. It saved and reopened the show after removing its original song, then checked both simulated cue transitions. The ad-hoc signed universal app and ZIP passed strict signature and file comparisons. Visual and listening acceptance and physical output remain pending.
