import SwiftUI

/// The "Share" area under a saved recording: connect once with the owner key, then upload (automatically or by
/// button) and copy the link. Also holds the auto-upload and auto-Trash switches, and recent uploads with Delete.
struct SharingSection: View {
    @Bindable var publisher: Publisher
    /// False while a recording is in progress or being saved, so uploading never competes with capture.
    var canOffer: Bool
    @State private var keyText = ""
    @State private var confirmDiscard = false
    @State private var deleting: UploadLibrary.Entry?

    private var library: UploadLibrary { publisher.library }

    var body: some View {
        if canOffer, publisher.recordingURL != nil || !library.entries.isEmpty || publisher.notice != nil {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Share")
                    .font(.system(size: 13, weight: .semibold))
                if !publisher.hasKey {
                    connect
                } else {
                    settings
                    if case let .done(link, videoID) = publisher.state {
                        done(link, videoID: videoID)
                    } else if publisher.recordingURL != nil {
                        upload
                    }
                }
                if let notice = publisher.notice {
                    Text(notice)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)
                }
                if publisher.hasKey { recent }
                if case let .failed(message) = publisher.state {
                    Text(message)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
                }
            }
            .confirmationDialog(
                "Delete “\(deleting?.title ?? "this video")” online?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                presenting: deleting
            ) { entry in
                Button("Delete online only", role: .destructive) {
                    Task { await publisher.deleteUploaded(videoID: entry.videoID, alsoLocal: false) }
                }
                if entry.local == .kept || entry.local == .changed {
                    Button("Delete online and move recording to Trash", role: .destructive) {
                        Task { await publisher.deleteUploaded(videoID: entry.videoID, alsoLocal: true) }
                    }
                }
            } message: { _ in
                Text("The online video, its links and its title are erased and can’t be brought back. Anyone with the link sees “This link isn’t available”. A recording moved to the Trash can still be put back from the Trash.")
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Upload automatically when a recording finishes", isOn: $publisher.autoUpload)
            Toggle("Move recordings to the Trash \(UploadLibrary.keepDays) days after a confirmed upload",
                   isOn: Bindable(library).autoTrash)
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .onChange(of: library.autoTrash) {
            Task { await library.sweep(api: publisher.api) }
        }
    }

    /// The last few confirmed uploads, with where the local copy stands and a Delete button.
    @ViewBuilder
    private var recent: some View {
        let shown = library.entries.filter { entry in
            if case let .done(_, current) = publisher.state { return entry.videoID != current }
            return true
        }.prefix(3)
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent uploads")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(shown)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).lineLimit(1).truncationMode(.middle)
                            Text(localStatus(entry))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Copy link") { publisher.copyLink(entry.shareURL) }
                        Button("Delete…") { deleting = entry }
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(.top, 4)
        }
    }

    private func localStatus(_ entry: UploadLibrary.Entry) -> String {
        switch entry.local {
        case .trashed: return "Online. The recording on this Mac was moved to the Trash."
        case .gone: return "Online. The recording is no longer on this Mac."
        case .changed: return "Online. Kept on this Mac because the file changed after upload."
        case .kept:
            guard library.autoTrash else { return "Online. Kept on this Mac." }
            let due = library.trashDate(for: entry)
            if due <= .now { return "Online. Moves to the Trash once the server confirms it still has it." }
            return "Online. Moves to the Trash on \(due.formatted(.dateTime.day().month().hour().minute()))."
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To get a share link, connect this app to your hosting page once with your owner key.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField("Owner key", text: $keyText)
                    .textFieldStyle(.roundedBorder)
                Button("Connect") {
                    let key = keyText
                    Task {
                        await publisher.saveKey(key)
                        if publisher.hasKey { keyText = "" }
                    }
                }
                .disabled(keyText.isEmpty)
            }
        }
    }

    private var upload: some View {
        VStack(alignment: .leading, spacing: 8) {
            if publisher.hasUnfinishedUpload, !publisher.isBusy {
                Text("An earlier upload of this recording didn’t finish.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            TextField("Video title", text: $publisher.title)
                .textFieldStyle(.roundedBorder)
                .disabled(publisher.isBusy)
            HStack(spacing: 10) {
                switch publisher.state {
                case .preparing:
                    ProgressView().controlSize(.small)
                    Text("Preparing the file…").foregroundStyle(.secondary)
                case let .uploading(fraction):
                    ProgressView(value: fraction).frame(maxWidth: 160)
                    Text("Uploading \(Int(fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
                case .finishing:
                    ProgressView().controlSize(.small)
                    Text("Finishing…").foregroundStyle(.secondary)
                default:
                    Button(publisher.hasUnfinishedUpload ? "Resume upload" : "Upload and get link") { publisher.upload() }
                    if publisher.hasUnfinishedUpload {
                        Button("Discard") { confirmDiscard = true }
                            .confirmationDialog("Discard the unfinished upload?", isPresented: $confirmDiscard) {
                                Button("Discard", role: .destructive) { publisher.discardUnfinished() }
                            } message: {
                                Text("Your saved recording stays in Movies. Only the partly uploaded copy online is removed.")
                            }
                    }
                }
                if publisher.isBusy {
                    Spacer()
                    Button("Pause") { publisher.cancel() }
                }
            }
            .font(.system(size: 12, weight: .medium))
            if !publisher.queued.isEmpty {
                Text(publisher.queued.count == 1
                     ? "1 more recording uploads after this one."
                     : "\(publisher.queued.count) more recordings upload after this one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button("Disconnect") { publisher.forgetKey() }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .disabled(publisher.isBusy)
        }
    }

    private func done(_ link: URL, videoID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Uploaded and confirmed. The link is copied.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
            if let entry = library.entries.first(where: { $0.videoID == videoID }) {
                Text(localStatus(entry))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(link.absoluteString)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Copy link") { publisher.copyLink(link) }
                Button("Open link") { NSWorkspace.shared.open(link) }
                Spacer()
                Button("Delete…") { deleting = library.entries.first { $0.videoID == videoID } }
            }
        }
    }
}
