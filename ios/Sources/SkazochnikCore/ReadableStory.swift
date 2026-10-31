import Foundation

/// A story prepared for the reading screen: body paragraphs with the illustrations placed between them.
public struct ReadableStory: Equatable, Sendable {
    public enum Block: Equatable, Identifiable, Sendable {
        case paragraph(index: Int, text: String)
        case illustration(MediaAsset)

        public var id: String {
            switch self {
            case .paragraph(let index, _): "p\(index)"
            case .illustration(let asset): "m\(asset.id)"
            }
        }
    }

    public var storyId: String?
    public var title: String
    public var blocks: [Block]
    public var moral: String?
    public var closing: String?
    public var readingMinutes: Int

    public var illustrationCount: Int {
        blocks.reduce(0) { count, block in
            if case .illustration = block { count + 1 } else { count }
        }
    }

    public var paragraphs: [String] {
        blocks.compactMap { block in
            if case .paragraph(_, let text) = block { text } else { nil }
        }
    }

    public init(
        storyId: String? = nil,
        title: String,
        text: String,
        media: [MediaAsset],
        moral: String? = nil,
        closing: String? = nil,
        readingMinutes: Int
    ) {
        self.storyId = storyId
        self.title = title
        self.moral = moral
        self.closing = closing
        self.readingMinutes = readingMinutes
        self.blocks = Self.layout(text: text, media: media)
    }

    public init(response: GenerateStoryResponse) {
        self.init(
            storyId: response.storyId,
            title: response.story.title ?? "Сказка на ночь",
            text: response.story.text,
            media: response.media,
            moral: response.story.moral,
            closing: response.story.closing,
            readingMinutes: response.story.readingMinutes
        )
    }

    /// Reads part 1 of a saved story. Multi-part series get their own reader later.
    public init(story: Story) {
        let part = story.parts.first
        self.init(
            storyId: story.id,
            title: story.title ?? "Сказка на ночь",
            text: part?.text ?? "",
            media: part?.media ?? [],
            moral: story.moral,
            closing: story.closing,
            readingMinutes: story.readingMinutes
        )
    }

    /// `afterParagraph` is the 1-based body paragraph an image follows; out-of-range values go to the end.
    static func layout(text: String, media: [MediaAsset]) -> [Block] {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var blocks: [Block] = []
        for (offset, paragraph) in paragraphs.enumerated() {
            let number = offset + 1
            blocks.append(.paragraph(index: number, text: paragraph))
            let isLast = number == paragraphs.count
            for asset in media where asset.afterParagraph == number || (isLast && asset.afterParagraph > paragraphs.count) {
                blocks.append(.illustration(asset))
            }
        }
        return blocks
    }
}
