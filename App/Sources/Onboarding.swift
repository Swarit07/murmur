import AppKit
import AVFoundation
import Combine
import MurmurKit
import SwiftUI

/// Onboarding (spec section 6). Resumes where it stopped if Murmur quits, and skips steps already done.
enum OnboardingStep: Int, CaseIterable {
    case welcome, microphone, accessibility, inputMonitoring, models, micTest, shortcut, languages, practiceHold, practiceHandsFree, data, flowBar

    var title: String {
        switch self {
        case .welcome: "Welcome to Murmur"
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .models: "Getting the models ready"
        case .micTest: "Test your microphone"
        case .shortcut: "Choose the shortcut"
        case .languages: "Languages"
        case .practiceHold: "Practice: hold to talk"
        case .practiceHandsFree: "Practice: hands-free"
        case .data: "Your data"
        case .flowBar: "This is the Flow Bar"
        }
    }

    /// Permission steps already granted are skipped.
    @MainActor func isDone(_ model: OnboardingModel) -> Bool {
        switch self {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: Permissions.accessibility
        case .inputMonitoring: Permissions.inputMonitoring
        case .models: model.modelsReady
        default: false
        }
    }
}

@MainActor
@Observable
final class OnboardingModel {
    let hub: HubModel
    let settings = AppSettings.shared
    var step: OnboardingStep
    var modelsReady = false
    var practiceDone: Set<OnboardingStep> = []
    var onFinish: (() -> Void)?
    var onShowFlowBar: ((Bool) -> Void)?

    init(hub: HubModel) {
        self.hub = hub
        step = OnboardingStep(rawValue: AppSettings.shared.onboardingStep) ?? .welcome
    }

    func next() {
        var candidate = step.rawValue + 1
        while let s = OnboardingStep(rawValue: candidate), s.isDone(self) { candidate += 1 }
        guard let s = OnboardingStep(rawValue: candidate) else { finish(); return }
        go(s)
    }

    func back() {
        var candidate = step.rawValue - 1
        while let s = OnboardingStep(rawValue: candidate), s.isDone(self), candidate > 0 { candidate -= 1 }
        if let s = OnboardingStep(rawValue: max(0, candidate)) { go(s) }
    }

    func go(_ s: OnboardingStep) {
        if step == .micTest { hub.controller.stopMicTest() }
        if step == .flowBar { onShowFlowBar?(false) }
        step = s
        settings.onboardingStep = s.rawValue
        if s == .flowBar { onShowFlowBar?(true) }
    }

    func finish() {
        hub.controller.stopMicTest()
        onShowFlowBar?(false)
        settings.onboardingDone = true
        settings.onboardingStep = 0
        onFinish?()
    }
}

struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(model.step.title).font(.title2.bold())
                Spacer()
                Text("\(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)").foregroundStyle(.secondary)
            }
            ProgressView(value: Double(model.step.rawValue + 1), total: Double(OnboardingStep.allCases.count))
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                if model.step != .welcome { Button("Back") { model.back() } }
                Spacer()
                if skippable { Button("Skip") { model.next() } }
                Button(model.step == .flowBar ? "Continue to Murmur" : "Continue") { model.next() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
        }
        .padding(28)
        .frame(width: 600, height: 470)
        .onReceive(timer) { _ in tick += 1 }
        .onChange(of: tick) { autoAdvance() }
    }

    var skippable: Bool {
        [.practiceHold, .practiceHandsFree, .languages, .micTest].contains(model.step)
    }

    /// Permission steps continue only once granted; models only once loaded.
    var canContinue: Bool {
        switch model.step {
        case .microphone, .accessibility, .inputMonitoring, .models: model.step.isDone(model)
        default: true
        }
    }

    func autoAdvance() {
        model.modelsReady = model.hub.controller.status.phase != .loading
        if [.microphone, .accessibility].contains(model.step), model.step.isDone(model) { model.next() }
    }

    @ViewBuilder var content: some View {
        switch model.step {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Text("Murmur turns your voice into text in any app. Hold a key, speak, let go, and the text appears where your cursor is.")
                Text("Everything runs on this Mac. Your audio and text are not sent anywhere unless you choose a cloud option later.")
                    .foregroundStyle(.secondary)
                Text("Setup takes about two minutes: three permissions, a mic check, your shortcut, and a quick practice.")
                    .foregroundStyle(.secondary)
            }
        case .microphone:
            PermissionStep(
                text: "Murmur listens only while you hold the shortcut or a hands-free dictation runs.",
                granted: model.step.isDone(model), button: "Allow microphone"
            ) { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
        case .accessibility:
            PermissionStep(
                text: "Accessibility lets Murmur find the text box you are in and paste your words there. It never types into password fields.",
                granted: model.step.isDone(model), button: "Open Accessibility settings"
            ) {
                Permissions.promptAccessibility()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        case .inputMonitoring:
            VStack(alignment: .leading, spacing: 12) {
                PermissionStep(
                    text: "Input Monitoring lets Murmur notice when you hold the dictation key. Murmur looks only at its own shortcut and Esc; it does not record what you type.",
                    granted: model.step.isDone(model), button: "Open Input Monitoring settings"
                ) {
                    Permissions.requestInputMonitoring()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
                if !model.step.isDone(model) {
                    Text("After you turn Murmur on, macOS may ask to quit and reopen it. Choose Quit & Reopen; setup continues where you left off.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        case .models:
            VStack(alignment: .leading, spacing: 12) {
                Text("Murmur's speech and cleanup models run on this Mac. The first time, they download (about 3 GB); after that they load in a few seconds.")
                if model.modelsReady {
                    Label("Ready: \(model.hub.controller.engineDescription) and \(model.hub.controller.cleanupDescription)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    HStack { ProgressView().controlSize(.small); Text("Downloading and loading…").foregroundStyle(.secondary) }
                    Text("You can keep going; Murmur finishes this in the background.").font(.caption).foregroundStyle(.secondary)
                    Button("Continue anyway") { model.next() }
                }
            }
        case .micTest:
            VStack(alignment: .leading, spacing: 14) {
                Text("Say something. The bars should move with your voice.")
                MicrophoneSettings(model: model.hub)
            }
            .onAppear { _ = model.hub.controller.startMicTest() }
        case .shortcut:
            VStack(alignment: .leading, spacing: 12) {
                Text("Hold the push-to-talk shortcut while you speak, and let go to insert. For longer dictation, use the hands-free shortcut or double-tap push-to-talk, then press it again to finish.")
                Form { ShortcutSettings(model: model.hub) }.formStyle(.grouped)
            }
        case .languages:
            VStack(alignment: .leading, spacing: 12) {
                Text("Murmur detects your language automatically. If you only speak one or two, choose them.")
                LanguagePicker(settings: model.settings)
            }
        case .practiceHold:
            PracticeStep(
                model: model, step: .practiceHold,
                instruction: "Click in the box, hold \(DictationController.shortcutConfiguration(model.settings).pushToTalk.displayName), say “Hello from Murmur, this is my first dictation,” and let go.")
        case .practiceHandsFree:
            PracticeStep(
                model: model, step: .practiceHandsFree,
                instruction: "Click in the box, press \(DictationController.shortcutConfiguration(model.settings).handsFree.displayName) (or double-tap push-to-talk), say a sentence, then press it again to finish.")
        case .data:
            DataStep(settings: model.settings)
        case .flowBar:
            VStack(alignment: .leading, spacing: 12) {
                Text("The Flow Bar sits just above your Dock. It grows while you speak, shows when Murmur is working, and tells you if something needs attention.")
                Text("Click it to start a hands-free dictation. Right-click it for more, or drag it somewhere else.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PermissionStep: View {
    let text: String
    let granted: Bool
    let button: String
    let request: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(button, action: request).controlSize(.large)
            }
        }
    }
}

struct PracticeStep: View {
    let model: OnboardingModel
    let step: OnboardingStep
    let instruction: String
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(instruction)
            TextEditor(text: $text)
                .font(.body)
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("That worked.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }
}

struct DataStep: View {
    let settings: AppSettings
    @State private var choice: String = AppSettings.shared.neverStore ? "never" : (AppSettings.shared.keepAudio ? "keep" : "text")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Murmur keeps a History of your dictations on this Mac, so nothing you say is lost.")
            Picker("", selection: $choice) {
                Text("Keep text and audio for 14 days (audio lets you replay and retry)").tag("keep")
                Text("Keep text only").tag("text")
                Text("Keep nothing: no History, nothing written to disk").tag("never")
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .onChange(of: choice) {
                settings.neverStore = choice == "never"
                settings.keepAudio = choice == "keep"
            }
            Text("You can change this any time in Settings › Data and Privacy.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
