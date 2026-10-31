import Foundation

/// "Сегодня", "Вчера", "2 дня назад", "На неделе", "В октябре": the short day labels of the library cards.
public enum StoryDateLabel {
    private static let monthsPrepositional = [
        "январе", "феврале", "марте", "апреле", "мае", "июне",
        "июле", "августе", "сентябре", "октябре", "ноябре", "декабре",
    ]

    public static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0

        switch days {
        case ..<1: return "Сегодня"
        case 1: return "Вчера"
        case 2...4: return "\(days) \(days < 5 ? "дня" : "дней") назад"
        case 5...7: return "На неделе"
        default:
            let month = calendar.component(.month, from: date) - 1
            return "В \(monthsPrepositional[month])"
        }
    }
}
