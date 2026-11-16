# Progress

## Milestone 1 · Local recording

**Status:** Incomplete. No milestone has been closed.

**Active feature:** Align the local recording format with the [product brief](BRIEF.md). Code changed on 16 November 2026: recordings now use ScreenCaptureKit's direct recording output with H.264 video in an MP4 file, SDR, and a 30 fps ceiling. With the mic on, the audio track is expected to be AAC. Source-based sizing (up to 4K) is unchanged so we can judge readable text on the actual setup.

| Feature step | Status |
| --- | --- |
| Code switched from HEVC-first to H.264, SDR set explicitly | Done in code. Not built or run yet, because macOS builds can't run in the cloud workspace. |
| App builds in Xcode on the target Mac | Pending on the Mac. |
| Short narrated clip: QuickTime Inspector shows H.264 video and AAC audio, about 30 fps | Pending on the Mac. |
| Owner checks text, scrolling, and speech in QuickTime | Pending on the Mac. |

**Evidence as of 12 November 2026:** The target is a MacBook Air with Apple M5, 16 GB memory, macOS 27.2.1, and Xcode 27.2. It meets the project's macOS 15 deployment target. Window or display selection, optional default-mic narration, start and stop controls, and local MP4 saving already exist. The owner confirmed that short recording and narration worked on the earlier build. A later synthetic HEVC test verified video-only recording and decode. Neither result closes the checks for the new baseline.

| Acceptance check | Status |
| --- | --- |
| Save and replay one short narrated sample using the agreed format | Pending. Check codec and duration, then have the owner check text, scrolling, and speech in QuickTime. |
| Record and replay a 45-minute sample using the usual mic or headset | Pending. Check for readable text, intelligible speech, and obvious drift near the start and end. |
| Try a real website and a dense Figma file | Pending. Use non-client material and a focused window so the test represents normal use. |
| Deny screen capture and recover | Pending. Confirm there is useful feedback, then allow capture and try again. Canceling source selection does not establish this check. |

**Audio feature (added 16 November 2026):** Clean up the narration without taking anything away. The owner asked for less background noise and room echo, plus small safe quality gains. ScreenCaptureKit has no noise or echo setting for its microphone capture, so the app now cleans the saved file right after recording (`VoiceCleanup.swift`): Apple's voice isolation (high-quality voice model), an 80 Hz rumble filter, a 2 dB level boost (about 25% louder) with a peak limiter 1 dB below full scale, and AAC at 96 kbps per channel instead of about 53. The video is copied untouched, the cleaned audio goes back at the original start time with the isolation delay removed, and the original file is kept if any step fails. A "Clean up voice" switch (on by default) lets the owner compare. Video stays H.264 at 30 fps.

| Audio feature step | Status |
| --- | --- |
| Code on branch `voice-cleanup` (built on `h264-mp4-baseline`) | Done in code. |
| App builds on the target Mac; cleanup tested on a copy of the 16 Nov clip (sync, loudness, peaks) | Pending. |
| Owner compares a new short clip in a normal room with cleanup on and off | Pending on the Mac. |

**Other local release features:** Microphone device selection, input meter, and a start/stop shortcut are pending. Test optional system audio separately before including it. Finish the active feature and its checks before starting another.

**Decisions:** On 16 November 2026 the owner added voice cleanup (noise and echo reduction, a small level boost, a higher speech bit rate) as the current Milestone 1 audio feature; in-app gain control stays on the later list. The owner deferred the 45-minute test until the rest of the scope is finished, and it must still pass before Milestone 1 closes. The supplied brief replaces the earlier roadmap. Keep the existing native capture code as the starting point and change the HEVC-first setting to the brief's H.264 baseline (done in code on 16 November 2026, pending Mac verification). Trim, webcam, auto-zoom, and other deferred features stay on the later list. Hosted sharing begins with Milestone 2 after the owner confirms the local checks are complete.
