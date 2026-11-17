import Foundation

/// Talks to the owner's hosting server (the recorder-web Worker): creates a video, uploads the file in parts,
/// and makes a share link. Every call carries the owner key; the server refuses anything without it.
struct SharingAPI: Sendable {
    struct APIError: LocalizedError {
        let message: String
        let status: Int?
        var errorDescription: String? { message }
        /// A refusal that retrying won't change (wrong key, bad file), as opposed to a dropped connection.
        var isFinal: Bool { status.map { $0 < 500 && $0 != 429 } ?? false }
    }

    struct UploadInfo: Decodable {
        let partSize: Int
        let parts: [Part]
        struct Part: Decodable { let partNumber: Int; let sizeBytes: Int }
    }

    let baseURL: URL
    let key: String
    private let session: URLSession

    init(baseURL: URL, key: String) {
        self.baseURL = baseURL
        self.key = key
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    private func request(_ method: String, _ path: String, json: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError(message: "The server address isn’t valid.", status: nil) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return request
    }

    private func send(_ request: URLRequest, body: Data? = nil) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            if let body {
                (data, response) = try await session.upload(for: request, from: body)
            } else {
                (data, response) = try await session.data(for: request)
            }
        } catch let error as URLError {
            throw APIError(message: "Couldn’t reach the server. Check your internet connection. (\(error.localizedDescription))", status: nil)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            let fallback = status == 401 ? "The owner key wasn’t accepted." : "The server returned an error (\(status))."
            throw APIError(message: message ?? fallback, status: status)
        }
        return data
    }

    private func object(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Checks the key and address without changing anything.
    func verify() async throws {
        _ = try await send(request("GET", "/api/videos"))
    }

    func createVideo(title: String) async throws -> String {
        let data = try await send(request("POST", "/api/videos", json: ["title": title]))
        guard let id = object(data)["id"] as? String else { throw APIError(message: "The server’s answer wasn’t understood.", status: nil) }
        return id
    }

    /// Where the video stands: `ready` when the file is already uploaded.
    func status(of videoID: String) async throws -> String {
        let data = try await send(request("GET", "/api/videos/\(videoID)/upload"))
        return object(data)["status"] as? String ?? "draft"
    }

    /// Starts the upload, or picks up the one in progress for a file of the same size, listing the parts already there.
    func startUpload(videoID: String, size: Int) async throws -> UploadInfo {
        let data = try await send(request("POST", "/api/videos/\(videoID)/upload", json: ["size": size]))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(UploadInfo.self, from: data)
    }

    /// Sends one part, trying again a few times if the connection drops or the server is busy.
    func uploadPart(videoID: String, number: Int, data: Data) async throws {
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                var put = try request("PUT", "/api/videos/\(videoID)/upload/parts/\(number)")
                put.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                _ = try await send(put, body: data)
                return
            } catch let error as APIError where error.isFinal {
                throw error
            } catch {
                lastError = error
                if Task.isCancelled { throw CancellationError() }
                try await Task.sleep(for: .seconds(pow(2, Double(attempt))))
            }
        }
        throw lastError ?? APIError(message: "The upload kept failing.", status: nil)
    }

    func completeUpload(videoID: String) async throws {
        _ = try await send(request("POST", "/api/videos/\(videoID)/upload/complete"))
    }

    /// Deletes a video and its stored file, used to discard an upload the owner gave up on.
    func deleteVideo(videoID: String) async throws {
        _ = try await send(request("DELETE", "/api/videos/\(videoID)"))
    }

    /// Makes a new share link and returns its address.
    func createShare(videoID: String) async throws -> URL {
        let data = try await send(request("POST", "/api/videos/\(videoID)/shares", json: [:]))
        guard let text = object(data)["url"] as? String, let url = URL(string: text) else {
            throw APIError(message: "The server’s answer wasn’t understood.", status: nil)
        }
        return url
    }
}
