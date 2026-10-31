import Foundation

/// The neural voice (Family+) as the player sees it.
public struct PremiumVoice: Sendable {
    /// False when the plan has no premium voice: the voice is still offered, with a hint about the plan.
    public var isAvailable: Bool
    /// Voices the story if that has not happened yet and returns the audio file on the device. Takes about a minute the first time.
    public var prepare: @Sendable () async throws -> URL

    public init(isAvailable: Bool, prepare: @escaping @Sendable () async throws -> URL) {
        self.isAvailable = isAvailable
        self.prepare = prepare
    }
}
