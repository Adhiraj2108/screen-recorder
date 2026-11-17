import AVFoundation

/// Makes the copy of a recording that gets uploaded. The saved original is never touched.
///
/// The copy has its index (the "moov" box) at the front, so a viewer's player can start playing right away instead of
/// first reaching for the end of the file. Video and audio are copied as they are, without re-encoding.
enum UploadCopy {
    enum CopyError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            if case let .failed(reason) = self { return "Couldn’t prepare the recording for upload. \(reason)" }
            return nil
        }
    }

    static func make(from original: URL, to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let asset = AVURLAsset(url: original)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw CopyError.failed("This Mac can’t copy the file.")
        }
        session.shouldOptimizeForNetworkUse = true
        do {
            try await session.export(to: destination, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw CopyError.failed(error.localizedDescription)
        }
    }
}
