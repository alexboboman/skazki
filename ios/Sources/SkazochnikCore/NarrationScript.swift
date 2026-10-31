import Foundation

/// One piece of the story read aloud. `paragraph` is the 1-based body paragraph it belongs to, so the reader
/// can highlight it; the title, the moral and the good-night line have none.
public struct NarrationSegment: Equatable, Sendable {
    public var text: String
    public var paragraph: Int?

    public init(text: String, paragraph: Int? = nil) {
        self.text = text
        self.paragraph = paragraph
    }
}

extension ReadableStory {
    /// What a narrator says, in order: the name (with the part number for a series), the paragraphs,
    /// the moral and the good-night line. Illustrations are skipped.
    public var narrationScript: [NarrationSegment] {
        var script: [NarrationSegment] = []

        if let number = partNumber {
            script.append(NarrationSegment(text: "Часть \(number). \(title)."))
        } else {
            script.append(NarrationSegment(text: "\(title)."))
        }

        for block in blocks {
            if case .paragraph(let index, let text) = block {
                script.append(NarrationSegment(text: text, paragraph: index))
            }
        }

        if let moral, !moral.isEmpty {
            script.append(NarrationSegment(text: "Мораль сказки. \(moral)"))
        }

        if let closing, !closing.isEmpty {
            script.append(NarrationSegment(text: closing))
        }

        return script
    }
}
