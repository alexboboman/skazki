import Foundation
import SkazochnikCore
@testable import SkazochnikUI

/// URLProtocol stub with its own handler, so suites that run in parallel do not share state.
final class RouteStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: (URLRequest) -> Result<(Int, Data), Error>] = [:]
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "route.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.url?.query.map { "\(request.httpMethod ?? "GET") \(request.url!.path)?\($0)" } ?? "\(request.httpMethod ?? "GET") \(request.url!.path)"
        Self.lock.lock()
        let handler = Self.routes[key] ?? Self.routes["\(request.httpMethod ?? "GET") \(request.url!.path)"]
        Self.lock.unlock()
        switch handler?(request) ?? .failure(URLError(.notConnectedToInternet)) {
        case .success(let (status, data)):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func jsonArray(_ items: [String]) -> String {
    "[" + items.map { "\"\($0)\"" }.joined(separator: ",") + "]"
}

import Testing

/// Suites that share `RouteStub.routes` live under this one serialized parent, so they never run in parallel.
@Suite(.serialized) enum StubbedNetwork {}

enum Sample {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func profile(_ id: String, _ name: String, age: Int, worlds: [String] = ["forest"], interests: [String] = ["Феи", "Море"]) -> ChildProfile {
        let json = """
        {"id":"\(id)","name":"\(name)","age":\(age),"gender":"girl",
         "appearance":{"skin":1,"hair":\(age % 6),"hairStyle":"long","outfit":\(age % 5)},
         "interests":\(jsonArray(interests)),"worlds":\(jsonArray(worlds)),
         "language":"Русский","createdAt":"2026-10-01T10:00:00Z"}
        """
        return try! decoder.decode(ChildProfile.self, from: Data(json.utf8))
    }

    static func story(
        _ id: String, _ title: String, hero: [String], world: String = "forest", minutes: Int = 5,
        favorite: Bool = false, progress: Double = 0, createdAt: String = "2026-10-30T18:00:00Z"
    ) -> StorySummary {
        let json = """
        {"id":"\(id)","title":"\(title)","format":"quick_story","world":"\(world)",
         "heroIds":\(jsonArray(hero)),"readingMinutes":\(minutes),"favorite":\(favorite),
         "readProgress":\(progress),"createdAt":"\(createdAt)"}
        """
        return try! decoder.decode(StorySummary.self, from: Data(json.utf8))
    }

    static let anya = profile("k1", "Аня", age: 5)
    static let misha = profile("k2", "Миша", age: 3, worlds: ["space"], interests: ["Машинки", "Космос", "Динозавры"])

    static let stories = [
        story("s1", "Лиса, которая берегла звёзды", hero: ["k1"], world: "forest", minutes: 8, favorite: true, progress: 0.62, createdAt: "2026-10-30T18:00:00Z"),
        story("s2", "Кит и потерянная песня", hero: ["k1"], world: "ocean", minutes: 10, createdAt: "2026-10-29T18:00:00Z"),
        story("s3", "Сонная ракета", hero: ["k2"], world: "space", minutes: 5, favorite: true, createdAt: "2026-10-28T18:00:00Z"),
        story("s4", "Рыцарь тёплого пледа", hero: ["k1", "k2"], world: "castle", minutes: 12, createdAt: "2026-10-24T18:00:00Z"),
        story("s5", "Облако, которое не умело плакать", hero: ["k2"], world: "clouds", minutes: 7, createdAt: "2026-10-20T18:00:00Z"),
        story("s6", "Тихая тропа сквозь джунгли", hero: ["k1"], world: "jungle", minutes: 9, favorite: true, createdAt: "2026-09-12T18:00:00Z"),
    ]

    /// A client whose network is a stub; `cache` is pre-filled like after an earlier launch.
    @MainActor
    static func appModel(
        profiles: [ChildProfile] = [anya, misha],
        stories: [StorySummary] = Sample.stories,
        defaults: UserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    ) -> AppModel {
        let cache = MemoryLibraryCache()
        cache.save(profiles, key: "profiles")
        cache.save(stories, key: "stories")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RouteStub.self]
        let client = APIClient(
            baseURL: URL(string: "http://route.test")!,
            store: MemorySessionStore(token: "t"),
            session: URLSession(configuration: configuration)
        )
        return AppModel(client: client, repository: LibraryRepository(client: client, cache: cache), defaults: defaults)
    }
}
