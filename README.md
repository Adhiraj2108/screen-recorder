# Screen Recorder

A native macOS app for recording narrated walkthroughs. The current build saves recordings locally. The [product brief](BRIEF.md) defines the release scope and the [progress record](PROGRESS.md) tracks the current milestone and its checks. The [owner guide](GUIDE.md) covers launching, updating and recovering the app, and the [pilot checklist](PILOT.md) covers the first real project.

## First milestone: reliable capture

Open `ScreenRecorder.xcodeproj`, select the **ScreenRecorder** scheme and **My Mac**, then press **Run**. In the app, choose whether to use the microphone, click **Record**, and select a window or display in the macOS picker. Stop the recording and use **Open recording** to review it or **Show in Finder** to find it in `~/Movies/Screen Recorder`.

The existing build keeps the source resolution up to a 4K limit and captures up to 30 frames per second. It writes H.264 MP4 in standard dynamic range (SDR), with an AAC audio track when the microphone is on, as the brief specifies.

## Development setup

Install the full version of [Xcode](https://developer.apple.com/xcode/resources/) and open it once to finish setup. The app targets macOS 15 or later and uses SwiftUI, ScreenCaptureKit, and AVFoundation.
