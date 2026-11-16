# Progress

## Milestone 1 · Local recording

**Status:** Incomplete. No milestone has been closed.

**Next feature:** Align the local recording format with the [product brief](BRIEF.md), then verify one short synthetic narrated clip on the target Mac. Use ScreenCaptureKit's direct recording output with SDR, a 30 fps ceiling, and H.264 MP4. Confirm the output has an AAC audio track when the mic is enabled. Keep the current source-based sizing for this test so we can judge readable text on the actual setup.

**Evidence as of 12 November 2026:** The target is a MacBook Air with Apple M5, 16 GB memory, macOS 27.2.1, and Xcode 27.2. It meets the project's macOS 15 deployment target. Window or display selection, optional default-mic narration, start and stop controls, and local MP4 saving already exist. The owner confirmed that short recording and narration worked on the earlier build. A later synthetic HEVC test verified video-only recording and decode. Neither result closes the checks for the new baseline.

| Acceptance check | Status |
| --- | --- |
| Save and replay one short narrated sample using the agreed format | Pending. Check codec and duration, then have the owner check text, scrolling, and speech in QuickTime. |
| Record and replay a 45-minute sample using the usual mic or headset | Pending. Check for readable text, intelligible speech, and obvious drift near the start and end. |
| Try a real website and a dense Figma file | Pending. Use non-client material and a focused window so the test represents normal use. |
| Deny screen capture and recover | Pending. Confirm there is useful feedback, then allow capture and try again. Canceling source selection does not establish this check. |

**Other local release features:** Microphone device selection, input meter, and a start/stop shortcut are pending. Test optional system audio separately before including it. Finish the active feature and its checks before starting another.

**Decisions:** The supplied brief replaces the earlier roadmap. Keep the existing native capture code as the starting point and change the HEVC-first setting to the brief's H.264 baseline. Trim, webcam, auto-zoom, and other deferred features stay on the later list. Hosted sharing begins with Milestone 2 after the owner confirms the local checks are complete.
