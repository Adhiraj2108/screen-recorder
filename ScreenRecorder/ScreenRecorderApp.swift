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
    }
}
