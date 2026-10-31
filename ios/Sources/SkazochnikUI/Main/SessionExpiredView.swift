import SwiftUI

/// Shown when the server no longer recognises the account. A guest account has no password to sign
/// in with again, so the honest way out is to start over.
struct SessionExpiredView: View {
    let onStartOver: () -> Void

    var body: some View {
        ZStack {
            NightBackground(starCount: 50, seed: 17)
            VStack(spacing: 0) {
                Spacer()
                MoonIcon(size: 72).padding(.bottom, 28)
                Text("Не удалось войти в аккаунт").display(28).padding(.bottom, 14)
                Text("Сервер больше не узнаёт этот гостевой аккаунт, поэтому войти в него снова нельзя. Начните заново: профиль и новые сказки создадутся с нуля.")
                    .bodyStyle().multilineTextAlignment(.center).frame(maxWidth: 310)
                Spacer()
                Button("Начать заново", action: onStartOver).buttonStyle(.primaryPill).padding(.bottom, 24)
            }
            .padding(.horizontal, 26)
        }
        .preferredColorScheme(.dark)
    }
}
