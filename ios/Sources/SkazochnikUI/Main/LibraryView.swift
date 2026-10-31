import SwiftUI
import SkazochnikCore

/// «Сказки»: filter by favourites and by child, two-column grid of stories.
struct LibraryView: View {
    @ObservedObject var app: AppModel
    let onOpen: (StorySummary) -> Void
    let onFavorite: (StorySummary) -> Void

    @State private var favoritesOnly = false
    @State private var kidFilter: String?
    @State private var searching = false
    @State private var query = ""
    @State private var pendingDelete: StorySummary?
    @State private var deleteFailed = false
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        let list = app.stories(for: kidFilter, favoritesOnly: favoritesOnly, matching: query)

        AdaptiveScroll {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Сказки").display(30, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                    CircleIconButton(systemName: searching ? "xmark" : "magnifyingglass", label: searching ? "Закрыть поиск" : "Поиск") {
                        searching.toggle()
                        if searching { searchFocused = true } else { query = "" }
                    }
                }
                .padding(.bottom, 18)

                if searching {
                    TextField("", text: $query, prompt: Text("Название сказки").foregroundStyle(Theme.text3))
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.text)
                        .tint(Theme.accent)
                        .focused($searchFocused)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.border))
                        .padding(.bottom, 14)
                }

                HStack(spacing: 0) {
                    segment("Все", selected: !favoritesOnly) { favoritesOnly = false }
                    segment("Любимые", selected: favoritesOnly) { favoritesOnly = true }
                }
                .padding(4)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border))
                .padding(.bottom, 14)

                if app.profiles.count > 1 {
                    FlowLayout(spacing: 8) {
                        Chip("Все дети", selected: kidFilter == nil) { kidFilter = nil }
                        ForEach(app.profiles) { profile in
                            Chip(profile.name, selected: kidFilter == profile.id) { kidFilter = profile.id }
                        }
                    }
                    .padding(.bottom, 20)
                }

                if app.isOffline { OfflineNote().padding(.bottom, 14) }

                if list.isEmpty {
                    VStack(spacing: 12) {
                        MoonIcon(size: 64)
                        Text(!query.isEmpty ? "Ничего не нашлось." : favoritesOnly ? "Любимых сказок пока нет." : "Здесь пока пусто.").bodyStyle()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(list) { story in card(story) }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .refreshable { await app.refresh() }
        .confirmationDialog(
            "Удалить сказку?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                guard let story = pendingDelete else { return }
                Task { deleteFailed = !(await app.deleteStory(story)) }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(pendingDelete?.title ?? "")
        }
        .alert("Не получилось удалить", isPresented: $deleteFailed) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Проверьте интернет и попробуйте ещё раз.")
        }
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.sans(14.5, weight: .medium))
                .foregroundStyle(selected ? Color(hex: 0x1A1330) : Theme.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selected ? Theme.accent : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func card(_ story: StorySummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Button { onOpen(story) } label: {
                    StoryThumb(story: story, hero: app.hero(for: story), coverURL: app.client.mediaURL(story.coverImageUrl ?? ""), height: 150)
                }
                .buttonStyle(.plain)
                Button { onFavorite(story) } label: {
                    Image(systemName: story.favorite ? "heart.fill" : "heart")
                        .font(.system(size: 16))
                        .foregroundStyle(story.favorite ? Theme.gold : .white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(story.favorite ? "Убрать из любимых" : "В любимые")
            }
            Button { onOpen(story) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(story.title ?? "Сказка на ночь")
                        .font(Theme.serif(15.5)).foregroundStyle(Theme.text)
                        .lineLimit(3).multilineTextAlignment(.leading)
                    Text("\(story.readingMinutes) мин").captionStyle(12.5)
                }
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button(role: .destructive) { pendingDelete = story } label: { Label("Удалить", systemImage: "trash") }
        }
        .accessibilityAction(named: "Удалить") { pendingDelete = story }
    }
}
