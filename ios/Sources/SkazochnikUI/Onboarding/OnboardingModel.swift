import SwiftUI
import SkazochnikCore

/// What the parent has entered so far in the profile steps.
public struct ProfileDraft: Equatable {
    public var name = ""
    public var age = 5
    public var gender: Gender?
    public var appearance = Appearance()
    public var interests: [String] = []
    public var world: WorldID = .forest

    public init() {}

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var input: ChildProfileInput {
        ChildProfileInput(
            name: trimmedName,
            age: age,
            gender: gender,
            appearance: appearance,
            interests: interests,
            worlds: [world]
        )
    }
}

public enum OnboardingStep: Int, CaseIterable {
    case welcome, value, name, age, appearance, interests, world

    /// Position in the five profile steps (the progress bar), nil for the intro screens.
    var profileIndex: Int? {
        switch self {
        case .name: 0
        case .age: 1
        case .appearance: 2
        case .interests: 3
        case .world: 4
        default: nil
        }
    }

    static let profileSteps = 5
}

@MainActor
public final class OnboardingModel: ObservableObject {
    @Published public var step: OnboardingStep = .welcome
    @Published public var draft = ProfileDraft()
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?
    @Published public var paywall: PaywallInfo?

    private let client: APIClient
    private let onFinished: (ChildProfile) -> Void

    public init(client: APIClient, onFinished: @escaping (ChildProfile) -> Void) {
        self.client = client
        self.onFinished = onFinished
    }

    public func next() {
        guard let following = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    public func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    public func toggleInterest(_ interest: String) {
        if let index = draft.interests.firstIndex(of: interest) {
            draft.interests.remove(at: index)
        } else {
            draft.interests.append(interest)
        }
    }

    /// Creates the guest account if needed, saves the profile and hands it to the app.
    public func finish() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await client.ensureSignedIn()
            let profile = try await client.createProfile(draft.input)
            onFinished(profile)
        } catch let APIError.paywall(info) {
            paywall = info
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        switch error as? APIError {
        case .transport:
            "Нет связи с сервером. Проверьте интернет и попробуйте ещё раз."
        case .server(_, _, let message):
            message
        default:
            "Не получилось сохранить профиль. Попробуйте ещё раз."
        }
    }
}
