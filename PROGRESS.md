# Progress

## Milestone 1 · Local recording

**Status:** Incomplete. No milestone has been closed.

**Active feature:** Optional system audio ("Record Mac sound" switch). The capture-blocked and recovery check passed.

**Done on 16 November 2026 (merged to main):**

| Feature | Result |
| --- | --- |
| Recording format matches the brief: H.264 video in MP4, SDR, at most 30 fps, AAC audio | Passed. Builds on the target Mac; short narrated clip checked with ffprobe (H.264/AAC, smooth scroll, no drift) and the owner confirmed the voice was good. |
| Voice cleanup (see Audio feature below) | Passed. Mac file tests passed, and the owner compared a new clip in a normal room and confirmed it sounds better. |
| Microphone selection (Input menu, remembered choice, unplug fallback) | Passed 16 Nov 2026. The owner tested it on the Mac and reported "Everything worked good." |
| Start/stop shortcut (⌥⇧⌘R from any app) | Passed 16 Nov 2026. The owner ran the Mac test steps and reported "Everything looks good." |
| Input level meter | Passed 16 Nov 2026. The owner ran all five Mac test steps and reported "All steps work great." |
| Real website and dense Figma file, 1-minute recording | Passed 16 Nov 2026. The owner confirmed the Figma recording looked good and reported the website recording as part of the same test. |

**Evidence as of 12 November 2026:** The target is a MacBook Air with Apple M5, 16 GB memory, macOS 27.2.1, and Xcode 27.2. It meets the project's macOS 15 deployment target. Window or display selection, optional default-mic narration, start and stop controls, and local MP4 saving already exist. The owner confirmed that short recording and narration worked on the earlier build. A later synthetic HEVC test verified video-only recording and decode. Neither result closes the checks for the new baseline.

| Acceptance check | Status |
| --- | --- |
| Save and replay one short narrated sample using the agreed format | Passed 16 Nov 2026 (H.264/AAC, owner checked text, scrolling, and speech). |
| Try a real website and a dense Figma file | Passed at 1-minute length on 16 Nov 2026 (owner decision). A long run is in the final checks below. |
| Capture blocked and recovery (changed by owner, 16 Nov; see Decisions) | (2) Microphone access off, note shown, back on and recording works: passed 16 Nov 2026 (owner). (1) Cancel the picker, app returns to Ready, next Record works: passed 16 Nov 2026 using Esc (owner). The Cancel button can't be clicked because the macOS picker covers the app window, so the status text now says "Esc cancels". |

**Final checks before wrap-up.** Every item here must pass before Milestone 1 closes. They are saved for the end because they are long or heavy, not because they are optional.

| Final check | Status |
| --- | --- |
| Record and replay a 45-minute sample using the usual mic or headset | Pending (deferred by owner, 16 Nov). Check for readable text, intelligible speech, and no drift near the start and end. Voice cleanup must finish on the long file. |
| Long real-work session: a website and a dense Figma file over a long recording, with scrolling and zooming | Pending. Check that text stays readable and the app stays responsive. |
| Heavy load: record while the Mac is busy (many browser tabs, Figma, a video call or other heavy app) | Pending. Check for dropped frames, stutter, and audio drift. |
| Microphone selection over a long recording with the chosen headset or external mic | Pending, after the mic selection feature passes its short tests. |

**Audio feature (added 16 November 2026):** Clean up the narration without taking anything away. The owner asked for less background noise and room echo, plus small safe quality gains. ScreenCaptureKit has no noise or echo setting for its microphone capture, so the app now cleans the saved file right after recording (`VoiceCleanup.swift`): Apple's voice isolation (high-quality voice model), an 80 Hz rumble filter, a 2 dB level boost (about 25% louder) with a peak limiter 1 dB below full scale, and AAC at 96 kbps per channel instead of about 53. The video is copied untouched, the cleaned audio goes back at the original start time with the isolation delay removed, and the original file is kept if any step fails. The narration is decoded on the video's timeline from time zero, so ScreenCaptureKit's lead-in offset (about 0.38 s) becomes silence and sync holds. A "Clean up voice" switch (on by default) lets the owner compare. Video stays H.264 at 30 fps.

