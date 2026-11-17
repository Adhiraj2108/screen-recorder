import AppKit
import Observation

/// Sends a finished recording to the owner's hosting server and returns a share link.
///
/// With "Upload automatically" on (the default), a finished recording starts uploading by itself; otherwise the owner
/// presses Upload. The saved recording is never changed by uploading: a separate copy (with its index at the front, so
/// it starts playing quickly) is what gets uploaded. If the connection drops or the app is closed, the unfinished
/// upload is remembered and carries on from the last part that arrived. Once the server confirms it holds the whole
/// file, the link is made and copied, and the upload is added to the `UploadLibrary` (which may later move the local
/// file to the Trash, see there for the safety rules).
@MainActor
@Observable
final class Publisher {
    enum State: Equatable {
        case idle
        case preparing
        case uploading(Double)
        case finishing
        case done(URL, videoID: String)
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
    private static let autoUploadKey = "autoUploadRecordings"

    private(set) var state = State.idle
    private(set) var hasKey = OwnerKeychain.read() != nil
    /// The recording this panel is about to upload, or the unfinished one from before.
    private(set) var recordingURL: URL?
    var title = ""
    /// True when an earlier upload of this recording stopped part way.
    private(set) var hasUnfinishedUpload = false
    /// The result of the last delete, shown in the Share area.
    var notice: String?
    /// Recordings that finished while another upload was running; they upload one after another.
    private(set) var queued: [URL] = []

    let library = UploadLibrary()

    /// Start uploading as soon as a recording is saved. A visible switch in the app.
    var autoUpload: Bool {
        didSet { UserDefaults.standard.set(autoUpload, forKey: Self.autoUploadKey) }
    }

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

    var api: SharingAPI? {
        OwnerKeychain.read().map { SharingAPI(baseURL: serverURL, key: $0) }
    }

    init() {
        autoUpload = UserDefaults.standard.object(forKey: Self.autoUploadKey) as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: Self.pendingKey),
           let saved = try? JSONDecoder().decode(Pending.self, from: data),
           FileManager.default.fileExists(atPath: saved.recordingPath) {
            pending = saved
            recordingURL = URL(fileURLWithPath: saved.recordingPath)
            title = saved.title
            hasUnfinishedUpload = true
        }
        library.startCleanup { [weak self] in self?.api }
        // An upload that was cut off when the app last closed carries on by itself.
        if hasUnfinishedUpload, autoUpload, hasKey { upload() }
    }

    /// Called when a new recording is saved: shows it in the Share area and, with auto-upload on, starts uploading.
    func offer(_ url: URL) {
        if isBusy || (hasUnfinishedUpload && pending?.recordingPath != url.path) {
            // Something else is uploading (or waiting to be resumed). Queue this one so it isn't forgotten.
            if autoUpload, !queued.contains(url) { queued.append(url) }
            return
        }
        if let pending, pending.recordingPath == url.path { return }
        recordingURL = url
        state = .idle
        hasUnfinishedUpload = false
        title = Self.defaultTitle(for: url)
        if autoUpload, hasKey { upload() }
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
        if autoUpload, let recordingURL, library.entry(forRecording: recordingURL) == nil { upload() }
    }

    func forgetKey() {
        OwnerKeychain.delete()
        hasKey = false
    }

    func upload() {
        notice = nil
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
                let (link, videoID, onlineBytes) = try await Self.run(job: startingJob, api: api, onChange: { updated in
                    self?.remember(updated)
                }, onProgress: { fraction in
                    self?.state = .uploading(fraction)
                }, onFinishing: {
                    self?.state = .finishing
                })
                self?.finished(link: link, videoID: videoID, onlineBytes: onlineBytes, job: startingJob)
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
        startNextQueued()
    }

    /// Deletes an uploaded video online (its file, links and record). With `alsoLocal`, the recording on this Mac goes
    /// to the Trash too, where it can still be put back.
    func deleteUploaded(videoID: String, alsoLocal: Bool) async {
        guard let api = api?.quick else {
            notice = "Connect with the owner key first."
            return
        }
        do {
            try await api.deleteVideo(videoID: videoID)
        } catch {
            notice = "The video couldn’t be deleted online, so nothing was removed. \(error.localizedDescription)"
            return
        }
        var note = "Deleted online. The link no longer works."
        if alsoLocal {
            note = library.trashLocal(videoID: videoID)
                ? "Deleted online, and the recording was moved to the Trash."
                : "Deleted online. The recording on this Mac couldn’t be moved to the Trash, so it’s still in Movies."
        } else {
            note += " The recording is still in Movies."
        }
        let recording = library.entries.first { $0.videoID == videoID }?.recordingPath
        library.remove(videoID: videoID)
        if case let .done(_, shown) = state, shown == videoID {
            state = .idle
            if alsoLocal, recordingURL?.path == recording { recordingURL = nil }
        }
        notice = note
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
    ) async throws -> (URL, String, Int) {
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

        // 4. Confirm the server holds the whole file before treating the upload as done. Only confirmed uploads are
        //    ever eligible for the local clean-up.
        let online = try await api.uploadState(of: videoID)
        guard online.status == "ready", online.sizeBytes == size else {
            throw SharingAPI.APIError(
                message: "The upload couldn’t be confirmed (the server has \(online.sizeBytes ?? 0) of \(size) bytes). Press Resume to try again.",
                status: nil)
        }
        return (try await api.createShare(videoID: videoID), videoID, size)
    }

    private func remember(_ job: Pending) {
        pending = job
        hasUnfinishedUpload = true
        if let data = try? JSONEncoder().encode(job) { UserDefaults.standard.set(data, forKey: Self.pendingKey) }
    }

    private func finished(link: URL, videoID: String, onlineBytes: Int, job: Pending) {
        try? FileManager.default.removeItem(atPath: job.copyPath)
        clearPending()
        let local = URL(fileURLWithPath: job.recordingPath)
        let facts = UploadLibrary.fileFacts(local)
        library.add(.init(
            videoID: videoID, title: job.title, recordingPath: job.recordingPath, shareURL: link, uploadedAt: .now,
            onlineBytes: onlineBytes, localBytes: facts.bytes, localModified: facts.modified))
        copyLink(link)
        state = .done(link, videoID: videoID)
        startNextQueued()
    }

    /// Uploads the next recording that finished while this one was uploading. The panel moves on to it.
    private func startNextQueued() {
        guard autoUpload, hasKey else { return }
        while let next = queued.first {
            queued.removeFirst()
            guard FileManager.default.fileExists(atPath: next.path), library.entry(forRecording: next) == nil else { continue }
            recordingURL = next
            title = Self.defaultTitle(for: next)
            hasUnfinishedUpload = false
            upload()
            return
        }
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
