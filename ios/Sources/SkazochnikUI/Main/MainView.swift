import SwiftUI
import SkazochnikCore

/// The app after onboarding: three tabs, the create button and full-screen overlays for reading,
/// creating a story and adding a child.
public struct MainView: View {
    private enum Overlay: Equatable {
        case reading(storyId: String, ReadableStory, HeroInfo)
        case create(ChildProfile)
        case addChild
    }

    @StateObject private var app: AppModel
    @State private var tab: MainTab = .home
    @State private var overlay: Overlay?
    @State private var notice: String?

    public init(client: APIClient, cache: LibraryCache = FileLibraryCache()) {
        _app = StateObject(wrappedValue: AppModel(client: client, repository: LibraryRepository(client: client, cache: cache)))
    }

    public var body: some View {
        ZStack {
            NightBackground(starCount: 34, seed: 41)

            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .home:
                        HomeView(app: app, onOpen: open, onCreate: startCreate, onAllStories: { tab = .library })
                    case .library:
                        LibraryView(app: app, onOpen: open) { story in Task { await app.toggleFavorite(story) } }
                    case .kids:
                        KidsView(app: app) { overlay = .addChild }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                MainTabBar(tab: $tab, onCreate: startCreate)
            }

            if let notice {
                Text(notice)
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.card2, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderStrong))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .transition(.opacity)
                    .task { try? await Task.sleep(for: .seconds(3)); self.notice = nil }
            }

            overlayView
        }
        .animation(.easeOut(duration: 0.3), value: overlay)
        .animation(.easeOut(duration: 0.2), value: notice)
        .preferredColorScheme(.dark)
        .task { await app.refresh() }
    }

    @ViewBuilder private var overlayView: some View {
        switch overlay {
        case .reading(let id, let story, let hero):
            ReadingView(
                story: story,
                hero: hero,
                mediaURL: app.client.mediaURL,
                onBack: { overlay = nil },
                onReachedEnd: { Task { await app.markRead(id: id) } },
                favorite: app.stories.first { $0.id == id }?.favorite,
                onToggleFavorite: {
                    if let summary = app.stories.first(where: { $0.id == id }) { Task { await app.toggleFavorite(summary) } }
                }
            )
            .background(Theme.bg0.ignoresSafeArea())
            .transition(.move(edge: .trailing))
        case .create(let profile):
            CreateFlow(app: app, profile: profile) { overlay = nil }
                .background(Theme.bg0.ignoresSafeArea())
                .transition(.move(edge: .bottom))
        case .addChild:
            OnboardingFlow(
                client: app.client,
                startAtProfile: true,
                onFinished: { profile in
                    app.added(profile)
                    overlay = nil
                    tab = .kids
                },
                onCancel: { overlay = nil }
            )
            .background(Theme.bg0.ignoresSafeArea())
            .transition(.move(edge: .bottom))
        case nil:
            EmptyView()
        }
    }

    private func startCreate() {
        guard let profile = app.activeProfile else {
            notice = "Сначала добавьте ребёнка"
            return
        }
        overlay = .create(profile)
    }

    private func open(_ summary: StorySummary) {
        Task {
            do {
                let story = try await app.readable(summary)
                overlay = .reading(storyId: summary.id, story, app.hero(for: summary))
            } catch {
                notice = "Не удалось открыть сказку. Проверьте интернет."
            }
        }
    }
}
