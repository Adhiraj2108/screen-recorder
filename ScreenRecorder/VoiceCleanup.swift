import AVFoundation
import AudioToolbox

/// Cleans up the narration in a finished recording, after ScreenCaptureKit has saved it.
///
/// ScreenCaptureKit has no setting for noise or echo reduction on the microphone, so the cleanup runs on the
/// saved file instead. The audio track is taken out, run through Apple's voice isolation unit (reduces
/// background noise and room echo), a gentle rumble filter, a small level boost and a peak limiter, then
/// encoded to AAC and put back at exactly the time the original track started. The video is copied as is.
///
/// If any step fails, the original file is left untouched.
enum VoiceCleanup {
    /// About 26% louder. The limiter stops the boost from clipping on loud peaks.
    static let boostDecibels: Float = 2
    /// Removes desk thumps, fan and traffic rumble below the speaking voice.
    static let rumbleFilterHertz: Float = 80
    /// Peaks are held about 1 dB below full scale so the AAC encoder never clips.
    static let ceilingDecibels: Float = -1
    /// AAC bit rate per channel. The earlier recordings used about 53 kbps per channel.
    static let bitRatePerChannel = 96_000

    enum CleanupError: LocalizedError {
        case noAudio
        case unavailable(String)
        case renderFailed
        case resultMismatch

        var errorDescription: String? {
            switch self {
            case .noAudio: "The recording has no microphone track."
            case let .unavailable(step): "\(step) isn’t available on this Mac."
            case .renderFailed: "The audio couldn’t be processed."
            case .resultMismatch: "The cleaned file didn’t match the original length."
            }
        }
    }

