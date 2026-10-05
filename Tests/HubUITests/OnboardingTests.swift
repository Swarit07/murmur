import Foundation
import MurmurKit
import Testing
@testable import HubUI

/// U7 (UI_REDESIGN.md v2): the restyled onboarding keeps SPEC §6's behavior: it resumes where it
/// stopped, skips steps already done (granted permissions, loaded models) in both directions, and saves
/// its progress (except in the design preview).
@Suite("Onboarding behavior")
@MainActor
struct OnboardingTests {
    func hub() throws -> HubModel {
        let store = try HistoryStore(url: nil)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "murmur.tests.onboarding") ?? .standard)
        return HubModel(controller: DictationController(settings: settings, store: store, sounds: nil), store: store)
    }

    @Test func resumesWhereItStopped() throws {
        let saved = AppSettings.shared.onboardingStep
        defer { AppSettings.shared.onboardingStep = saved }
        AppSettings.shared.onboardingStep = OnboardingStep.micTest.rawValue
        #expect(OnboardingModel(hub: try hub()).step == .micTest)
    }

    @Test func skipsGrantedStepsBothWays() throws {
        let saved = AppSettings.shared.onboardingStep
        defer { AppSettings.shared.onboardingStep = saved }
        AppSettings.shared.onboardingStep = 0
        let model = OnboardingModel(hub: try hub())
        model.isDoneOverride = { [.microphone, .accessibility, .models].contains($0) }
        #expect(model.step == .welcome)
        model.next()
        #expect(model.step == .inputMonitoring)
        model.next()
        #expect(model.step == .micTest)
        model.back()
        #expect(model.step == .inputMonitoring)
        model.back()
        #expect(model.step == .welcome)
    }

    @Test func savesProgressButNotInPreview() throws {
        let saved = AppSettings.shared.onboardingStep
        defer { AppSettings.shared.onboardingStep = saved }
        AppSettings.shared.onboardingStep = 0
        let model = OnboardingModel(hub: try hub())
        model.isDoneOverride = { _ in false }
        model.go(.languages)
        #expect(AppSettings.shared.onboardingStep == OnboardingStep.languages.rawValue)
        let preview = OnboardingModel(hub: try hub(), preview: true)
        preview.go(.data)
        #expect(AppSettings.shared.onboardingStep == OnboardingStep.languages.rawValue)
    }

    @Test func twelveStepsInSpecOrder() {
        #expect(OnboardingStep.allCases == [.welcome, .microphone, .accessibility, .inputMonitoring, .models, .micTest, .shortcut,
                                            .languages, .practiceHold, .practiceHandsFree, .data, .flowBar])
    }
}
