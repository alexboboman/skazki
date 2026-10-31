import SwiftUI

enum MainTab: Hashable {
    case home, library, kids
}

/// Bottom bar of the design: «Сегодня», «Сказки», a gold «Сочинить» button in the middle, «Дети».
struct MainTabBar: View {
    @Binding var tab: MainTab
    let onCreate: () -> Void

    var body: some View {
        HStack {
            item(.home, "Сегодня", "house")
            item(.library, "Сказки", "books.vertical")
            Button(action: onCreate) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x2B1C0C))
                    .frame(width: 50, height: 50)
                    .background(LinearGradient(colors: [Color(hex: 0xF7D9A8), Theme.gold, Color(hex: 0xD2873F)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .shadow(color: Theme.gold.opacity(0.5), radius: 12, y: 8)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Сочинить сказку")
            item(.kids, "Дети", "person.2")
        }
        .frame(height: 64)
        .background(Color(hex: 0x221E3A, opacity: 0.78), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border))
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .padding(.top, 10)
        .background(LinearGradient(colors: [Theme.bg0.opacity(0), Theme.bg0.opacity(0.92), Theme.bg0], startPoint: .top, endPoint: .bottom))
    }

    private func item(_ target: MainTab, _ title: String, _ icon: String) -> some View {
        let selected = tab == target
        return Button { tab = target } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(selected ? Theme.accent : Theme.text3)
                Text(title).font(Theme.sans(11.5, weight: .medium)).foregroundStyle(selected ? Theme.text : Theme.text3)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
