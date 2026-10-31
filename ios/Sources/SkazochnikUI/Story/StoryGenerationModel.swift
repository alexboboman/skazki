import SwiftUI
import SkazochnikCore

/// Drives the "Создаём сказку" screen: the five steps of the design advance on a timer while the
/// real request runs, then the screen waits for the response.
@MainActor
public final class StoryGenerationModel: ObservableObject {
    public static let steps = [
        "Готовим идею сказки…",
        "Пишем добрую историю…",
        "Проверяем, что всё подходит ребёнку…",
        "Рисуем иллюстрации…",
        "Сохраняем в библиотеку…",
    ]

    public enum Failure: Error, Equatable {
        case paywall(PaywallInfo)
        /// The safety check rejected two drafts in a row.
        case rejected
        case offline
        case other(String)
    }

    public enum Phase: Equatable {
        case running
        case failed(Failure)
        case done(ReadableStory)
    }

    @Published public private(set) var phase: Phase = .running
    /// Index of the step being worked on; equals `steps.count` when everything is done.
    @Published public private(set) var currentStep = 0

    private let client: APIClient
    private let request: GenerateStoryRequest
    private let stepDelay: Duration
    private let finishDelay: Duration
    private var task: Task<Void, Never>?

    public init(
        client: APIClient,
        request: GenerateStoryRequest,
        stepDelay: Duration = .milliseconds(1300),
        finishDelay: Duration = .milliseconds(850)
    ) {
        self.client = client
        self.request = request
        self.stepDelay = stepDelay
        self.finishDelay = finishDelay
    }

    public func start() {
        guard task == nil else { return }
        phase = .running
        currentStep = 0

        task = Task { [weak self] in
            guard let self else { return }

            // The first four steps advance on a timer; the last one stays active until the answer arrives.
            let ticker = Task { [weak self] in
                guard let self else { return }
                for _ in 0..<(Self.steps.count - 1) {
                    try? await Task.sleep(for: self.stepDelay)
                    if Task.isCancelled { return }
                    self.currentStep += 1
                }
            }

            let result = await self.fetch()
            ticker.cancel()
            if Task.isCancelled { return }

            switch result {
            case .success(let story):
                // A fast answer still walks through the remaining steps, so the screen never just flashes.
                while self.currentStep < Self.steps.count {
                    self.currentStep += 1
                    try? await Task.sleep(for: self.stepDelay / 5)
                    if Task.isCancelled { return }
                }
                try? await Task.sleep(for: self.finishDelay)
                if !Task.isCancelled { self.phase = .done(story) }
            case .failure(let failure):
                self.phase = .failed(failure)
            }
        }
    }

    public func retry() {
        task?.cancel()
        task = nil
        start()
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    private func fetch() async -> Result<ReadableStory, Failure> {
        do {
            try await client.ensureSignedIn()
            let response = try await client.generateStory(request)
            return .success(ReadableStory(response: response))
        } catch let APIError.paywall(info) {
            return .failure(.paywall(info))
        } catch APIError.storyRejected {
            return .failure(.rejected)
        } catch APIError.transport {
            return .failure(.offline)
        } catch let APIError.server(_, _, message) {
            return .failure(.other(message))
        } catch {
            return .failure(.other("Не получилось создать сказку. Попробуйте ещё раз."))
        }
    }
}
