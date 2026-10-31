import Foundation

public enum NarrationError: Error, Equatable, Sendable {
    /// The plan has no premium voice (HTTP 402).
    case needsPlan
    /// The server has no voice configured (HTTP 503).
    case unavailable
    /// Voicing did not finish in time.
    case timedOut
    case failed(String)
}

/// Gets the premium narration of a part onto the device: asks the server (waiting while it is voiced) and
/// keeps the downloaded file, so listening again works at once and without a connection.
public struct NarrationFetcher: Sendable {
    private let client: APIClient
    private let directory: URL
    private let pollInterval: Duration
    private let maxWait: Duration

    public init(client: APIClient, directory: URL, pollInterval: Duration = .seconds(5), maxWait: Duration = .seconds(600)) {
        self.client = client
        self.directory = directory
        self.pollInterval = pollInterval
        self.maxWait = maxWait
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("narration", isDirectory: true)
    }

    /// `known` is the narration the story already carries, if any. Returns a local file.
    public func file(storyId: String, part: Int, known: MediaAsset?) async throws -> URL {
        if let known, let cached = cachedFile(for: known) { return cached }
        let asset: MediaAsset
        if let known { asset = known } else { asset = try await waitForAsset(storyId: storyId, part: part) }
        if let cached = cachedFile(for: asset) { return cached }
        return try await download(asset)
    }

    private func waitForAsset(storyId: String, part: Int) async throws -> MediaAsset {
        let clock = ContinuousClock()
        let deadline = clock.now + maxWait

        while clock.now < deadline {
            do {
                if case .ready(let asset) = try await client.narration(storyId: storyId, part: part) { return asset }
            } catch APIError.paywall {
                throw NarrationError.needsPlan
            } catch let APIError.server(503, _, _) {
                throw NarrationError.unavailable
            } catch let APIError.server(_, _, message) {
                throw NarrationError.failed(message)
            } catch APIError.transport(let message) {
                throw NarrationError.failed(message)
            }
            try await Task.sleep(for: pollInterval)
        }

        throw NarrationError.timedOut
    }

    private func localURL(for asset: MediaAsset) -> URL {
        let ext = URL(fileURLWithPath: asset.url).pathExtension
        return directory.appendingPathComponent("\(asset.id).\(ext.isEmpty ? "mp3" : ext)")
    }

    private func cachedFile(for asset: MediaAsset) -> URL? {
        let url = localURL(for: asset)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func download(_ asset: MediaAsset) async throws -> URL {
        let data: Data
        do {
            data = try await client.download(asset.url)
        } catch {
            throw NarrationError.failed("Не удалось загрузить озвучку.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = localURL(for: asset)
        try data.write(to: url, options: .atomic)
        return url
    }
}
