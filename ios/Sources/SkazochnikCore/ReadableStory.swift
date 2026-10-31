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
    /// Series only: which part this is, how many there will be, and the name of the whole series.
    public var partNumber: Int?
    public var partCount: Int?
    public var seriesTitle: String?

    public var isSeriesPart: Bool { partNumber != nil }
    public var isLastPart: Bool { partNumber != nil && partNumber == partCount }

    public var illustrationCount: Int {
        blocks.reduce(0) { count, block in
            if case .illustration = block { count + 1 } else { count }
        }
    }

    /// Path of the first illustration; the story cover on the reveal screen.
    public var coverImagePath: String? {
        for block in blocks {
            if case .illustration(let asset) = block { return asset.url }
        }
        return nil
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

    /// `seriesTitle` is only needed for parts after the first: their response carries the name of the part.
    public init(response: GenerateStoryResponse, seriesTitle: String? = nil) {
        self.init(
            storyId: response.storyId,
            title: response.story.title ?? "Сказка на ночь",
            text: response.story.text,
            media: response.media,
            // A series gives its moral with the last part only.
            moral: response.arc.map { $0.isCompleted ? response.story.moral : nil } ?? response.story.moral,
            closing: response.story.closing,
            readingMinutes: response.story.readingMinutes
        )
        if let arc = response.arc, let number = response.partNumber {
            partNumber = number
            partCount = arc.length
            self.seriesTitle = number == 1 ? (response.story.title ?? seriesTitle) : seriesTitle
        }
    }

    /// Reads a saved story; for a series, `part` picks the part (the first one by default).
    public init(story: Story, part number: Int? = nil) {
        let part = number.flatMap { n in story.parts.first { $0.partNumber == n } } ?? story.parts.first
        let isSeries = story.arc != nil
        self.init(
            storyId: story.id,
            title: (isSeries ? part?.title : nil) ?? story.title ?? "Сказка на ночь",
            text: part?.text ?? "",
            media: part?.media ?? [],
            // The moral of a series belongs to its last part.
            moral: isSeries ? (part?.partNumber == story.arc?.length ? story.moral : nil) : story.moral,
            closing: (isSeries ? part?.closing : nil) ?? story.closing,
            readingMinutes: story.readingMinutes
        )
        if let arc = story.arc, let part {
            partNumber = part.partNumber
            partCount = arc.length
            seriesTitle = story.title
        }
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
