import SwiftUI
import SkazochnikCore

/// Welcome, value slides and the five profile steps from the design prototype.
public struct OnboardingFlow: View {
    @StateObject private var model: OnboardingModel

    public init(client: APIClient, onFinished: @escaping (ChildProfile) -> Void) {
        _model = StateObject(wrappedValue: OnboardingModel(client: client, onFinished: onFinished))
    }

    public var body: some View {
        ZStack {
            NightBackground(starCount: 40, seed: UInt64(model.step.rawValue + 1) &* 7)
            screen
                .id(model.step)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .animation(.easeOut(duration: 0.35), value: model.step)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var screen: some View {
        switch model.step {
        case .welcome: WelcomeView(model: model)
        case .value: ValueView(model: model)
        case .name: NameStepView(model: model)
        case .age: AgeStepView(model: model)
        case .appearance: AppearanceStepView(model: model)
        case .interests: InterestsStepView(model: model)
        case .world: WorldStepView(model: model)
        }
    }
}
