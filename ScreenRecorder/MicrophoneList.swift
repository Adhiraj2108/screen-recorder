import AVFoundation
import Observation

/// The microphones the owner can pick from, and the remembered choice.
///
/// A `nil` choice means "follow the Mac's default input" (System Settings → Sound → Input).
/// A chosen mic is remembered by its stable device ID, so it is used again whenever it is plugged in,
/// and the Mac's default is used (with a note) while it is missing.
@MainActor
@Observable
final class MicrophoneList {
    struct Microphone: Identifiable, Hashable {
        let id: String
        let name: String
    }

    /// What a recording will actually use, worked out just before capture starts.
    struct Resolved {
        /// Passed to ScreenCaptureKit. `nil` lets it use the Mac's default input.
        let deviceID: String?
        /// The ID of the device in use, for spotting it being unplugged mid-recording.
        let activeID: String?
        let name: String
        /// Set when the remembered mic is missing and the default stands in for it.
        let notice: String?
    }

    private enum Key {
        static let id = "microphoneDeviceID"
        static let name = "microphoneDeviceName"
    }

    private(set) var available: [Microphone] = []
    private(set) var defaultName: String?

    /// The remembered mic, or `nil` for the Mac's default. Change it with `select(_:)`.
    private(set) var selectedID: String?

    /// Name of the remembered mic, kept so it can be shown while unplugged.
    private(set) var rememberedName: String?

    /// Called with the device ID of any mic that goes away.
    @ObservationIgnored var onDisconnect: ((String) -> Void)?
    /// Called when the pick changes or a mic is plugged in or out.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let defaults = UserDefaults.standard
        selectedID = defaults.string(forKey: Key.id)
        rememberedName = defaults.string(forKey: Key.name)
        refresh()

        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            let isDisconnect = name == AVCaptureDevice.wasDisconnectedNotification
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let id = (note.object as? AVCaptureDevice).flatMap { $0.hasMediaType(.audio) ? $0.uniqueID : nil }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refresh()
                    if isDisconnect, let id { self.onDisconnect?(id) }
                    self.onChange?()
                }
            })
        }
    }

    /// Remember the owner's pick. Only called from the menu, so launching never overwrites the saved choice.
    func select(_ id: String?) {
        guard id != selectedID else { return }
        let defaults = UserDefaults.standard
        if let id, let mic = available.first(where: { $0.id == id }) {
            selectedID = id
            rememberedName = mic.name
            defaults.set(id, forKey: Key.id)
            defaults.set(mic.name, forKey: Key.name)
        } else {
            selectedID = nil
            rememberedName = nil
            defaults.removeObject(forKey: Key.id)
            defaults.removeObject(forKey: Key.name)
        }
        onChange?()
    }

    /// True when a mic was chosen but is not plugged in right now.
    var selectedIsMissing: Bool {
        guard let selectedID else { return false }
        return !available.contains { $0.id == selectedID }
    }

    func refresh() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        available = session.devices
            .filter(\.isConnected)
            .map { Microphone(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        defaultName = AVCaptureDevice.default(for: .audio)?.localizedName
    }

    func resolve() -> Resolved {
        refresh()
        let fallback = AVCaptureDevice.default(for: .audio)
        let fallbackName = fallback?.localizedName ?? "the Mac’s default microphone"
        guard let selectedID else {
            return Resolved(deviceID: nil, activeID: fallback?.uniqueID, name: fallbackName, notice: nil)
        }
        if let mic = available.first(where: { $0.id == selectedID }) {
            return Resolved(deviceID: mic.id, activeID: mic.id, name: mic.name, notice: nil)
        }
        let missing = rememberedName ?? "Your chosen microphone"
        return Resolved(deviceID: nil, activeID: fallback?.uniqueID, name: fallbackName,
                        notice: "\(missing) isn’t connected, so \(fallbackName) was used.")
    }
}
