# Screen Recorder: launch, update and recover

A short guide for the owner. It covers the Mac app and the hosting page that clients see. Nothing here needs coding.

## What lives where

| Thing | Where it is |
| --- | --- |
| The app's code | This folder on the Mac (`Desktop/screen-recording-clone`) and on GitHub (`Adhiraj2108/screen-recorder`) |
| Your recordings | `Movies/Screen Recorder` on the Mac. The app never deletes or changes them. |
| Uploaded videos and share links | Cloudflare (free R2 storage), behind https://recorder-web.rae-social-agency.workers.dev |
| Your owner list (find, rename, share, revoke, delete) | https://recorder-web.rae-social-agency.workers.dev/admin |
| Your owner key | The Mac's Keychain (for the app), `web/.prod.vars` on the Mac, and Cloudflare's secret store. It is never in the code or on GitHub. |

Keep a copy of the owner key in your password manager. If the Mac is lost, that copy plus GitHub is all you need to carry on (see "If the Mac is lost").

## Launch the app

1. Open **Xcode**, then open `ScreenRecorder.xcodeproj` from the project folder.
2. At the top, check the scheme says **ScreenRecorder** and **My Mac**.
3. Press **Run** (the ▶ button, or ⌘R). The app window opens.
4. Keep Xcode open while you use the app. Quitting Xcode also quits the app.

Recording:

1. Pick your microphone in **Input** and watch the **Level** bar move as you talk.
2. Press **Record**, or **⌥⇧⌘R** from any app, then choose a window or display in the macOS picker. **Esc** cancels the picker.
3. Press **Stop** (or **⌥⇧⌘R** again). The file is saved in `Movies/Screen Recorder`, and voice cleanup runs for a few seconds.
4. Watch it with **Open recording** before sharing.

Sharing:

1. In the **Share** area, give the video a title and press **Upload and get link**.
2. When it finishes, the link is copied. Paste it to the client.
3. To stop a client watching, open the owner list and switch the link off. It stops at once.

## Update the app

When Claude (or anyone) has merged a change on GitHub:

1. Quit the app.
2. Ask Claude to "update my Mac copy to the latest main", or in Terminal run, from the project folder:

   ```bash
   git checkout main && git pull
   ```

3. Open Xcode and press **Run** again. The new version opens. Your recordings, microphone choice, owner key and any unfinished upload are kept.

Updates to the hosting page are published to Cloudflare by Claude, and only with your written OK in the thread. You don't need to do anything for those; links that are already shared keep working.

## Recover from common problems

| What you see | What to do |
| --- | --- |
| The app won't build or open in Xcode | Quit Xcode, open it again and press Run. If it still fails, copy the red error text to Claude. Your recordings are safe either way. |
| The picker never appears, or recording won't start | Quit and reopen the app. If macOS shows a permission prompt, allow it. |
| No sound in a recording | Check the Microphone switch is on and the Level bar moves. If it says access is off: **System Settings → Privacy & Security → Microphone**, turn Screen Recorder on, then reopen the app. |
| The mic you chose shows "(not connected)" | Plug it back in, or choose another one in **Input**. Until then the Mac's default mic is used. |
| The shortcut says it's used by another app | Use the Record button instead, and tell Claude which app clashes. |
| An upload stopped with a message | Check the internet, then press **Resume upload**. It carries on from where it stopped and never makes a second copy. |
| An upload is stuck or you changed your mind | Press **Pause**, then **Discard**. Only the part-uploaded copy online is removed; your recording stays in Movies. |
| The app asks for the owner key again | Paste it from your password manager. If you've lost it, see "Lost or leaked owner key". |
| A client says the link doesn't open | Open it yourself in a private browser window. "This link isn't available" means the link is switched off or the video was deleted: make a new link in the owner list. If it plays for you, ask the client to try another browser or Wi-Fi. |
| A long video buffers on a slow connection | Expected on very slow connections (the page always sends the full-quality file). Ask the client to pause for a minute and then play, or send a shorter clip. |
| The owner list or share page shows an error for everyone | Tell Claude. Claude can check the live service and, with your OK, roll it back to the last working version (`npx wrangler rollback` in `web/`). |

## Lost or leaked owner key

The owner key opens the owner list and allows uploads. If someone else may have it, or it's lost:

1. Ask Claude to set a new key. This changes your Cloudflare account, so Claude will ask for your written OK first.
2. Save the new key in your password manager.
3. In the app, press **Disconnect** in the Share area, then **Connect** with the new key.

Share links already sent keep working; only the owner side changes.

## If the Mac is lost or replaced

- Uploaded videos and share links keep working; they don't depend on the Mac.
- Recordings that were only on the Mac are lost unless they were backed up (Time Machine or iCloud Drive). Consider backing up `Movies/Screen Recorder`.
- On the new Mac: install Xcode, get the code from GitHub, press Run, and connect with the owner key from your password manager. Claude can do the setup steps for you.

## Space and cost

The free Cloudflare storage holds 10 GB, which is about 70 to 150 ten-minute videos. Deleting a video in the owner list frees its space. Going over 10 GB costs about $0.015 per GB a month; nothing paid is switched on without your OK.
