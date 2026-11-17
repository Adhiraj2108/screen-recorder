import SwiftUI

/// The "Share" area under a saved recording: connect once with the owner key, then upload and copy the link.
struct SharingSection: View {
    @Bindable var publisher: Publisher
    /// False while a recording is in progress or being saved, so uploading never competes with capture.
    var canOffer: Bool
    @State private var keyText = ""
    @State private var confirmDiscard = false

    var body: some View {
        if canOffer, publisher.recordingURL != nil {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Share")
                    .font(.system(size: 13, weight: .semibold))
                if !publisher.hasKey {
                    connect
                } else if case let .done(link) = publisher.state {
                    done(link)
                } else {
                    upload
                }
                if case let .failed(message) = publisher.state {
                    Text(message)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
                }
            }
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
            Button("Disconnect") { publisher.forgetKey() }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .disabled(publisher.isBusy)
        }
    }

    private func done(_ link: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Uploaded. The link is copied.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
            Text(link.absoluteString)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Copy link") { publisher.copyLink(link) }
                Button("Open link") { NSWorkspace.shared.open(link) }
            }
        }
    }
}
