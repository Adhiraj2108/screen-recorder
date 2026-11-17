# Solo Mac screen recorder

> This is the original brief, kept as written. Changes the owner has decided since (for example R2 storage instead of Stream, automatic upload, and moving uploaded recordings to the Trash after 5 days) are recorded under Decisions in [PROGRESS.md](PROGRESS.md).
## Product brief and build guide

### Goal
I run a design agency and want my own lightweight Loom-style app for narrating website, brand, and Figma walkthroughs. I am a non-developer and the only person who will record. The app runs on my Mac. Clients watch from a browser link on their own devices without installing anything. Shared videos should play when my Mac is asleep or offline.

### How to work with me
Treat this brief as the scope. Start by inspecting the existing project, checking my Mac model and macOS version, and identifying the smallest milestone I can test. Summarize the proposed next step, why it matters, and how I can verify it in plain English. Work through one milestone at a time and report what actually passed, what I need to test on my Mac, and any remaining issue. Use synthetic footage during testing. Ask for decisions only when they materially affect scope, spending, or client access. Explain system permission prompts when they appear. Keep secrets out of chat, source code, and the desktop bundle. Confirm with me before purchasing services or publishing real client footage. Keep a short record of decisions and deviations from this brief.

### Stay on track and finish each stage

- Keep one active milestone and one feature in progress within it. Break each feature into small, testable steps. Finish and verify it against the agreed checks before starting another feature. If a check fails or needs me to test something on my Mac, mark it pending and help me close it before advancing.
- Close each milestone only when every agreed acceptance check passes and I have completed any hands-on checks. Share the evidence and confirm with me that the stage is complete before starting the next one. If we intentionally change a check or reorder work, record my decision and the reason first.
- At the start and end of each work session, after each completed feature, and whenever a blocker changes the plan, give me a short update. Include the active milestone, what passed, what is pending or blocked, and the single next action. At each milestone handoff, recap completed milestones and show what comes next. Keep this progress record available so a new session can pick up where we left off.
- If I bring up an idea outside the active milestone, flag the drift and ask me to return to the current step. Say what remains unfinished, put the new idea in a later list, and suggest the next concrete action. Only switch priorities if I explicitly decide to revise the plan. For example, “Webcam overlays can go on the later list. We still need to verify audio on a 45-minute recording. Can we run that check first?”

### First release
- Pick a display or window, choose a microphone, see an input meter, and start or stop with obvious controls and a keyboard shortcut. Include optional system audio if the audio tests pass.
- Save a playable local file first. Show clear upload and processing states, preserve the source file on failure, and offer retry. Make uploading an explicit action so I can review the capture before sharing.
- Once ready, copy a revocable link to a simple branded viewing page with fullscreen, playback speed, and an optional link to the Figma file or staging site. The page presents the walkthrough. Access to the underlying Figma file or site remains governed by its own permissions.
- Give me a simple owner-only list to find, rename, share, revoke, and delete uploaded videos. One owner identity is sufficient. Use opaque share links and short-lived signed video playback. Anyone with a forwarded standard link can watch while it is active. If I need named-recipient access for confidential work, agree on email verification before sharing that material.
- Defer team seats, roles, invitations, project portals, webcam bubble, trim, captions, comments, AI, auto-zoom, and Google Meet. If I request a change, explain what it adds to the current milestone.

### Proposed stack and decisions to validate
- **Recorder:** Swift, SwiftUI, Xcode, and Apple's ScreenCaptureKit. Confirm the deployment target against my actual Mac. Start with Apple's recording output on supported macOS and use AVFoundation if testing shows a need for more control. Start with SDR, 30 fps, H.264 and AAC in MP4. Validate text legibility, motion, audio sync, and system-audio behavior with my actual setup.
- **Web and video:** Use a small TypeScript Cloudflare Worker for the branded viewing page and API, D1 for video and share metadata, and Cloudflare Stream for upload, processing, and playback. Authenticate the owner before creating upload sessions or managing recordings. Use short-lived, one-time direct upload sessions and resumable tus uploads, with provider credentials held server-side. Keep the provider asset private and mint playback tokens only after checking the share. Use a short token lifetime and document that already-issued tokens can remain usable until expiry.
- **Resolution:** Stream tops out at 1080p. Test a focused-window recording on a dense Figma file and a website, and compare the hosted view with the local master. Consider Mux for 1440p or 4K only if the client cannot read the details at 1080p. Keep the original locally if it matters. Cloudflare runs the viewer and video delivery independently of the Mac. A rented VPS or Mac-hosted web service is unnecessary for this proposed stack.
- **Installation:** Run on my own Mac from Xcode during development. Evaluate signing and notarization only if needed for the final installation workflow. Preserve the agency's ownership of the repo, domain, and cloud accounts.

### Milestones and acceptance checks
| Milestone | Evidence before advancing |
|---|---|
| 1. Local recording | Save and replay one short sample and one 45-minute sample on my Mac. Try an actual website and dense Figma file, my usual microphone or headset, and screen capture permission denial and recovery. Confirm the file contains intelligible speech, readable text and no obvious audio drift. |
| 2. One hosted video | Upload a synthetic clip through the owner-only flow. Open the link in Safari, Chrome and on a phone over mobile data with the Mac offline. Check playback, text legibility and time from upload to ready. Confirm direct playback without a signed token is denied. |
| 3. Dependable solo workflow | Disconnect Wi-Fi mid-upload and confirm the upload resumes or recovers without losing the local file or creating duplicate videos. Relaunch the app and verify recovery. Revoke a link and confirm a fresh browser cannot play it. Verify the old token expiry and what delete removes from the host and Mac. |
| 4. Pilot | Use the app on a real project once the earlier checks pass. Review speed, audio and text quality, and whether the client could view the link without help. Record remaining limits and a short guide for launching, updating, and recovering the app. |

### Time and cost assumptions
For planning, allow 1–2 weeks for a local prototype and roughly 3–6 weeks total for a solo pilot with an experienced implementer. These are rough estimates. Re-estimate after the local capture test. For a paid build, ask for separate fixed-scope quotes for local capture, hosted sharing, and reliability. The earlier team build estimate does not apply.

Cloudflare Stream lists $5 per 1,000 minutes of storage capacity and $1 per 1,000 delivered minutes. As an example, eight 10-minute videos per month with six months kept gives 480 stored minutes. If each new video is watched in full three times, that is 240 delivered minutes per month before older-video views. Budget about $5–$6/month for video at that usage, plus any web service charges, domain costs, taxes and maintenance. Verify pricing before enabling billing.

### Later phase
For Google Meet, first decide whether the desired outcome is recording the window and audio of a call I attend, or importing Google's official recording from Drive. The latter depends on Workspace eligibility and host permissions. Validate participant notice and consent before deploying call capture. Treat automatic recording of arbitrary client-hosted calls and separate participant tracks as separate feasibility work.

### Official references
- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) and [Apple's microphone and direct recording walkthrough](https://developer.apple.com/videos/play/wwdc2024/10088/)
- [Cloudflare Stream overview](https://developers.cloudflare.com/stream/), [resumable uploads](https://developers.cloudflare.com/stream/uploading-videos/resumable-uploads/), and [pricing](https://developers.cloudflare.com/stream/pricing/)
- [Mux 4K playback](https://www.mux.com/docs/guides/stream-videos-in-4k)
- [Google Meet recording eligibility](https://support.google.com/meet/answer/9308681) and [Meet recording artifacts](https://developers.google.com/workspace/meet/api/guides/artifacts)
