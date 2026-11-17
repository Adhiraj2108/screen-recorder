import Foundation
import Observation

/// Remembers every recording that was uploaded and confirmed, so the app can show its link, delete it online, and
/// tidy the local file away once it has been safe online for a while.
///
/// Safety rules for the local clean-up:
/// - Only a recording whose upload finished and was confirmed by the server (same size online as the file sent) is
///   ever considered. Failed, paused or unfinished uploads are never in this list.
/// - Just before moving a file, the server is asked again that the video is still there and complete. If the server
///   can't be reached, or the video was deleted online, the local file stays.
/// - A file that changed on the Mac since it was uploaded is left alone.
/// - Files go to the Trash, never straight to deletion, so they can be put back.
@MainActor
@Observable
final class UploadLibrary {
    struct Entry: Codable, Identifiable, Equatable {
        var id: String { videoID }
        let videoID: String
        var title: String
        let recordingPath: String
        let shareURL: URL
        let uploadedAt: Date
        /// Size of the copy the server confirmed it holds.
        let onlineBytes: Int
        /// Size and change date of the local recording when it was uploaded, to spot a file edited afterwards.
        let localBytes: Int
        let localModified: Date?
        var local: LocalState = .kept

        enum LocalState: String, Codable { case kept, trashed, gone, changed }
    }

    static let keepDays = 5
    private static let storeKey = "uploadLibrary"
    static let autoTrashKey = "autoTrashLocalCopies"

    private(set) var entries: [Entry] = []

    /// Whether local copies go to the Trash `keepDays` days after a confirmed upload. A visible switch in the app.
    var autoTrash: Bool {
        didSet { UserDefaults.standard.set(autoTrash, forKey: Self.autoTrashKey) }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var sweeping = false

    init() {
        autoTrash = UserDefaults.standard.object(forKey: Self.autoTrashKey) as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    // MARK: - Entries

    func add(_ entry: Entry) {
        entries.removeAll { $0.videoID == entry.videoID }
        entries.insert(entry, at: 0)
        save()
    }

    func remove(videoID: String) {
        entries.removeAll { $0.videoID == videoID }
        save()
    }

    func entry(forRecording url: URL) -> Entry? {
        entries.first { $0.recordingPath == url.path }
    }

    /// When this entry's local file is due to go to the Trash.
    func trashDate(for entry: Entry) -> Date {
        entry.uploadedAt.addingTimeInterval(Double(Self.keepDays) * 86_400)
    }

    private func save() {
        // Keep the list from growing forever. Dropping an old entry only means its local file is never auto-moved.
        if entries.count > 100 {
            entries = Array(entries.prefix(100))
        }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
    }

    private func update(_ videoID: String, _ change: (inout Entry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.videoID == videoID }) else { return }
        change(&entries[index])
        save()
    }

    // MARK: - Local clean-up

    /// Checks now, then once an hour while the app is open. If the app was closed, due files are handled at next launch.
    func startCleanup(api: @escaping @MainActor () -> SharingAPI?) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sweep(api: api()) }
        }
        Task { await sweep(api: api()) }
    }

    /// Moves due local copies to the Trash, following the safety rules above.
    func sweep(api: SharingAPI?, now: Date = .now) async {
        guard autoTrash, !sweeping, let api = api?.quick else { return }
        sweeping = true
        defer { sweeping = false }
        for entry in entries where entry.local == .kept && trashDate(for: entry) <= now {
            let url = URL(fileURLWithPath: entry.recordingPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                update(entry.videoID) { $0.local = .gone }
                continue
            }
            guard Self.unchanged(url, since: entry) else {
                update(entry.videoID) { $0.local = .changed }
                continue
            }
            // Ask the server again. Anything other than "still there and complete" keeps the file.
            guard let online = try? await api.uploadState(of: entry.videoID),
                  online.status == "ready", online.sizeBytes == entry.onlineBytes else { continue }
            guard autoTrash else { return }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                update(entry.videoID) { $0.local = .trashed }
            } catch {
                // Leave it for the next check.
            }
        }
    }

    /// Moves one entry's local file to the Trash now (used by "delete online and on this Mac").
    func trashLocal(videoID: String) -> Bool {
        guard let entry = entries.first(where: { $0.videoID == videoID }) else { return false }
        let url = URL(fileURLWithPath: entry.recordingPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        return (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
    }

    nonisolated static func fileFacts(_ url: URL) -> (bytes: Int, modified: Date?) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return (values?.fileSize ?? 0, values?.contentModificationDate)
    }

    private static func unchanged(_ url: URL, since entry: Entry) -> Bool {
        let facts = fileFacts(url)
        guard facts.bytes == entry.localBytes else { return false }
        if let then = entry.localModified, let now = facts.modified { return abs(now.timeIntervalSince(then)) < 1 }
        return true
    }
}
