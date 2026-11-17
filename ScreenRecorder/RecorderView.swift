import SwiftUI

struct RecorderView: View {
    @Bindable var recorder: ScreenRecorder

    var body: some View {
        RecorderPanel(
            phase: recorder.phase,
            usesMicrophone: $recorder.usesMicrophone,
            cleansVoice: $recorder.cleansVoice,
            recordsSystemSound: $recorder.recordsSystemSound,
            microphoneChoice: MicrophoneChoice(list: recorder.microphones),
            inputLevel: InputLevel(meter: recorder.meter),
            shortcutAvailable: recorder.shortcutAvailable,
            message: recorder.message,
            lastRecordingDuration: recorder.lastRecording?.duration,
            onPrimaryAction: recorder.primaryAction,
            onOpenRecording: recorder.openLastRecording,
            onRevealRecording: recorder.revealLastRecording
        )
    }

}

private struct RecorderPanel: View {
    let phase: ScreenRecorder.Phase
    @Binding var usesMicrophone: Bool
    @Binding var cleansVoice: Bool
    @Binding var recordsSystemSound: Bool
    var microphoneChoice = MicrophoneChoice()
    var inputLevel = InputLevel()
    var shortcutAvailable = true
    var message: String?
    var lastRecordingDuration: TimeInterval?
    var onPrimaryAction: () -> Void = {}
    var onOpenRecording: () -> Void = {}
    var onRevealRecording: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Screen recorder")
                    .font(.system(size: 22, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Text("Record a window or display and save it as an MP4.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                recordingStatus
                    .padding(16)
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "mic")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Microphone")
                        .accessibilityHidden(true)
                    Spacer()
                    Toggle("Microphone", isOn: $usesMicrophone)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(phase != .ready)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                if usesMicrophone {
                    Divider()
                    microphonePicker
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                    levelMeter
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clean up voice")
                        Text(recordsSystemSound && usesMicrophone
                             ? "Off while Mac sound is on (macOS saves both together)"
                             : "Less background noise and echo, slightly louder")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
                    Spacer()
                    Toggle("Clean up voice", isOn: $cleansVoice)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(phase != .ready || !usesMicrophone || recordsSystemSound)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Record Mac sound")
                        Text(usesMicrophone && recordsSystemSound
                             ? "Use headphones so the voice doesn’t pick up the speakers"
                             : "Videos or audio playing on this Mac, mixed with your voice")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
                    Spacer()
                    Toggle("Record Mac sound", isOn: $recordsSystemSound)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(phase != .ready)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark ? Color(white: 0.13) : .white)
                    .shadow(color: .black.opacity(isDark ? 0.5 : 0.10), radius: 2, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isDark ? Color(white: 0.30) : .black.opacity(0.08), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }

            if let message {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(isDark ? 0.16 : 0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if let lastRecordingDuration {
                savedRecording(duration: lastRecordingDuration)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Saved in Movies", systemImage: "internaldrive")
                    Label(shortcutAvailable
                          ? "\(GlobalShortcut.label) starts or stops from any app"
                          : "\(GlobalShortcut.label) is used by another app",
                          systemImage: "keyboard")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                Spacer()
                actionButton
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(24)
        .frame(minWidth: 460, minHeight: 548)
        .background(isDark ? Color(white: 0.09) : Color(red: 0.965, green: 0.961, blue: 0.950))
    }

    private var microphonePicker: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic")
                .foregroundStyle(.clear)
                .accessibilityHidden(true)
            Text("Input")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Spacer()
            Picker("Microphone input", selection: microphoneChoice.selection) {
                Text(microphoneChoice.defaultLabel).tag(String?.none)
                if !microphoneChoice.available.isEmpty || microphoneChoice.missing != nil {
                    Divider()
                }
                ForEach(microphoneChoice.available) { mic in
                    Text(mic.name).tag(Optional(mic.id))
                }
                if let missing = microphoneChoice.missing {
                    Text("\(missing.name) (not connected)").tag(Optional(missing.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 240)
            .disabled(phase != .ready)
        }
    }

    private var levelMeter: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic")
                .foregroundStyle(.clear)
                .accessibilityHidden(true)
            Text("Level")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Spacer()
            if inputLevel.needsAccess {
                Text("Shows after you allow microphone access")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 240, alignment: .leading)
            } else {
                LevelBar(level: inputLevel.level, peak: inputLevel.peak)
                    .frame(width: 240, height: 8)
                    .accessibilityElement()
                    .accessibilityLabel("Microphone level")
                    .accessibilityValue("\(Int(inputLevel.level * 100)) percent")
            }
        }
    }

    private var recordingStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: isRecording ? "record.circle.fill" : "rectangle.dashed")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(isRecording ? Color.red : Color.secondary)
                .frame(width: 36, height: 36)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            Text(statusTitle)
                .font(.system(size: 16, weight: .medium))
            Spacer(minLength: 12)
            if case let .recording(start) = phase {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(timeLabel(context.date.timeIntervalSince(start)))
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .accessibilityLabel("Elapsed recording time")
                        .accessibilityValue(timeLabel(context.date.timeIntervalSince(start)))
                }
            }
        }
    }

    private func savedRecording(duration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .accessibilityHidden(true)
                Text("Recording saved")
                Spacer()
                Text(timeLabel(duration))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Open recording", action: onOpenRecording)
                Button("Show in Finder", action: onRevealRecording)
            }
        }
        .padding(.horizontal, 4)
    }

    private var actionButton: some View {
        Button(action: onPrimaryAction) {
            Label(actionTitle, systemImage: actionIcon)
                .frame(minWidth: 136, minHeight: 36)
        }
        .buttonStyle(RecorderButtonStyle())
        .disabled(phase != .ready && phase != .choosingSource && !isRecording)
    }

    private var actionIcon: String {
        switch phase {
        case .choosingSource: "xmark"
        case .recording: "stop.fill"
        default: "record.circle"
        }
    }

    private var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    private var actionTitle: String {
        switch phase {
        case .ready: "Record"
        case .requestingMicrophone: "Waiting for access…"
        case .choosingSource: "Cancel"
        case .starting: "Starting…"
        case .recording: "Stop recording"
        case .saving: "Saving…"
        case .cleaningVoice: "Cleaning up voice…"
        }
    }

    private var statusTitle: String {
        switch phase {
        case .ready: "Ready to record"
        case .requestingMicrophone: "Microphone access"
        case .choosingSource: "Select a window or display (Esc cancels)"
        case .starting: "Preparing capture"
        case .recording: "Recording"
        case .saving: "Finishing the MP4"
        case .cleaningVoice: "Cleaning up the voice"
        }
    }

    private func timeLabel(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview("Ready", traits: .fixedLayout(width: 480, height: 460)) {
    @Previewable @State var usesMicrophone = true
    @Previewable @State var selected: String? = "headset"
    RecorderPanel(
        phase: .ready, usesMicrophone: $usesMicrophone, cleansVoice: .constant(true), recordsSystemSound: .constant(false),
        microphoneChoice: MicrophoneChoice(
            available: [.init(id: "built-in", name: "MacBook Air Microphone")],
            defaultName: "MacBook Air Microphone",
            missing: .init(id: "headset", name: "USB Headset"),
            selection: $selected))
}

#Preview("Speaking", traits: .fixedLayout(width: 480, height: 460)) {
    RecorderPanel(
        phase: .ready, usesMicrophone: .constant(true), cleansVoice: .constant(true), recordsSystemSound: .constant(false),
        microphoneChoice: MicrophoneChoice(defaultName: "MacBook Air Microphone"),
        inputLevel: InputLevel(level: 0.62, peak: 0.78))
}

