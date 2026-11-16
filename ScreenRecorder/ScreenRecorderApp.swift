import SwiftUI

@main
struct ScreenRecorderApp: App {
    @State private var recorder = ScreenRecorder()

    var body: some Scene {
        Window("Screen Recorder", id: "recorder") {
            RecorderView(recorder: recorder)
        }
        .defaultSize(width: 480, height: 360)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Recording") {
                // Shown for discoverability; while the app is running the system-wide shortcut handles the keys.
                Button(recorder.phase == .ready ? "Record" : "Stop or Cancel", action: recorder.primaryAction)
                    .keyboardShortcut("r", modifiers: [.command, .option, .shift])
            }
        }
    }
}
