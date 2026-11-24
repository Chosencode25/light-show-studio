# Show design tools

Add a portable stage background photo with opacity and lock controls. Keep fixture placement relative to the photo and include it in reusable setups. Add soundtrack waveforms, a zoomable timeline, manual beat and section markers, and optional snapping. Allow direct single and grouped cue movement with one undo per completed edit and duplication to the playhead.

Let each cue edit its fixture targets and their saved settings, with temporary audition before applying the edit. Preserve existing show packages and Simulation. Use SwiftUI and Xcode 27.0 beta 5 (27A5237l). Verify package reopening, waveform samples, cue batch edits, and collision rollback.

## Fixture timeline

Display fixture rows beneath the shared soundtrack and cue group tracks. Use equal-size visual command tiles with a programmed state band and a toolbar for compatible fixture drops. Use existing cues, motion keys, and chases with no format change. Split multi-fixture cues transactionally when a single tile is retimed and retain whole-cue editing in the shared row. Window layout presets and docking are a separate milestone.

## Clip duration

Palette drops use five-second clips, shortened at the end of a soundtrack as needed. Drag a clip body to move it and either edge to trim it. Evaluate clips over existing programming and restore the underlying output at the end. When clips overlap, the most recently started clip takes precedence. Preserve older point cues and validate format and playback compatibility.
