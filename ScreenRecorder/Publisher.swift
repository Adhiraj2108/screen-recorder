import AppKit
import Observation

/// Sends a finished recording to the owner's hosting server and returns a share link.
///
/// Uploading is always the owner's explicit action. The saved recording is never changed or removed: a separate copy
/// (with its index at the front, so it starts playing quickly) is what gets uploaded. If the connection drops or the
/// app is closed, the unfinished upload is remembered and carries on from the last part that arrived.
@MainActor
@Observable
final class Publisher {
    enum State: Equatable {
        case idle
        case preparing
        case uploading(Double)
        case finishing
        case done(URL)
        case failed(String)
    }

    /// An upload that started but hasn't finished. Saved so it survives a restart.
    private struct Pending: Codable {
        var recordingPath: String
        var copyPath: String
        var videoID: String?
        var title: String
    }

    static let defaultServer = "https://recorder-web.rae-social-agency.workers.dev"
    private static let pendingKey = "pendingUpload"
    private static let serverKey = "sharingServerURL"

    private(set) var state = State.idle
    private(set) var hasKey = OwnerKeychain.read() != nil
    /// The recording this panel is about to upload, or the unfinished one from before.
    private(set) var recordingURL: URL?
    var title = ""
    /// True when an earlier upload of this recording stopped part way.
    private(set) var hasUnfinishedUpload = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pending: Pending?

    var serverURL: URL {
        let text = UserDefaults.standard.string(forKey: Self.serverKey) ?? Self.defaultServer
        return URL(string: text) ?? URL(string: Self.defaultServer)!
    }

    var isBusy: Bool {
        switch state {
        case .preparing, .uploading, .finishing: true
        default: false
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.pendingKey),
           let saved = try? JSONDecoder().decode(Pending.self, from: data),
           FileManager.default.fileExists(atPath: saved.recordingPath) {
            pending = saved
            recordingURL = URL(fileURLWithPath: saved.recordingPath)
            title = saved.title
            hasUnfinishedUpload = true
        }
    }

    /// Called when a new recording is saved, so the panel offers to upload it.
    func offer(_ url: URL) {
        guard !isBusy else { return }
        if let pending, pending.recordingPath == url.path { return }
        recordingURL = url
        state = .idle
        hasUnfinishedUpload = false
        title = Self.defaultTitle(for: url)
    }

    func saveKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24 else {
            state = .failed("That doesn’t look like the owner key. It is a long string of letters and numbers.")
            return
        }
        // Check it with the server before keeping it, so a typo is caught now and not at upload time.
        do {
            try await SharingAPI(baseURL: serverURL, key: trimmed).verify()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        guard OwnerKeychain.save(trimmed) else {
            state = .failed("The key couldn’t be saved to the Keychain.")
            return
        }
        hasKey = true
        state = .idle
    }

    func forgetKey() {
        OwnerKeychain.delete()
        hasKey = false
    }

    func upload() {
        guard !isBusy, let recordingURL, let key = OwnerKeychain.read() else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            state = .failed("Give the video a title first.")
            return
        }
        let api = SharingAPI(baseURL: serverURL, key: key)
        var job = pending.flatMap { $0.recordingPath == recordingURL.path ? $0 : nil }
            ?? Pending(recordingPath: recordingURL.path, copyPath: Self.copyURL(for: recordingURL).path, videoID: nil, title: cleanTitle)
        job.title = cleanTitle
        let startingJob = job
        state = .preparing
        task = Task { [weak self] in
            do {
                let link = try await Self.run(job: startingJob, api: api, onChange: { updated in
                    self?.remember(updated)
                }, onProgress: { fraction in
                    self?.state = .uploading(fraction)
                }, onFinishing: {
                    self?.state = .finishing
                })
                self?.finished(link: link, job: startingJob)
            } catch is CancellationError {
                self?.state = .failed("Paused. Press Resume to carry on where it stopped.")
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Gives up on an unfinished upload and discards the partly sent file on the server.
    func discardUnfinished() {
        guard let job = pending, let key = OwnerKeychain.read() else { return clearPending() }
        let api = SharingAPI(baseURL: serverURL, key: key)
        Task {
            if let id = job.videoID { try? await api.deleteVideo(videoID: id) }
        }
        clearPending()
        state = .idle
    }

    func copyLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    // MARK: - Work

    private nonisolated static func run(
        job startingJob: Pending,
        api: SharingAPI,
        onChange: @MainActor @Sendable (Pending) -> Void,
        onProgress: @MainActor @Sendable (Double) -> Void,
        onFinishing: @MainActor @Sendable () -> Void
    ) async throws -> URL {
        var job = startingJob
        let original = URL(fileURLWithPath: job.recordingPath)
        let copy = URL(fileURLWithPath: job.copyPath)

        // 1. The upload copy, kept until the upload finishes so a resumed upload sends identical bytes.
        if !FileManager.default.fileExists(atPath: copy.path) {
            try await UploadCopy.make(from: original, to: copy)
        }
        let size = (try FileManager.default.attributesOfItem(atPath: copy.path)[.size] as? Int) ?? 0
        guard size > 0 else { throw SharingAPI.APIError(message: "The recording is empty.", status: nil) }

        // 2. A video record on the server, created once and remembered, so retries never make duplicates.
        let videoID: String
        if let existing = job.videoID {
            videoID = existing
        } else {
            videoID = try await api.createVideo(title: job.title)
            job.videoID = videoID
            await onChange(job)
        }

        // 3. Upload the parts that haven't arrived yet.
        if try await api.status(of: videoID) != "ready" {
            let info = try await api.startUpload(videoID: videoID, size: size)
            let have = Set(info.parts.map(\.partNumber))
            let total = (size + info.partSize - 1) / info.partSize
            let handle = try FileHandle(forReadingFrom: copy)
            defer { try? handle.close() }
            for number in 1...total {
                try Task.checkCancellation()
                await onProgress(Double(number - 1) / Double(total))
                if have.contains(number) { continue }
                try handle.seek(toOffset: UInt64((number - 1) * info.partSize))
                let chunk = try handle.read(upToCount: info.partSize) ?? Data()
                try await api.uploadPart(videoID: videoID, number: number, data: chunk)
            }
            await onFinishing()
            try await api.completeUpload(videoID: videoID)
        }
        await onFinishing()
        return try await api.createShare(videoID: videoID)
    }

    private func remember(_ job: Pending) {
        pending = job
        hasUnfinishedUpload = true
        if let data = try? JSONEncoder().encode(job) { UserDefaults.standard.set(data, forKey: Self.pendingKey) }
    }

    private func finished(link: URL, job: Pending) {
        try? FileManager.default.removeItem(atPath: job.copyPath)
        clearPending()
        copyLink(link)
        state = .done(link)
    }

    private func clearPending() {
        if let pending { try? FileManager.default.removeItem(atPath: pending.copyPath) }
        pending = nil
        hasUnfinishedUpload = false
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    }

    private static func copyURL(for recording: URL) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appending(path: "Screen Recorder Uploads", directoryHint: .isDirectory)
            .appending(path: "\(UUID().uuidString).mp4", directoryHint: .notDirectory)
    }

    private static func defaultTitle(for url: URL) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
        return "Walkthrough \(formatter.string(from: date))"
    }
}
