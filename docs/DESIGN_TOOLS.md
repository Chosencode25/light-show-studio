# Edit a light show

- **Stage Photo** lets you choose a house or stage image. Adjust its opacity, drag the fixtures into position, then use **Lock Photo** to protect the image settings. The photo stays with saved shows and fixture setups. Fixture positions stay anchored to the image as the window resizes.
- **Timeline** shows the soundtrack waveform. Use the zoom slider and scroll horizontally to work in detail. Click the timeline to set the playhead. Add beat or named section markers from **Markers**. Turn on **Snap** to align cue drags with nearby markers.
- **Move and duplicate cues** by dragging their diamonds in **Cue Groups**. Shift-click or Command-click several cues and drag one to move the group. The **Cues** menu contains **Duplicate at Playhead**, **Delete Selected**, and **Clear Cue Selection**. Each successful batch action can be undone together. A conflict on a fixture leaves the cues in place.
- **Edit a cue** by selecting its diamond or choosing it from **Cues**. In the inspector, add or remove fixtures and change their saved power, color, dimmer, pan, tilt, or gobo settings. **Preview Cue** auditions the draft in Simulation. Click **Apply** to save it or **Release Preview** to return to the timeline.

- **Switched plug icons** can match the decoration a relay powers. Select the plug in the Fixture inspector, choose an **Icon**, and click **Apply Patch**. The icon is saved with the show or fixture setup. The plug still switches one relay on or off.
- **Draw a switched light strip** by choosing the **Light Strip** icon for a switched plug and clicking **Apply Patch**. Select the fixture on the stage or in the sidebar. Drag the two end points to set the length. Double-click a line segment to add a point, then drag it to make a bend. Control-click a point and choose **Remove Point**. The path saves with the show or fixture setup and appears in Show Mode.

Build 3 reads existing shows and setups. Files saved from this build use format 2 and require build 3 or later.

## Program fixture rows

Drag the divider above **Timeline** to give it more room. Each fixture has a row, and its name stays visible when you scroll horizontally. Drag a command tile from the palette above the waveform to the fixture row and time you want. The row highlights when it accepts the command. A switched plug accepts On, Off, and Chase. An RGB strip also accepts colors. Moving heads additionally accept dimmer, fade, and movement commands, using their fixture color wheel.

All command tiles are the same size. A thin color band shows the states set by cues, and a mint line shows where a chase runs. Drag a tile to change its time. Click a tile to edit the cue, movement key, or chase. Control-click it to remove that command. A multi-fixture chase stays together when moved. Fade Out reaches darkness at its tile, with a one-second lead by default. A new movement tile makes a small pan change. Click it to set a precise pan and tilt.

The **Cue Groups** diamonds move whole cues. Shift-click or Command-click diamonds to move several whole cues together. Drag a tile on a fixture row to move only that fixture's part of a cue. Shows saved before this build already have the cues needed for these rows. Manual-only cues remain in the **Cues** menu.
