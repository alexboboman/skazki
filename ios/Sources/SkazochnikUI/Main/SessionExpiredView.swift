import SwiftUI

/// Shown when the server no longer recognises the account. A guest account has no password to sign
/// in with again, so the honest way out is to start over.
struct SessionExpiredView: View {
    let onStartOver: () -> Void

    var body: some View {
        ZStack {
            Theme.bg0.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                MoonIcon(size: 72).padding(.bottom, 28)
                Text("Не удалось войти в аккаунт").display(28).padding(.bottom, 14)
                Text("Сохранённые сказки остались на сервере, но этот гостевой аккаунт больше не подтверждается. Начните заново: профиль и новые сказки создадутся с нуля.")
                    .bodyStyle().multilineTextAlignment(.center).frame(maxWidth: 310)
                Spacer()
                Button("Начать заново", action: onStartOver).buttonStyle(.primaryPill).padding(.bottom, 24)
            }
            .padding(.horizontal, 26)
        }
        .preferredColorScheme(.dark)
    }
}
