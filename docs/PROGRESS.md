# Progress

## November 24, 2026 · v0.3 build 11

Fixed clipping in the docked Inspector. The scroll content follows the panel width, the tab labels fit smaller widths, and fixture patch fields and action buttons reflow as the panel narrows.

Xcode 27.0 beta 5 (27A5237l) passed all 22 Release tests. Offscreen macOS renders of the switched-plug Inspector at 235, 300, and 360 points show both sides of the form and all action buttons. The universal app and ZIP passed strict signature verification and file comparisons.

## November 24, 2026 · v0.3 build 10

Added **Edit Fixture…** to fixture rows in the Fixtures panel and Timeline. The dialog shares fields and validation with the Fixture inspector, preserves stage placement and cue assignments, and saves the patch in one undoable step.

Xcode 27.0 beta 5 (27A5237l) passed all 22 Release tests. The new test checks patch conflicts, applying changes to the intended fixture, preserving geometry and cue assignments, and undo. The universal app and ZIP passed strict signature verification and file comparisons. Right-click interaction still needs a hands-on check.

## November 24, 2026 · v0.3 build 9

Added Show Overview, Cue Editing, and Fixture Patch presets. Program has a layout picker, panel expansion preserves the saved arrangement, and the Window menu can show or hide individual panels. The new Show and Timeline command menus share the existing transport and editor state. Help has a searchable shortcut reference. The one-word chat commands are recorded in [the project guide](CHAT_COMMANDS.md).

Xcode 27.0 beta 5 (27A5237l) passed all 21 Release tests. The new tests check the new presets, restored panels, timeline commands across layouts, and Show Mode readiness. The universal app and ZIP passed strict signature verification and file comparisons. Visual acceptance remains pending.

## November 24, 2026 · v0.3 build 8 local preview

Added **Window → Layouts** with **Stage Design** for fixtures, stage preview, and inspector, and **Show Timing** for the timeline. The panel menu opens another editor panel to the left, right, above, or below, and closes panels. Drag dividers to resize. The app remembers each preset’s arrangement in preferences, and **Reset Layout** restores the active preset. Both layouts use the same show, playhead, and selection. Show files continue to use format 3.

Xcode 27.0 beta 5 (27A5237l) built the universal macOS 15 Release app with the `LightShowStudio` scheme. The app and the extracted ZIP passed strict signature verification and a file comparison. Running the Release test bundle directly passed 18 of 19 tests, including all three new layout tests. The tests cover docking on all four sides, panel closing, divider persistence, independent preset reset, and inserting, moving, and trimming clips in the same show across layout changes. The phone pairing test also failed on unchanged build 7 in this session, where loopback listener creation is denied. Xcode’s test launcher was blocked from reaching its test manager service.

A fresh Release run with the pinned Xcode passed all 19 tests, including the local phone pairing test and the three layout tests. See [build history](BUILD_HISTORY.md) for the archived downloads and source tags.

Hands-on verification is pending. Switch between presets with a show open and unsaved changes, and confirm the playhead and selections carry over. Dock panels on all four sides, drag the dividers, close a panel, reopen the app, and reset each layout. In Show Timing and in a docked timeline, check the waveform and rows, drop a palette command, drag its center, and trim both edges. Verify that the underlying cue resumes when the clip ends.

## November 24, 2026 · v0.3 build 7

New timeline drops create five-second clips that can be moved from the center or trimmed at either end. Clips stop at their end and let the underlying program resume. The latest-started overlapping clip takes precedence. Older cue points keep their behavior. Shows saved by this build use format 3, and fixture setups continue to use format 2.

Xcode 27.0 beta 5 (27A5237l) passed all sixteen Release tests. The new tests cover default length, overlap, restoring underlying cues, trims, moving and undoing clips, soundtrack boundaries, and reopening saved shows. The universal app and ZIP passed strict signature verification and file comparisons. Visual acceptance remains pending.

## November 24, 2026 · v0.3 build 6

Added a fixture-by-fixture timeline with a shared waveform, fixed-size command tiles, and color bands. The timeline palette adds power, color, dimmer, fade, chase, and movement commands where supported. Individual tiles retime one fixture from a cue, while the Cue Groups row still moves whole cues. Existing shows open on the new rows. The Program divider can give the timeline more room.

Xcode 27.0 beta 5 (27A5237l) passed all fourteen Release tests. The new tests cover compatibility, command playback, save data, collision rollback, single-fixture retiming, grouped retiming, and undo. The universal app and ZIP passed strict signature verification and file comparisons. Visual acceptance remains pending.

## November 24, 2026 · v0.3 build 5

Switched plugs using the Light Strip icon now draw a path on the stage. Drag the endpoints to adjust the strip, double-click a segment to add a bend, or Control-click a point to remove it. The geometry appears in Show Mode and is saved with shows and fixture setups.

Xcode 27.0 beta 5 (27A5237l) passed all twelve Release tests. The new test checks default and edited geometry, invalid points, relay assignment, undo, and persistence. The universal app and ZIP passed strict signature verification and file comparisons.

User feedback: the adjustable switched strip worked in the app.

## November 24, 2026 · v0.3 build 4

Added nine Switched Plug icons in the Fixture inspector. The selected icon follows each plug in the sidebar, stage, and Show Mode. Show and setup files preserve the choice, and older fixtures default to Plug. Icon choices leave the relay address and cue states intact.

Xcode 27.0 beta 5 (27A5237l) passed all eleven Release tests. The new test checks symbol availability, older fixture data, show and setup saves, cue playback, and undo. The universal app and ZIP passed strict signature verification and file comparisons. Visual acceptance remains pending.

## November 23, 2026 · v0.3 build 3

Added portable stage photos with opacity and locking, fixture-by-fixture cue edits with Simulation preview, soundtrack waveforms, timeline zoom, and manual beat and section markers with optional snapping. Cues can be moved in groups and duplicated at the playhead, with a single undo per action. Build 3 opens existing shows and setups and writes format 2. See [the design tools guide](DESIGN_TOOLS.md).

Xcode 27.0 beta 5 (27A5237l) passed all ten Release tests, including package and setup round trips, cue draft preview and apply, group moves, duplication, undo, and snapping. The ad-hoc signed universal app and ZIP passed strict signature verification and file comparisons. Visual acceptance remains pending.

## November 23, 2026 · v0.2 build 2

Added an opt-in Wi-Fi phone remote with QR pairing, Mac approval, revocation, transport, GO, blackout, and simulated fixture status. Made the separate Light Show Studio GitHub repository public at the user’s request. Added daily and manual stable-release checks. The public feed requires no token and reported that no full release had been published. The Xcode 27A5237l Release run passed seven tests, including localhost pairing and control, and the universal ZIP passed strict signature and file comparison. Phone browser and visual acceptance remain pending. See [phone and update instructions](PHONE_AND_UPDATES.md).

## November 23, 2026 · v0.1 build 1

Implemented the standalone Home, Program, and Show Mode workspaces. The first build adds controller and fixture patching, fixture groups and a stage schematic, portable show files with their soundtrack, reusable setup files, saved looks, cue recording and review, chases, moving-head paths, and an armed Simulation workspace. The app has its own bundle ID, project format, settings and icon.

Xcode 27.0 beta 5 (27A5237l) passed four Release tests covering setup reuse, patch and cue conflict handling, movement and chases, and recording against the real AVPlayer clock. The recording test used muted audio. It saved and reopened the show after removing its original song, then checked both simulated cue transitions. The ad-hoc signed universal app and ZIP passed strict signature and file comparisons. Visual and listening acceptance and physical output remain pending.
