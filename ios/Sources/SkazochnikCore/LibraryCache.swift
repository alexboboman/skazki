import Foundation

/// Keeps decoded API data on disk so the library opens offline (PRD: saved stories are readable without internet).
public protocol LibraryCache: Sendable {
    func load<T: Decodable>(_ type: T.Type, key: String) -> T?
    func save<T: Encodable>(_ value: T, key: String)
    func remove(key: String)
}

public final class MemoryLibraryCache: LibraryCache, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    public init() {}

    public func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        lock.lock(); defer { lock.unlock() }
        return storage[key].flatMap { try? APIClient.decoder.decode(type, from: $0) }
    }

    public func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? Self.encoder.encode(value) else { return }
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }

    public func remove(key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

/// One JSON file per key under `directory` (Application Support by default), excluded from iCloud backup.
public final class FileLibraryCache: LibraryCache, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Library", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = base
        try? mutable.setResourceValues(values)
    }

    public func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? APIClient.decoder.decode(type, from: data)
    }

    public func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? MemoryLibraryCache.encoder.encode(value) else { return }
        lock.lock(); defer { lock.unlock() }
        try? data.write(to: url(for: key), options: .atomic)
    }

    public func remove(key: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url(for: key))
    }

    private func url(for key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
        return directory.appendingPathComponent("\(safe).json")
    }
}