#Preview("Recording", traits: .fixedLayout(width: 480, height: 420)) {
    RecorderPanel(phase: .recording(.now.addingTimeInterval(-28)), usesMicrophone: .constant(true), cleansVoice: .constant(true), recordsSystemSound: .constant(false))
}

#Preview("Saved", traits: .fixedLayout(width: 480, height: 420)) {
    RecorderPanel(phase: .ready, usesMicrophone: .constant(true), cleansVoice: .constant(true), recordsSystemSound: .constant(false), lastRecordingDuration: 62)
}

#Preview("Permission denied", traits: .fixedLayout(width: 480, height: 420)) {
    RecorderPanel(
        phase: .ready,
        usesMicrophone: .constant(true),
        cleansVoice: .constant(true), recordsSystemSound: .constant(false),
        message: "Allow Screen Recorder under Privacy & Security → Microphone, or turn the microphone off to record without narration."
    )
}

private struct RecorderButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        configuration.label
            .padding(.horizontal, 14)
            .foregroundStyle(isDark ? .black : .white)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDark ? Color(white: 0.93) : Color(white: 0.12))
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// What the panel needs to show the microphone menu, kept separate so previews don't need real devices.
struct MicrophoneChoice {
    var available: [MicrophoneList.Microphone] = []
    var defaultName: String?
    var missing: MicrophoneList.Microphone?
    var selection: Binding<String?> = .constant(nil)

    var defaultLabel: String {
        defaultName.map { "Mac default (\($0))" } ?? "Mac default"
    }
}

extension MicrophoneChoice {
    @MainActor
    init(list: MicrophoneList) {
        available = list.available
        defaultName = list.defaultName
        if list.selectedIsMissing, let id = list.selectedID {
            missing = MicrophoneList.Microphone(id: id, name: list.rememberedName ?? "Chosen microphone")
        }
        selection = Binding(get: { list.selectedID }, set: { list.select($0) })
    }
}

/// The meter values the panel shows.
struct InputLevel {
    var level: Float = 0
    var peak: Float = 0
    var needsAccess = false
}

extension InputLevel {
    @MainActor
    init(meter: InputMeter) {
        level = meter.level
        peak = meter.peak
        needsAccess = meter.needsAccess
    }
}

/// A horizontal level bar: green for normal speech, amber when loud, red near clipping.
private struct LevelBar: View {
    let level: Float
    let peak: Float
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                Capsule()
                    .fill(color(for: level))
                    .frame(width: width * CGFloat(level))
                if peak > 0.02 {
                    Rectangle()
                        .fill(color(for: peak))
                        .frame(width: 2)
                        .offset(x: max(0, width * CGFloat(peak) - 2))
                }
            }
        }
        .clipShape(Capsule())
    }

    /// Thresholds on the −60…0 dB scale: amber above −12 dB, red above −3 dB.
    private func color(for value: Float) -> Color {
        if value > 0.95 { return .red }
        if value > 0.80 { return .orange }
        return .green
    }
}
