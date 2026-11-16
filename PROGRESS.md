# Progress

## Milestone 1 · Local recording

**Status:** Incomplete. No milestone has been closed.

**Active feature:** Try a real website and a dense Figma file (non-client material, focused window), checking text readability, scrolling, and narration.

**Done on 16 November 2026 (merged to main):**

| Feature | Result |
| --- | --- |
| Recording format matches the brief: H.264 video in MP4, SDR, at most 30 fps, AAC audio | Passed. Builds on the target Mac; short narrated clip checked with ffprobe (H.264/AAC, smooth scroll, no drift) and the owner confirmed the voice was good. |
| Voice cleanup (see Audio feature below) | Passed. Mac file tests passed, and the owner compared a new clip in a normal room and confirmed it sounds better. |

**Evidence as of 12 November 2026:** The target is a MacBook Air with Apple M5, 16 GB memory, macOS 27.2.1, and Xcode 27.2. It meets the project's macOS 15 deployment target. Window or display selection, optional default-mic narration, start and stop controls, and local MP4 saving already exist. The owner confirmed that short recording and narration worked on the earlier build. A later synthetic HEVC test verified video-only recording and decode. Neither result closes the checks for the new baseline.

| Acceptance check | Status |
| --- | --- |
| Save and replay one short narrated sample using the agreed format | Passed 16 Nov 2026 (H.264/AAC, owner checked text, scrolling, and speech). |
| Record and replay a 45-minute sample using the usual mic or headset | Deferred by owner decision (16 Nov) until the rest of the scope is finished; must pass before Milestone 1 closes. Check for readable text, intelligible speech, and obvious drift near the start and end. |
| Try a real website and a dense Figma file | Active. Use non-client material and a focused window so the test represents normal use. |
| Deny screen capture and recover | Pending. Confirm there is useful feedback, then allow capture and try again. Canceling source selection does not establish this check. |

**Audio feature (added 16 November 2026):** Clean up the narration without taking anything away. The owner asked for less background noise and room echo, plus small safe quality gains. ScreenCaptureKit has no noise or echo setting for its microphone capture, so the app now cleans the saved file right after recording (`VoiceCleanup.swift`): Apple's voice isolation (high-quality voice model), an 80 Hz rumble filter, a 2 dB level boost (about 25% louder) with a peak limiter 1 dB below full scale, and AAC at 96 kbps per channel instead of about 53. The video is copied untouched, the cleaned audio goes back at the original start time with the isolation delay removed, and the original file is kept if any step fails. The narration is decoded on the video's timeline from time zero, so ScreenCaptureKit's lead-in offset (about 0.38 s) becomes silence and sync holds. A "Clean up voice" switch (on by default) lets the owner compare. Video stays H.264 at 30 fps.

| Audio feature step | Status |
| --- | --- |
| Code (`VoiceCleanup.swift`, PR #2) | Merged to main. |
| App builds on the target Mac; cleanup tested on a copy of the 16 Nov clip (sync, loudness, peaks) | Done 16 Nov on the Mac. Builds. 47 s clip cleaned in 2.4 s; video stream byte-identical; voice in sync within 1 ms at start and end; loudness −32.2 → −30.5 LUFS, true peak −13.5 → −10.9 dBFS; AAC about 140 kbps. A 9.4-minute file took 26 s with no drift. |
| Owner compares a new short clip in a normal room with cleanup on and off | Passed 16 Nov 2026: owner confirmed it sounds better. |

**Other local release features:** Microphone device selection, input meter, and a start/stop shortcut are pending. Test optional system audio separately before including it. Finish the active feature and its checks before starting another.

**Decisions:** On 16 November 2026 the owner added voice cleanup (noise and echo reduction, a small level boost, a higher speech bit rate) as the current Milestone 1 audio feature; in-app gain control stays on the later list. The owner deferred the 45-minute test until the rest of the scope is finished, and it must still pass before Milestone 1 closes. The supplied brief replaces the earlier roadmap. Keep the existing native capture code as the starting point and change the HEVC-first setting to the brief's H.264 baseline (done and verified on the Mac on 16 November 2026). Trim, webcam, auto-zoom, and other deferred features stay on the later list. Hosted sharing begins with Milestone 2 after the owner confirms the local checks are complete.