| Audio feature step | Status |
| --- | --- |
| Code (`VoiceCleanup.swift`, PR #2) | Merged to main. |
| App builds on the target Mac; cleanup tested on a copy of the 16 Nov clip (sync, loudness, peaks) | Done 16 Nov on the Mac. Builds. 47 s clip cleaned in 2.4 s; video stream byte-identical; voice in sync within 1 ms at start and end; loudness −32.2 → −30.5 LUFS, true peak −13.5 → −10.9 dBFS; AAC about 140 kbps. A 9.4-minute file took 26 s with no drift. |
| Owner compares a new short clip in a normal room with cleanup on and off | Passed 16 Nov 2026: owner confirmed it sounds better. |

**Other local release features:** Microphone device selection passed (see below). The input meter and start/stop shortcut passed. Optional system audio is next, after the screen-permission check. Test optional system audio separately before including it. Finish the active feature and its checks before starting another.

**Microphone selection (passed 16 November 2026):** A new "Input" menu under the Microphone switch lists every connected mic, plus "Mac default", which follows System Settings → Sound → Input and is used until the owner picks something else. The pick is remembered between launches by the mic's device ID (`MicrophoneList.swift`) and passed to ScreenCaptureKit as the capture device. If the remembered mic is unplugged, the menu shows it as "(not connected)", the recording uses the Mac default, and a note says so; plugging it back in makes it the input again. If the mic in use is unplugged mid-recording, the screen keeps recording, a warning appears straight away, and the saved-file message says the voice may stop early. Voice cleanup and its sync handling are unchanged, since they work on the saved file whichever mic made it.

| Mic selection step | Status |
| --- | --- |
| Code on a branch with a PR (not merged) | Done 17 Nov. |
| Builds on the target Mac with no warnings; app launches | Done 17 Nov. |
| Mic list, remembered choice, relaunch, and unplugged fallback logic (tested against the Mac's real inputs: MacBook Air mic, Camo, iPhone mic) | Passed 17 Nov. Found and fixed a bug where the saved choice was cleared at every launch. |
| Owner tests on the Mac: headset chosen and used, choice remembered after relaunch, unplug fallback and warnings | Passed 16 Nov 2026 (owner: "The picker is working", "Everything worked good"). |

**Input level meter (passed 16 November 2026):** A "Level" bar under the Input menu moves as the owner speaks while the microphone switch is on, before and during recording (`InputMeter.swift`). It listens to the same mic the recording uses (the remembered pick, or the Mac default) through a separate AVFoundation listener, so the capture path and voice cleanup are unchanged. Green is normal speech, amber is loud (above about −12 dB), red is near distortion (above about −3 dB), and a thin marker holds the latest peak for a second. It never asks for mic access itself; until access is granted it says the meter shows after access is allowed. macOS shows its orange mic dot while the meter is listening.

| Level meter step | Status |
| --- | --- |
| Code on a branch with a PR (not merged) | Done. |
| Builds on the target Mac with no warnings | Done 16 Nov. |
| Meter stays off and shows the access note when mic access isn't granted | Passed 16 Nov (checked with the test tools, which have no mic access). |
| Owner checks the bar moves with their voice, follows a different chosen mic, keeps moving while recording, and the recording and cleanup still sound right | Passed 16 Nov 2026 (owner: "All steps work great"). |

**Start/stop shortcut (passed 16 November 2026):** ⌥⇧⌘R does the same as the main button from any app, even while Figma or a browser is in front: it opens the picker when ready, cancels the picker, or stops a recording (`GlobalShortcut.swift`). It uses the macOS hot key API, so no Accessibility permission is needed. ⌘⇧R was avoided because browsers use it for hard reload. The window shows the shortcut under "Saved in Movies", or says it's used by another app if registration fails, and a Recording menu lists it.

| Shortcut step | Status |
| --- | --- |
| Code on a branch with a PR (not merged) | Done. |
| Builds on the target Mac with no warnings | Done 16 Nov. |
| Shortcut registers on the Mac, and a clash with another app is detected | Passed 16 Nov (test tools). |
| Owner starts and stops a recording with ⌥⇧⌘R while another app is in front, and cancels the picker with it | Passed 16 Nov 2026 (owner: "Everything looks good"). |

**Optional system audio (started 17 November 2026):** A "Record Mac sound" switch records what the Mac is playing (a video, a prototype's sound) alongside the voice. ScreenCaptureKit captures it (this app's own sounds are excluded, 48 kHz stereo) and saves it as a second audio track, so the cleanup step now mixes the two into one stereo AAC track, because players and the future viewing page normally play only one track. Only the voice goes through voice isolation, the rumble filter and boost; the Mac sound is never cleaned, since isolation would treat music or video sound as noise. The Mac sound sits 4 dB below the voice, the mix is limited to 1 dB under full scale, and the Mac sound is delayed by the same amount as the voice chain so the two stay in sync. The microphone track is found by name, then by being the only mono track, then by order. If the file comes back with only one audio track while both sources were on, cleanup is skipped with a note so the Mac sound isn't damaged, and the original is kept if any step fails. Video stays H.264 at 30 fps, and recordings with the switch off are unchanged. Headphones are advised, since speakers would be heard by the mic as well as captured directly.

| System audio step | Status |
| --- | --- |
| Code on a branch with a PR (not merged) | Done 17 Nov. |
| Builds on the target Mac with no warnings | Done 17 Nov. |
| Mixing tested on synthetic two-track files on the Mac (spoken voice plus a tone at 3.000 s) | Passed 17 Nov: one stereo AAC track, same length as the video; tone lands within 2 ms, the same with cleanup on or off; Mac sound 4 dB under its original level, voice 6 dB above it; peaks below −1 dBFS; works with the tracks in either order; voice-only recordings unchanged; a failed mix leaves the original file untouched. |
| Owner records with the switch on while sound plays and they talk; checks both are heard, clear and in sync, with no echo on headphones | Pending (needs the owner; the tools can't capture the screen). |
| Check the real file's tracks: that ScreenCaptureKit really saves two tracks, and the Mac sound comes through untouched | Pending, after the owner's test (the file is inspected with ffprobe and a test tone). |

**Decisions:** On 16 November 2026 the owner added voice cleanup (noise and echo reduction, a small level boost, a higher speech bit rate) as the current Milestone 1 audio feature; in-app gain control stays on the later list. The owner deferred the 45-minute test until the rest of the scope is finished, and it must still pass before Milestone 1 closes. On 16 November 2026 the owner accepted the 1-minute website and Figma test as passed; the 45-minute test and other long or heavy-load tests now live in "Final checks before wrap-up". The supplied brief replaces the earlier roadmap. Keep the existing native capture code as the starting point and change the HEVC-first setting to the brief's H.264 baseline (done and verified on the Mac on 16 November 2026). Trim, webcam, auto-zoom, and other deferred features stay on the later list. Hosted sharing begins with Milestone 2 after the owner confirms the local checks are complete. On 16 November 2026 the owner changed the "deny screen capture and recover" check. The app uses Apple's content picker, which grants access one recording at a time, so it never appears under Screen & System Audio Recording and that permission can't be denied (the owner confirmed it isn't listed and recording still works). The replacement check covers the two blocks that can happen: canceling the picker, and turning Microphone access off and back on.
