import AVFoundation
import AudioToolbox

/// Cleans up the narration in a finished recording, after ScreenCaptureKit has saved it.
///
/// ScreenCaptureKit has no setting for noise or echo reduction on the microphone, so the cleanup runs on the
/// saved file instead. The audio track is decoded, run through Apple's voice isolation unit (reduces
/// background noise and room echo), a gentle rumble filter, a small level boost and a peak limiter, then
/// encoded to AAC once and written back at exactly the time the original track started. The video samples
/// are copied as they are, without re-encoding.
///
/// When the recording also has the Mac's own sound (a second audio track), the voice is cleaned and the Mac sound is
/// mixed in untouched, so the file ends up with one stereo audio track that every player and the viewing page can
/// play. The Mac sound never goes through voice isolation, which would treat music or a video's sound as noise.
///
/// If any step fails, the original file is left untouched.
enum VoiceCleanup {
    /// The Mac's sound sits this far below the cleaned voice in the mix, so narration stays easy to hear over it.
    static let systemSoundDecibels: Float = -4
    /// Which audio track is the microphone when the file has two. ScreenCaptureKit adds the system audio first.
    static let microphoneTrackIndexWithSystemSound = 1
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
        case noSystemSound

        var errorDescription: String? {
            switch self {
            case .noAudio: "The recording has no microphone track."
            case let .unavailable(step): "\(step) isn’t available on this Mac."
            case .renderFailed: "The audio couldn’t be processed."
            case .resultMismatch: "The cleaned file didn’t match the original length."
            case .noSystemSound: "The recording has no separate Mac sound track."
            }
        }
    }

    /// Replaces the audio of the MP4 at `url` with a cleaned-up version. The original stays if anything fails.
    ///
    /// - Parameters:
    ///   - cleansVoice: Run the microphone through voice isolation, rumble filter and boost.
    ///   - mixesSystemSound: The file has the Mac's sound as a second audio track; mix it with the voice into one track.
    @concurrent
    static func apply(to url: URL, cleansVoice: Bool = true, mixesSystemSound: Bool = false) async throws {
        let workFolder = FileManager.default.temporaryDirectory
            .appending(path: "VoiceCleanup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workFolder) }

        let original = AVURLAsset(url: url)
        let audioTracks = try await original.loadTracks(withMediaType: .audio)
        guard let firstAudio = audioTracks.first else {
            throw CleanupError.noAudio
        }
        var originalAudio = firstAudio
        var systemAudio: AVAssetTrack?
        if mixesSystemSound {
            guard audioTracks.count >= 2 else { throw CleanupError.noSystemSound }
            let micIndex = await microphoneIndex(in: audioTracks)
            originalAudio = audioTracks[micIndex]
            systemAudio = audioTracks[micIndex == 0 ? 1 : 0]
        }
        guard let originalVideo = try await original.loadTracks(withMediaType: .video).first else {
            throw CleanupError.unavailable("Video copy")
        }
        let originalDuration = try await original.load(.duration)

        // 1. Decode the narration as it plays on the video's timeline, from time zero. ScreenCaptureKit often starts
        //    the microphone a few hundred ms after the video (stored as an empty edit), and that lead-in comes out as
        //    silence here, as would any gap. So sample N of the decoded audio sits exactly at N / sample rate.
        let decoded = workFolder.appending(path: "decoded.caf")
        try await decodeTimeline(of: original, track: originalAudio, to: decoded)

        // 2. Clean it up into uncompressed audio, so no encoder delay creeps in yet.
        //    With the Mac's sound, that is also decoded on the video's timeline and mixed in here, after the voice chain.
        var decodedSystem: URL?
        if let systemAudio {
            let url = workFolder.appending(path: "system.caf")
            try await decodeTimeline(of: original, track: systemAudio, to: url)
            decodedSystem = url
        }
        let cleaned = workFolder.appending(path: "cleaned.caf")
        let cleanedFormat = try process(from: decoded, systemSound: decodedSystem, cleansVoice: cleansVoice, to: cleaned)
        try? FileManager.default.removeItem(at: decoded)

        // 3. Write a new MP4: the video samples copied exactly, the cleaned audio encoded once to AAC from time zero.
        let result = url.deletingLastPathComponent()
            .appending(path: ".\(UUID().uuidString)-cleaned.mp4", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: result) }
        try await remux(video: originalVideo, of: original, cleanedAudio: cleaned, format: cleanedFormat, to: result)

        // 4. Only replace the original once the new file checks out.
        let check = AVURLAsset(url: result)
        let checkDuration = try await check.load(.duration)
        let hasAudio = try await !check.loadTracks(withMediaType: .audio).isEmpty
        let hasVideo = try await !check.loadTracks(withMediaType: .video).isEmpty
        guard hasAudio, hasVideo, abs((checkDuration - originalDuration).seconds) < 0.25 else {
            throw CleanupError.resultMismatch
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: result)
    }

    /// Picks the microphone among the audio tracks. A track whose name says microphone wins; otherwise the fixed order is used.
    private static func microphoneIndex(in tracks: [AVAssetTrack]) async -> Int {
        for (index, track) in tracks.enumerated() {
            let items = ((try? await track.load(.metadata)) ?? []) + ((try? await track.load(.commonMetadata)) ?? [])
            for item in items {
                if let text = try? await item.load(.stringValue), text.localizedCaseInsensitiveContains("microphone") {
                    return index
                }
            }
        }
        // The Mac's sound is always saved as stereo, so a lone mono track is the microphone.
        var channelCounts: [Int] = []
        for track in tracks {
            let description = try? await track.load(.formatDescriptions).first
            let channels = description.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
            channelCounts.append(Int(channels ?? 0))
        }
        let mono = channelCounts.indices.filter { channelCounts[$0] == 1 }
        if mono.count == 1 { return mono[0] }
        return min(microphoneTrackIndexWithSystemSound, tracks.count - 1)
    }

    /// Writes the track's audio, as heard on the asset's timeline from time zero, to an uncompressed file.
    private static func decodeTimeline(of asset: AVAsset, track: AVAssetTrack, to url: URL) async throws {
        guard let description = try await track.load(.formatDescriptions).first,
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              let format = AVAudioFormat(standardFormatWithSampleRate: stream.mSampleRate,
                                         channels: AVAudioChannelCount(max(1, stream.mChannelsPerFrame))) else {
            throw CleanupError.unavailable("Audio decoding")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        guard reader.startReading() else { throw reader.error ?? CleanupError.renderFailed }
        while let sample = output.copyNextSampleBuffer() {
            let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
            guard frames > 0 else { continue }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
                throw CleanupError.renderFailed
            }
            buffer.frameLength = frames
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                                      into: buffer.mutableAudioBufferList)
            guard status == noErr else { throw CleanupError.renderFailed }
            try file.write(from: buffer)
        }
        guard reader.status == .completed else { throw reader.error ?? CleanupError.renderFailed }
    }

    private static func remux(video videoTrack: AVAssetTrack, of original: AVAsset, cleanedAudio: URL, format: AVAudioFormat, to url: URL) async throws {
        let channelCount = Int(format.channelCount)
        let videoReader = try AVAssetReader(asset: original)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        videoReader.add(videoOutput)

        let audioAsset = AVURLAsset(url: cleanedAudio)
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw CleanupError.renderFailed
        }
        let audioReader = try AVAssetReader(asset: audioAsset)
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        audioReader.add(audioOutput)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                            sourceFormatHint: try await videoTrack.load(.formatDescriptions).first)
        videoInput.transform = try await videoTrack.load(.preferredTransform)
        videoInput.expectsMediaDataInRealTime = false
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: bitRatePerChannel * channelCount,
        ])
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw CleanupError.unavailable("MP4 writing")
        }
        writer.add(videoInput)
        writer.add(audioInput)

        guard videoReader.startReading(), audioReader.startReading(), writer.startWriting() else {
            throw videoReader.error ?? audioReader.error ?? writer.error ?? CleanupError.renderFailed
        }
        writer.startSession(atSourceTime: .zero)

        var videoDone = false
        var audioDone = false
        while !(videoDone && audioDone) {
            var progressed = false
            if !videoDone, videoInput.isReadyForMoreMediaData {
                progressed = true
                if let sample = videoOutput.copyNextSampleBuffer() {
                    guard videoInput.append(sample) else { throw writer.error ?? CleanupError.renderFailed }
                } else {
                    guard videoReader.status == .completed else { throw videoReader.error ?? CleanupError.renderFailed }
                    videoInput.markAsFinished()
                    videoDone = true
                }
            }
            if !audioDone, audioInput.isReadyForMoreMediaData {
                progressed = true
                if let sample = audioOutput.copyNextSampleBuffer() {
                    // The cleaned audio already starts at time zero of the video's timeline.
                    guard audioInput.append(sample) else { throw writer.error ?? CleanupError.renderFailed }
                } else {
                    guard audioReader.status == .completed else { throw audioReader.error ?? CleanupError.renderFailed }
                    audioInput.markAsFinished()
                    audioDone = true
                }
            }
            if !progressed {
                if writer.status == .failed { throw writer.error ?? CleanupError.renderFailed }
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CleanupError.renderFailed }
    }

    /// Runs the recording's audio through the cleanup chain faster than real time and writes it as uncompressed audio.
    /// Returns the audio format (sample rate and channel count) of the cleaned file.
    private static func process(from inputURL: URL, systemSound systemURL: URL?, cleansVoice: Bool, to outputURL: URL) throws -> AVAudioFormat {
        let input = try AVAudioFile(forReading: inputURL)
        let voiceFormat = input.processingFormat
        let systemFile = try systemURL.map { try AVAudioFile(forReading: $0) }
        // Voice only keeps the microphone's own layout. With the Mac's sound the result is stereo at the voice's rate.
        guard let format = systemFile == nil ? voiceFormat
                : AVAudioFormat(standardFormatWithSampleRate: voiceFormat.sampleRate, channels: 2) else {
            throw CleanupError.unavailable("Stereo mixing")
        }
        let output = try AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        // The voice chain: isolation, rumble filter and boost. It is skipped when the owner turned cleanup off.
        var voiceChain: [AVAudioNode] = []
        var isolation: AVAudioUnitEffect?
        var filterAndBoost: AVAudioUnitEQ?
        if cleansVoice {
            let unit = AVAudioUnitEffect(audioComponentDescription: appleEffect(kAudioUnitSubType_AUSoundIsolation))
            guard let isolationParameters = unit.auAudioUnit.parameterTree,
                  let mix = isolationParameters.parameter(withAddress: AUParameterAddress(kAUSoundIsolationParam_WetDryMixPercent)) else {
                throw CleanupError.unavailable("Voice isolation")
            }
            mix.value = 100
            // The higher-quality voice model (macOS 15 and later). If it can't be selected, the standard model stays on.
            isolationParameters.parameter(withAddress: AUParameterAddress(kAUSoundIsolationParam_SoundToIsolate))?.value =
                AUValue(kAUSoundIsolationSoundType_HighQualityVoice)

            let eq = AVAudioUnitEQ(numberOfBands: 1)
            let rumble = eq.bands[0]
            rumble.filterType = .highPass
            rumble.frequency = rumbleFilterHertz
            rumble.bypass = false
            // Boost into the limiter by the ceiling margin too; the main mixer takes that margin back off below.
            eq.globalGain = boostDecibels - ceilingDecibels
            isolation = unit
            filterAndBoost = eq
            voiceChain = [unit, eq]
        }

        let limiter = AVAudioUnitEffect(audioComponentDescription: appleEffect(kAudioUnitSubType_PeakLimiter))

        for node in [player, limiter] + voiceChain {
            engine.attach(node)
        }
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)

        // Voice (and, if present, the Mac's sound) meet in a mixer that feeds the limiter.
        var voiceTail: AVAudioNode = player
        let voiceTailFormat = voiceFormat
        for node in voiceChain {
            engine.connect(voiceTail, to: node, format: voiceTailFormat)
            voiceTail = node
        }
        var systemPlayer: AVAudioPlayerNode?
        if systemFile != nil {
            let blend = AVAudioMixerNode()
            let sound = AVAudioPlayerNode()
            engine.attach(blend)
            engine.attach(sound)
            engine.connect(voiceTail, to: blend, format: voiceTailFormat)
            engine.connect(sound, to: blend, format: systemFile?.processingFormat)
            engine.connect(blend, to: limiter, format: format)
            // The main mixer takes the ceiling margin off everything, so add it back to get the intended level.
            sound.volume = pow(10, (systemSoundDecibels - ceilingDecibels) / 20)
            systemPlayer = sound
        } else {
            engine.connect(voiceTail, to: limiter, format: voiceTailFormat)
        }
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = pow(10, ceilingDecibels / 20)

        // Voice isolation and the limiter delay the sound slightly. Drop that much from the start and render
        // the same amount past the end, so the cleaned audio lines up sample for sample with the original.
        // The Mac's sound skips the voice chain, so it starts that much later to stay level with the voice.
        let latency = (isolation?.auAudioUnit.latency ?? 0) + limiter.auAudioUnit.latency + (filterAndBoost?.auAudioUnit.latency ?? 0)
        var framesToSkip = AVAudioFramePosition((latency * format.sampleRate).rounded())
        let totalFrames = max(input.length, systemFile.map { AVAudioFramePosition(Double($0.length) * format.sampleRate / $0.processingFormat.sampleRate) } ?? 0) + framesToSkip

        player.scheduleFile(input, at: nil)
        if let systemPlayer, let systemFile {
            let start = framesToSkip > 0 ? AVAudioTime(sampleTime: framesToSkip, atRate: format.sampleRate) : nil
            systemPlayer.scheduleFile(systemFile, at: start)
        }
        try engine.start()
        defer { engine.stop() }
        player.play()
        systemPlayer?.play()

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
        return format
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
