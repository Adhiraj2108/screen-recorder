import AVFoundation
import Observation

/// A live level for the microphone that recordings will use.
///
/// It listens to the mic separately from ScreenCaptureKit, so the recording path and voice cleanup are untouched.
/// It only runs while the microphone switch is on and access has already been granted (it never asks by itself).
@MainActor
@Observable
final class InputMeter {
    /// 0 is silence (−60 dB or quieter), 1 is full scale.
    private(set) var level: Float = 0
    /// Short-lived peak marker, so brief loud sounds stay visible.
    private(set) var peak: Float = 0
    private(set) var isRunning = false
    /// True when access hasn't been granted yet, so the meter can't run.
    private(set) var needsAccess = false

    @ObservationIgnored private var session: AVCaptureSession?
    @ObservationIgnored private var deviceID: String?
    @ObservationIgnored private let tap = LevelTap()
    @ObservationIgnored private let queue = DispatchQueue(label: "InputMeter.audio")
    @ObservationIgnored private var peakHeldUntil = Date.distantPast

    init() {
        tap.onLevel = { [weak self] decibels in
            Task { @MainActor in self?.receive(decibels) }
        }
    }

    /// Listen to `deviceID` (or the Mac's default input when nil). Pass `enabled: false` to stop.
    func update(enabled: Bool, deviceID: String?) {
        guard enabled else { stop(); return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            stop()
            needsAccess = true
            return
        }
        needsAccess = false
        let device = deviceID.flatMap(AVCaptureDevice.init(uniqueID:)) ?? AVCaptureDevice.default(for: .audio)
        guard let device else { stop(); return }
        if isRunning, device.uniqueID == self.deviceID { return }
        stop()

        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        // Ask for 32-bit float samples so levels can be read directly.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(tap, queue: queue)
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(output) else { return }
            session.addInput(input)
            session.addOutput(output)
        } catch {
            return
        }
        self.session = session
        self.deviceID = device.uniqueID
        isRunning = true
        let running = SessionHandle(session: session)
        queue.async { running.session.startRunning() }
    }

    func stop() {
        if let session {
            let stopping = SessionHandle(session: session)
            queue.async { stopping.session.stopRunning() }
        }
        session = nil
        deviceID = nil
        isRunning = false
        level = 0
        peak = 0
    }

    private func receive(_ decibels: Float) {
        guard isRunning else { return }
        let target = max(0, min(1, (decibels + 60) / 60))
        // Rise fast, fall gently, like a standard meter.
        level = target > level ? target : max(target, level - 0.06)
        let now = Date.now
        if target >= peak || now > peakHeldUntil {
            peak = target
            peakHeldUntil = now.addingTimeInterval(1)
        }
    }
}

/// Hands the session to the audio queue, which is the only place it is started or stopped.
private struct SessionHandle: @unchecked Sendable {
    let session: AVCaptureSession
}

/// Reads peak levels on the audio queue and reports them in decibels.
private final class LevelTap: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onLevel: (@Sendable (Float) -> Void)?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let format = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else { return }
        var peak: Float = 0
        do {
            try sampleBuffer.withAudioBufferList { list, _ in
                for buffer in list {
                    guard let data = buffer.mData else { continue }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let samples = data.assumingMemoryBound(to: Float.self)
                    for index in 0..<count { peak = max(peak, abs(samples[index])) }
                }
            }
        } catch {
            return
        }
        onLevel?(20 * log10(max(peak, 0.000_001)))
    }
}
