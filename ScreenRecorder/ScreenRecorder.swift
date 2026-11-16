import AVFoundation
import AppKit
import Observation
import ScreenCaptureKit

@MainActor
@Observable
final class ScreenRecorder: NSObject {
    enum Phase: Equatable {
        case ready, requestingMicrophone, choosingSource, starting, recording(Date), saving, cleaningVoice
    }

    struct Recording {
        let url: URL
        let duration: TimeInterval
    }

    private struct Capture {
        let stream: SCStream
        let output: SCRecordingOutput
        let url: URL
        let includesMicrophone: Bool
        let cleansVoice: Bool
        /// The mic in use, so unplugging it mid-recording can be spotted.
        let microphoneID: String?
        let microphoneName: String?
        /// Shown again after saving, for example when the chosen mic was missing.
        let microphoneNotice: String?
    }

    // Hand the picker-owned filter to the main actor without reading or mutating it on the callback queue.
    private struct PickerSelection: @unchecked Sendable {
        let filter: SCContentFilter
    }

    private(set) var phase = Phase.ready
    private(set) var lastRecording: Recording?
    private(set) var message: String?
    var usesMicrophone = true
    /// Reduce background noise and room echo, and lift the voice slightly, after each recording.
    var cleansVoice = true
    /// The inputs the owner can pick from, and the remembered choice.
    let microphones = MicrophoneList()

    @ObservationIgnored private var capture: Capture?
    @ObservationIgnored private var captureTimeout: Task<Void, Never>?
    /// Set when the mic in use is unplugged during a recording.
    @ObservationIgnored private var lostMicrophone = false

    override init() {
        super.init()
        microphones.onDisconnect = { [weak self] id in self?.microphoneDisconnected(id) }
    }

    private func microphoneDisconnected(_ id: String) {
        guard let capture, capture.includesMicrophone, capture.microphoneID == id, !lostMicrophone else { return }
        switch phase {
        case .starting, .recording: break
        default: return
        }
        lostMicrophone = true
        message = "\(capture.microphoneName ?? "The microphone") was disconnected. The screen is still recording, but the voice may be missing from this point. Stop and record again if you need the narration."
    }

    func chooseSource() async {
        guard phase == .ready else { return }
        message = nil

        if usesMicrophone {
            phase = .requestingMicrophone
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                returnToReady("Allow Screen Recorder under Privacy & Security → Microphone, or turn the microphone off to record without narration.")
                return
            }
        }

