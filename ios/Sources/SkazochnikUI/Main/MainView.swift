import SwiftUI
import SkazochnikCore

/// The app after onboarding: three tabs, the create button and full-screen overlays for reading,
/// creating a story and adding a child.
public struct MainView: View {
    private enum Overlay: Equatable {
        case reading(storyId: String, ReadableStory, HeroInfo)
        case series(storyId: String)
        case create(ChildProfile)
        case addChild
        case editChild(ChildProfile)
    }

    @StateObject private var app: AppModel
    @EnvironmentObject private var subscriptions: SubscriptionStore
    private let onStartOver: () -> Void
    @State private var tab: MainTab = .home
    @State private var overlay: Overlay?
    @State private var notice: String?

    /// `onStartOver` runs after the lost account's data was wiped; the app then restarts onboarding.
    public init(client: APIClient, cache: LibraryCache = FileLibraryCache(), onStartOver: @escaping () -> Void = {}) {
        _app = StateObject(wrappedValue: AppModel(client: client, repository: LibraryRepository(client: client, cache: cache)))
        self.onStartOver = onStartOver
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
                        KidsView(app: app, onAdd: { overlay = .addChild }, onEdit: { overlay = .editChild($0) })
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

            if app.sessionExpired {
                SessionExpiredView {
                    app.startOver()
                    onStartOver()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: overlay)
        .animation(.easeOut(duration: 0.2), value: notice)
        .preferredColorScheme(.dark)
        .task { await app.refresh() }
        // A purchase (or a renewal seen by the App Store) changes the plan while the app is open.
        .onReceive(subscriptions.$entitlements.compactMap { $0 }) { app.applyEntitlements($0) }
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
                },
                premiumVoice: app.premiumVoice(for: story)
            )
            .background(Theme.bg0.ignoresSafeArea())
            .transition(.move(edge: .trailing))
        case .series(let id):
            SeriesFlow(app: app, storyId: id) { overlay = nil }
                .background(Theme.bg0.ignoresSafeArea())
                .transition(.move(edge: .trailing))
        case .create(let profile):
            CreateFlow(app: app, profile: profile, onOpenSeries: { overlay = .series(storyId: $0) }) { overlay = nil }
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
        case .editChild(let profile):
            OnboardingFlow(
                client: app.client,
                editing: profile,
                onFinished: { updated in
                    app.updated(updated)
                    overlay = nil
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
        if summary.isSeries {
            overlay = .series(storyId: summary.id)
            return
        }

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
