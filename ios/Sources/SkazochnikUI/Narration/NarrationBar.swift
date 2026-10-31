import SwiftUI

/// Player strip at the bottom of the reader: play/pause, paragraph skip, speed, sleep timer, close.
struct NarrationBar: View {
    @ObservedObject var narration: NarrationController

    var body: some View {
        VStack(spacing: 8) {
            if let notice = narration.notice {
                Text(notice)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.card2, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderStrong))
                    .transition(.opacity)
            }

            HStack(spacing: 4) {
                if narration.isPreparing { preparing } else { controls }
                Spacer(minLength: 6)
                if narration.offersPremium { voiceMenu }
                if !narration.isPreparing { speedMenu }
                timerMenu
                control("xmark", "Остановить чтение вслух") { narration.stop() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Theme.card2.opacity(0.9), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderStrong))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        }
        .animation(.easeOut(duration: 0.2), value: narration.notice)
    }

    private var premium: Bool { narration.voice == .premium }

    private var preparing: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.accent).frame(width: 34, height: 34)
            Text("Готовим голос…\nэто займёт около минуты")
                .font(Theme.sans(12.5))
                .foregroundStyle(Theme.text2)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.leading, 6)
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            control(premium ? "gobackward.15" : "backward.fill", premium ? "Назад на 15 секунд" : "Предыдущий абзац") { narration.skip(-1) }
            Button { narration.toggle() } label: {
                Image(systemName: narration.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: 0x1A1330))
                    .frame(width: 50, height: 50)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(narration.state == .playing ? "Пауза" : "Продолжить чтение вслух")
            control(premium ? "goforward.15" : "forward.fill", premium ? "Вперёд на 15 секунд" : "Следующий абзац") { narration.skip(1) }
        }
    }

    private var voiceMenu: some View {
        Menu {
            Button { narration.select(.premium) } label: {
                let title = narration.premiumLocked ? "Премиум-голос · Family+" : "Премиум-голос"
                if premium { Label(title, systemImage: "checkmark") } else { Text(title) }
            }
            Button { narration.select(.device) } label: {
                if !premium { Label("Голос устройства", systemImage: "checkmark") } else { Text("Голос устройства") }
            }
        } label: {
            pill("", icon: premium ? "sparkles" : "person.wave.2")
        }
        .accessibilityLabel("Голос: \(premium ? "премиум" : "устройства")")
    }

    private var speedMenu: some View {
        Menu {
            ForEach(NarrationController.Speed.allCases) { speed in
                Button { narration.setSpeed(speed) } label: {
                    if speed == narration.speed { Label(speed.title, systemImage: "checkmark") } else { Text(speed.title) }
                }
            }
        } label: {
            pill(narration.speed.title)
        }
        .accessibilityLabel("Скорость чтения: \(narration.speed.title)")
    }

    private var timerMenu: some View {
        Menu {
            ForEach(NarrationController.sleepOptions, id: \.self) { minutes in
                Button { narration.setSleepTimer(minutes: minutes) } label: {
                    let title = minutes.map { "Через \($0) мин" } ?? "До конца сказки"
                    if minutes == narration.sleepMinutes { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            pill(narration.sleepMinutes.map { "\($0) мин" } ?? "", icon: "moon.zzz.fill")
        }
        .accessibilityLabel("Таймер сна")
    }

    private func control(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text2)
                .frame(width: 38, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func pill(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 13)) }
            if !text.isEmpty { Text(text).font(Theme.sans(13, weight: .semibold)) }
        }
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Theme.card, in: Capsule())
    }
}