        phase = .choosingSource
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow, .singleDisplay]
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        picker.present()
    }

    func stop() async {
        guard case .recording = phase, let capture else { return }
        await endCapture(capture)
    }

    func cancelSourceSelection() {
        guard phase == .choosingSource else { return }
        returnToReady()
    }

    func openLastRecording() {
        guard let lastRecording else { return }
        if !NSWorkspace.shared.open(lastRecording.url) {
            message = "The last recording couldn’t be opened. Check whether it was moved in Finder."
        }
    }

    func revealLastRecording() {
        guard let lastRecording else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastRecording.url])
    }

    private func start(with filter: SCContentFilter) async {
        guard phase == .choosingSource else { return }
        phase = .starting

        do {
            let url = try newRecordingURL()
            let configuration = SCStreamConfiguration()
            let sourceSize = filter.contentRect.size
            let pixelScale = CGFloat(filter.pointPixelScale)
            guard sourceSize.width > 0, sourceSize.height > 0, pixelScale > 0 else {
                returnToReady("That source has no visible area. Choose another window or display.")
                return
            }
            // Keep source pixels where possible and fit larger sources within a 4K frame in either orientation.
            let width = sourceSize.width * pixelScale
            let height = sourceSize.height * pixelScale
            let scale = min(1, 3840 / max(width, height), 2160 / min(width, height))
            configuration.width = max(2, Int(width * scale / 2) * 2)
            configuration.height = max(2, Int(height * scale / 2) * 2)
            configuration.captureResolution = .best
            // Brief baseline: standard dynamic range, at most 30 frames per second.
            configuration.captureDynamicRange = .SDR
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.showsCursor = true
            configuration.captureMicrophone = usesMicrophone
            let microphone = usesMicrophone ? microphones.resolve() : nil
            if let microphone {
                // nil follows the Mac's default input; otherwise use the owner's remembered mic.
                configuration.microphoneCaptureDeviceID = microphone.deviceID
                message = microphone.notice
            }
            lostMicrophone = false

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            let recordingConfiguration = SCRecordingOutputConfiguration()
            recordingConfiguration.outputURL = url
            // Brief baseline: H.264 video in an MP4 file. With the mic on, ScreenCaptureKit adds an AAC audio track.
            guard recordingConfiguration.availableVideoCodecTypes.contains(.h264),
                  recordingConfiguration.availableOutputFileTypes.contains(.mp4) else {
                returnToReady("This Mac can’t record H.264 MP4 right now. Try again after restarting the app.")
                return
            }
            recordingConfiguration.outputFileType = .mp4
            recordingConfiguration.videoCodecType = .h264

            let output = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
            try stream.addRecordingOutput(output)
            let capture = Capture(stream: stream, output: output, url: url, includesMicrophone: usesMicrophone,
                                  cleansVoice: usesMicrophone && cleansVoice,
                                  microphoneID: microphone?.activeID, microphoneName: microphone?.name,
                                  microphoneNotice: microphone?.notice)
            self.capture = capture
            scheduleTimeout(for: capture, message: "Capture didn’t start. Choose the window or display again.")
            do {
                try await stream.startCapture()
            } catch {
                await failCapture(capture, message: "Couldn’t start recording. \(error.localizedDescription)")
            }
        } catch {
            returnToReady("Couldn’t start recording. \(error.localizedDescription)")
        }
    }

    private func endCapture(_ capture: Capture) async {
        phase = .saving
        scheduleTimeout(for: capture, message: "The recording didn’t finish saving. Check the Screen Recorder folder in Movies.")
        do {
            try await capture.stream.stopCapture()
        } catch {
            // A stop from the system menu can race our stop request. Allow the output to finalize.
            guard self.capture?.output === capture.output, captureTimeout != nil else { return }
            scheduleTimeout(for: capture, message: "Couldn’t stop recording. \(error.localizedDescription)")
        }
    }

    private func scheduleTimeout(for capture: Capture, message: String) {
        captureTimeout?.cancel()
        captureTimeout = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            guard let self, self.capture?.output === capture.output else { return }
            await self.failCapture(capture, message: message)
        }
    }

    private func finishCapture(_ capture: Capture) async {
        phase = .saving
        captureTimeout?.cancel()
        captureTimeout = nil

        let asset = AVURLAsset(url: capture.url)
        do {
            let duration = try await asset.load(.duration).seconds
            let video = try await asset.loadTracks(withMediaType: .video)
            guard duration.isFinite, duration > 0, !video.isEmpty else {
                returnToReady("No video was saved. Record for a little longer and try again.")
                return
            }

            let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
            guard self.capture?.output === capture.output else { return }
            var warning = capture.includesMicrophone && !hasAudio
                ? "Video saved, but it has no microphone track. Check your input before recording again."
                : nil
            if lostMicrophone && hasAudio {
                warning = "Recording saved. \(capture.microphoneName ?? "The microphone") was disconnected partway through, so the voice may stop early. Choose another microphone if it isn’t plugged back in."
            }
            if let notice = capture.microphoneNotice {
                warning = [notice, warning].compactMap { $0 }.joined(separator: " ")
            }
            if capture.cleansVoice && hasAudio {
                phase = .cleaningVoice
                do {
                    try await VoiceCleanup.apply(to: capture.url)
                } catch {
                    warning = "Recording saved with the original sound. Voice cleanup didn’t finish. \(error.localizedDescription)"
                }
                guard self.capture?.output === capture.output else { return }
            }
            lastRecording = Recording(url: capture.url, duration: duration)
            returnToReady(warning)
        } catch {
            guard self.capture?.output === capture.output else { return }
            returnToReady("Couldn’t verify the saved file. Check the Screen Recorder folder in Movies. \(error.localizedDescription)")
        }
    }

    private func failCapture(_ capture: Capture, message: String) async {
        guard self.capture?.output === capture.output else { return }
        phase = .saving
        captureTimeout?.cancel()
        captureTimeout = nil
        self.capture = nil
        try? await capture.stream.stopCapture()
        returnToReady(message)
    }

    private func returnToReady(_ message: String? = nil) {
        if phase != .ready && phase != .requestingMicrophone {
            let picker = SCContentSharingPicker.shared
            picker.remove(self)
            picker.isActive = false
        }
        captureTimeout?.cancel()
        captureTimeout = nil
        capture = nil
        lostMicrophone = false
        self.message = message
        phase = .ready
    }

    private func newRecordingURL() throws -> URL {
        let movies = try FileManager.default.url(for: .moviesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = movies.appending(path: "Screen Recorder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let timestamp = Date.now.ISO8601Format().replacingOccurrences(of: ":", with: "")
        let suffix = UUID().uuidString.prefix(6)
        return folder.appending(path: "Recording \(timestamp) \(suffix).mp4", directoryHint: .notDirectory)
    }
}

extension ScreenRecorder: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        guard stream == nil else { return }
        Task { @MainActor [weak self] in
            guard let self, self.phase == .choosingSource else { return }
            self.cancelSourceSelection()
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        guard stream == nil else { return }
        let selection = PickerSelection(filter: filter)
        Task { @MainActor [weak self] in await self?.start(with: selection.filter) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, self.phase == .choosingSource else { return }
            self.returnToReady("Couldn’t open the screen picker. Check Privacy & Security → Screen & System Audio Recording, then try again. \(error.localizedDescription)")
        }
    }
}

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let streamID = ObjectIdentifier(stream)
        Task { @MainActor [weak self] in
            guard let self, let capture = self.capture, ObjectIdentifier(capture.stream) == streamID,
                  self.phase != .saving, self.phase != .cleaningVoice else { return }
            self.phase = .saving
            self.scheduleTimeout(for: capture, message: "Screen capture ended before the file could be saved. \(error.localizedDescription)")
        }
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let outputID = ObjectIdentifier(recordingOutput)
        let started = Date.now
        Task { @MainActor [weak self] in
            guard let self, let capture = self.capture, ObjectIdentifier(capture.output) == outputID,
                  self.phase == .starting else { return }
            self.captureTimeout?.cancel()
            self.captureTimeout = nil
            self.phase = .recording(started)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let outputID = ObjectIdentifier(recordingOutput)
        Task { @MainActor [weak self] in
            guard let self, let capture = self.capture, ObjectIdentifier(capture.output) == outputID else { return }
            await self.finishCapture(capture)
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let outputID = ObjectIdentifier(recordingOutput)
        Task { @MainActor [weak self] in
            guard let self, let capture = self.capture, ObjectIdentifier(capture.output) == outputID else { return }
            await self.failCapture(capture, message: "Couldn’t save the recording. \(error.localizedDescription)")
        }
    }
}