    /// Replaces the audio track of the MP4 at `url` with a cleaned-up version. The original stays if anything fails.
    @concurrent
    static func apply(to url: URL) async throws {
        let workFolder = FileManager.default.temporaryDirectory
            .appending(path: "VoiceCleanup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workFolder) }

        let original = AVURLAsset(url: url)
        guard let originalAudio = try await original.loadTracks(withMediaType: .audio).first else {
            throw CleanupError.noAudio
        }
        let audioRange = try await originalAudio.load(.timeRange)
        let originalDuration = try await original.load(.duration)

        // 1. Copy the AAC track out without re-encoding, so Core Audio can decode it.
        let extracted = workFolder.appending(path: "original.m4a")
        let audioOnly = AVMutableComposition()
        guard let extractTrack = audioOnly.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CleanupError.unavailable("Audio extraction")
        }
        try extractTrack.insertTimeRange(audioRange, of: originalAudio, at: .zero)
        try await export(audioOnly, to: extracted, as: .m4a)

        // 2. Clean up the sound.
        let cleaned = workFolder.appending(path: "cleaned.m4a")
        try process(from: extracted, to: cleaned)

        // 3. Put the cleaned audio back at the same start time, next to the untouched video.
        let combined = AVMutableComposition()
        for videoTrack in try await original.loadTracks(withMediaType: .video) {
            guard let track = combined.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CleanupError.unavailable("Video copy")
            }
            let range = try await videoTrack.load(.timeRange)
            try track.insertTimeRange(range, of: videoTrack, at: range.start)
            track.preferredTransform = try await videoTrack.load(.preferredTransform)
        }
        let cleanedAsset = AVURLAsset(url: cleaned)
        guard let cleanedAudio = try await cleanedAsset.loadTracks(withMediaType: .audio).first,
              let audioTrack = combined.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CleanupError.renderFailed
        }
        let cleanedRange = try await cleanedAudio.load(.timeRange)
        let length = CMTimeMinimum(cleanedRange.duration, audioRange.duration)
        try audioTrack.insertTimeRange(CMTimeRange(start: cleanedRange.start, duration: length), of: cleanedAudio, at: audioRange.start)

        // Write next to the recording so the final swap is a same-volume rename.
        let result = url.deletingLastPathComponent()
            .appending(path: ".\(UUID().uuidString)-cleaned.mp4", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: result) }
        try await export(combined, to: result, as: .mp4)

        // 4. Only replace the original once the new file checks out.
        let check = AVURLAsset(url: result)
        let checkDuration = try await check.load(.duration)
        let hasVideo = try await !check.loadTracks(withMediaType: .video).isEmpty
        let hasAudio = try await !check.loadTracks(withMediaType: .audio).isEmpty
        guard hasVideo, hasAudio, abs((checkDuration - originalDuration).seconds) < 0.25 else {
            throw CleanupError.resultMismatch
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: result)
    }

    private static func export(_ asset: AVAsset, to url: URL, as fileType: AVFileType) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw CleanupError.unavailable("Passthrough export")
        }
        try await session.export(to: url, as: fileType)
    }

    /// Runs the audio through the cleanup chain faster than real time and writes it as AAC.
    private static func process(from inputURL: URL, to outputURL: URL) throws {
        let input = try AVAudioFile(forReading: inputURL)
        let format = input.processingFormat
        let output = try AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: bitRatePerChannel * Int(format.channelCount),
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        let isolation = AVAudioUnitEffect(audioComponentDescription: appleEffect(kAudioUnitSubType_AUSoundIsolation))
        let isolationUnit = isolation.audioUnit
        guard AudioUnitSetParameter(isolationUnit, kAUSoundIsolationParam_WetDryMixPercent, kAudioUnitScope_Global, 0, 100, 0) == noErr else {
            throw CleanupError.unavailable("Voice isolation")
        }
        // The higher-quality voice model (macOS 15 and later). If it can't be selected, the standard model stays on.
        _ = AudioUnitSetParameter(isolationUnit, kAUSoundIsolationParam_SoundToIsolate, kAudioUnitScope_Global, 0,
                                  AudioUnitParameterValue(kAUSoundIsolationSoundType_HighQualityVoice), 0)

        let filterAndBoost = AVAudioUnitEQ(numberOfBands: 1)
        let rumble = filterAndBoost.bands[0]
        rumble.filterType = .highPass
        rumble.frequency = rumbleFilterHertz
        rumble.bypass = false
        // Boost into the limiter by the ceiling margin too; the main mixer takes that margin back off below.
        filterAndBoost.globalGain = boostDecibels - ceilingDecibels

        let limiter = AVAudioUnitEffect(audioComponentDescription: appleEffect(kAudioUnitSubType_PeakLimiter))

        for node in [player, isolation, filterAndBoost, limiter] as [AVAudioNode] {
            engine.attach(node)
        }
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        engine.connect(player, to: isolation, format: format)
        engine.connect(isolation, to: filterAndBoost, format: format)
        engine.connect(filterAndBoost, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = pow(10, ceilingDecibels / 20)

        player.scheduleFile(input, at: nil)
        try engine.start()
        defer { engine.stop() }
        player.play()

        // Voice isolation and the limiter delay the sound slightly. Drop that much from the start and render
        // the same amount past the end, so the cleaned audio lines up sample for sample with the original.
        let latency = isolation.auAudioUnit.latency + limiter.auAudioUnit.latency + filterAndBoost.auAudioUnit.latency
        var framesToSkip = AVAudioFramePosition((latency * format.sampleRate).rounded())
        let totalFrames = input.length + framesToSkip

        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw CleanupError.renderFailed
        }
        while engine.manualRenderingSampleTime < totalFrames {
            let remaining = totalFrames - engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), remaining))
            switch try engine.renderOffline(frames, to: buffer) {
            case .success:
                let rendered = AVAudioFramePosition(buffer.frameLength)
                if framesToSkip >= rendered {
                    framesToSkip -= rendered
                } else {
                    try write(buffer, droppingFirst: AVAudioFrameCount(framesToSkip), to: output)
                    framesToSkip = 0
                }
            case .cannotDoInCurrentContext:
                continue
            case .insufficientDataFromInputNode, .error:
                throw CleanupError.renderFailed
            @unknown default:
                throw CleanupError.renderFailed
            }
        }
    }

    private static func write(_ buffer: AVAudioPCMBuffer, droppingFirst skip: AVAudioFrameCount, to file: AVAudioFile) throws {
        guard skip > 0 else {
            try file.write(from: buffer)
            return
        }
        let kept = buffer.frameLength - skip
        guard let tail = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: kept),
              let source = buffer.floatChannelData, let destination = tail.floatChannelData else {
            throw CleanupError.renderFailed
        }
        for channel in 0..<Int(buffer.format.channelCount) {
            destination[channel].update(from: source[channel] + Int(skip), count: Int(kept))
        }
        tail.frameLength = kept
        try file.write(from: tail)
    }

    private static func appleEffect(_ subType: OSType) -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: subType,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }
}
