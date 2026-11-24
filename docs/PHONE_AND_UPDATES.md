# Phone remote and update notifications

## Pair a phone

1. Open a show. Connect the Mac and phone to the same trusted local network.
2. In the Mac toolbar, choose **Phone Remote**, select the network, and click **Start Phone Remote**.
3. Scan the QR code with the phone’s camera and open the link. Click **Approve Phone** on the Mac, then close the pairing panel.
4. Use **Play**, **Pause**, **Stop**, **GO**, and **Blackout** from the phone. Choose a cue before GO or continue the Mac’s cue list. Fixture states and the playhead are shown for reference.

The remote uses local HTTP on port 9444. A pairing code expires after two minutes and phone approval lasts up to eight hours. **Disconnect Phone** instantly revokes the paired phone. **Turn Off Remote** shuts down the listener. Switching shows or losing the selected network ends the connection. Show Mode must be armed on the Mac before a phone can start it.

## Check for a new version

Open **Light Show Studio → Check for Updates…** to check immediately. Automatic checks run at most once every 24 hours when the app launches or returns to the foreground. New full release notices appear when playback, recording, and Show Mode arming are inactive. **Download Update** opens the GitHub release. **Later** postpones the notice for that version.

For publishing, use a numeric full-release tag and attach a universal Mac ZIP named `LightShowStudio-…-macOS-universal.zip`. Preview releases are excluded by the stable release feed.
