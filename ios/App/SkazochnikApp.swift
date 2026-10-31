import SwiftUI
import SkazochnikCore
import SkazochnikUI

@main
struct SkazochnikApp: App {
    private let client = APIClient(baseURL: AppConfig.apiBaseURL, store: KeychainSessionStore())

    init() {
        // Illustrations are served as immutable files; a big disk cache lets saved stories show their
        // pictures offline (AsyncImage reads through URLCache.shared).
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView(client: client)
        }
    }
}

enum AppConfig {
    /// `API_BASE_URL` in Info.plist (see project.yml); the iOS Simulator reaches the Mac's API at localhost.
    static let apiBaseURL: URL = {
        let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        return URL(string: value ?? "http://localhost:3000") ?? URL(string: "http://localhost:3000")!
    }()
}
