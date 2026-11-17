# Milestone 4: pilot checklist

The goal is to use the app on one real client project and note what worked. The brief's checks are: speed, audio and text quality, whether the client could open the link without help, the remaining limits, and a short guide (see [GUIDE.md](GUIDE.md)).

Real client footage is shared only with the owner's OK, and the owner chooses the project.

## Before the pilot (10 minutes)

- [ ] Update the Mac copy to the latest version and press Run in Xcode (see GUIDE.md).
- [ ] Owner key saved in a password manager.
- [ ] Choose your usual mic or headset in **Input**; the Level bar moves when you talk.
- [ ] Decide whether you need Mac sound. If it's on, voice cleanup is off for that recording, and headphones are best.
- [ ] Close apps you don't need, and switch on Do Not Disturb so notifications aren't recorded.

## During the pilot

- [ ] Record a real walkthrough (a website or Figma file for the client) at your normal length.
- [ ] Watch it back before sharing: text readable at full screen, voice clear, voice in time with the screen at the start and the end.
- [ ] Upload it and note roughly how long the upload took.
- [ ] Open the link yourself on your phone before sending it.
- [ ] Send the link to the client the way you normally would.

## After the pilot: write down

| Question | Answer |
| --- | --- |
| Project and video length | |
| Time from pressing Stop to having a link | |
| Was the text readable for the client (especially small Figma text)? | |
| Was the voice clear, and did it stay in time? | |
| Did the client open and play it without help? Which device or browser? | |
| Did anything get in your way, or feel slow? | |
| Anything you'd want before using it for every project? | |

Send these answers to Claude in the thread, and they'll go into PROGRESS.md.

## Limits known before the pilot

- The app runs from Xcode on this Mac. It isn't installed as a normal app yet (signing and notarizing are only needed if you want that).
- Videos are sent at full quality with no lower-quality versions, so very slow connections may buffer on long videos.
- With Mac sound on, the voice isn't cleaned up (macOS mixes both into one track).
- The viewing page is plain (title, player, speed, fullscreen, optional Figma or site link). Branding is on the later list.
- Share links use the `workers.dev` address, not your own domain (later list).
- Anyone with a forwarded link can watch while it's switched on. Named-recipient access for confidential work would need email checks first.
- The long and heavy checks (45-minute recording, busy Mac, long upload on mobile data, Wi-Fi off mid-upload) are still open in PROGRESS.md under "Final checks".
- Delete currently keeps a record of the video's title and dates (the video file and links are removed). Whether to erase that record too is an open owner decision.
