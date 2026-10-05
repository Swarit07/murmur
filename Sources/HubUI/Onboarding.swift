import AppKit
import AVFoundation
import Combine
import MurmurKit
import SwiftUI
import UI

/// Onboarding (spec section 6). Resumes where it stopped if Murmur quits, and skips steps already done.
public enum OnboardingStep: Int, CaseIterable, Sendable {
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
public final class OnboardingModel {
    let hub: HubModel
    let settings = AppSettings.shared
    public var step: OnboardingStep
    var modelsReady = false
    var practiceDone: Set<OnboardingStep> = []
    public var onFinish: (() -> Void)?
    public var onShowFlowBar: ((Bool) -> Void)?
    /// The practice steps show a live copy of the Flow Bar inside the practice field.
    let practiceBar = FlowBarModel()
    /// A preview (design snapshots) shows steps without saving progress or starting the microphone.
    let preview: Bool

    public init(hub: HubModel, preview: Bool = false) {
        self.hub = hub
        self.preview = preview
        step = preview ? .welcome : (OnboardingStep(rawValue: AppSettings.shared.onboardingStep) ?? .welcome)
        practiceBar.levelSource = hub.controller.micLevel
    }

    /// The practice bar follows the dictation controller.
    func syncPracticeBar() {
        practiceBar.state = switch hub.status?.phase {
        case .recording(let handsFree)?: .listening(handsFree: handsFree)
        case .processing?: .processing
        case .inserted?: .inserted
        default: .idle
        }
    }

    /// Tests replace whether a step is done (permission granted, models loaded).
    func done(_ s: OnboardingStep) -> Bool { isDoneOverride?(s) ?? s.isDone(self) }
    var isDoneOverride: ((OnboardingStep) -> Bool)?

    func next() {
        var candidate = step.rawValue + 1
        while let s = OnboardingStep(rawValue: candidate), done(s) { candidate += 1 }
        guard let s = OnboardingStep(rawValue: candidate) else { finish(); return }
        go(s)
    }

    func back() {
        var candidate = step.rawValue - 1
        while let s = OnboardingStep(rawValue: candidate), done(s), candidate > 0 { candidate -= 1 }
        if let s = OnboardingStep(rawValue: max(0, candidate)) { go(s) }
    }

    func go(_ s: OnboardingStep) {
        if step == .micTest { hub.controller.stopMicTest() }
        if step == .flowBar { onShowFlowBar?(false) }
        step = s
        guard !preview else { return }
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

/// Onboarding (UI_REDESIGN.md v2 §5.4): one 400 × 560 step at a time on the ivory window, a mono
/// header with progress, a sunken illustration, the step's title and body, and one clay primary action.
/// Same steps, order and behavior as SPEC §6: resumes where it stopped, skips granted permissions,
/// advances on its own when a permission is granted.
public struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    public init(model: OnboardingModel) {
        self.model = model
    }

    public var body: some View {
        ThemeProvider { OnboardingSteps(model: model) }
    }
}

struct OnboardingSteps: View {
    @Bindable var model: OnboardingModel
    @Environment(\.theme) private var theme
    /// Permissions are polled while onboarding is open (the step advances on its own once granted).
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var tick = 0

    var body: some View {
        let motion = theme.motion
        ZStack {
            theme.colors.bgWindow.color
            step
                .id(model.step)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: motion.offset(MotionTokens.onboardingDrift))).animation(motion.easeOut(MotionTokens.onboardingStep)),
                    removal: .opacity.animation(motion.easeOut(MotionTokens.onboardingStep / 2))))
        }
        .frame(width: OnboardingGeometry.step.width, height: OnboardingGeometry.step.height)
        .overlay(alignment: .top) { WindowDragArea().frame(height: OnboardingGeometry.padding) }
        .ignoresSafeArea()
        .animation(motion.easeOut(MotionTokens.onboardingStep), value: model.step)
        .onReceive(timer) { _ in tick += 1 }
        .onChange(of: tick) { autoAdvance() }
        .onChange(of: model.hub.status) { model.syncPracticeBar() }
    }

    var hotkey: String { model.hub.hotkeyLabel }

    func autoAdvance() {
        guard !model.preview else { return }
        model.modelsReady = model.hub.controller.status.phase != .loading
        if [.microphone, .accessibility].contains(model.step), model.step.isDone(model) { model.next() }
    }

    @ViewBuilder var step: some View {
        let c = theme.colors
        let granted = model.step.isDone(model)
        switch model.step {
        case .welcome:
            WelcomeStep(model: model)
        case .microphone:
            StepScaffold(model: model, section: "Permissions", title: "Let Murmur hear you",
                         message: "Only while you hold the shortcut. Audio is transcribed on this Mac and deleted right after, unless you choose to keep it.",
                         primary: granted ? "Continue" : "Allow microphone") {
                if granted { model.next() } else { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
            } illustration: {
                MIllustrationWell { MicPromptMock() }
            }
        case .accessibility:
            StepScaffold(model: model, section: "Permissions", title: "Let Murmur type for you",
                         message: "Accessibility lets Murmur place text at your cursor in any app. It doesn’t read your screen, and never types into password fields.",
                         primary: granted ? "Continue" : "Open System Settings") {
                if granted { model.next() } else { openPane("Privacy_Accessibility"); Permissions.promptAccessibility() }
            } illustration: {
                MIllustrationWell { AccessibilityMock() }
            } extra: {
                if !granted { WaitingLine(text: "Waiting for permission — this updates on its own", running: !model.preview) }
            }
        case .inputMonitoring:
            StepScaffold(model: model, section: "Permissions", title: "Notice when you hold the key",
                         message: "Input Monitoring is how Murmur knows \(hotkey) is being held down — and released. It watches that one key; nothing you type is logged or stored.",
                         primary: granted ? "Continue" : "Open System Settings") {
                if granted { model.next() } else { Permissions.requestInputMonitoring(); openPane("Privacy_ListenEvent") }
            } illustration: {
                MIllustrationWell { HoldKeyMock(key: hotkey) }
            } extra: {
                if !granted {
                    Text("After you turn Murmur on, macOS may ask to quit and reopen it. Choose Quit & Reopen; setup continues where you left off.")
                        .textStyle(TypeTokens.hint).foregroundStyle(c.textTertiary.color).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .models:
            StepScaffold(model: model, section: "Setup", title: "Getting the models ready",
                         message: "Murmur’s speech and cleanup models run on this Mac. The first time, they download (about 3 GB); after that they load in a few seconds.",
                         primary: "Continue", primaryEnabled: granted) {
                model.next()
            } illustration: {
                MIllustrationWell { ModelsMock(ready: model.modelsReady || model.preview, model: model) }
            } extra: {
                if !(model.modelsReady || model.preview) {
                    HStack(spacing: Spacing.s8) {
                        Text("You can keep going; Murmur finishes this in the background.").textStyle(TypeTokens.hint).foregroundStyle(c.textTertiary.color)
                        MButton("Continue anyway", kind: .link, size: .small) { model.next() }
                    }
                }
            }
        case .micTest:
            StepScaffold(model: model, section: "Setup", title: "Check your mic",
                         message: "Read the line above at your normal volume. Aim for the bars to reach the last third.", primary: "Sounds good") {
                model.next()
            } illustration: {
                MIllustrationWell { MicTestMeter(model: model) }
            } extra: {
                MicrophonePicker(model: model.hub)
            }
            .onAppear { if !model.preview { _ = model.hub.controller.startMicTest() } }
        case .shortcut:
            StepScaffold(model: model, section: "Setup", title: "Pick how you talk",
                         message: "You can use both. Change them any time in Settings.", primary: "Continue", illustrationFirst: false) {
                model.next()
            } illustration: {
                ShortcutCards(model: model.hub)
            }
        case .languages:
            LanguagesStep(model: model)
        case .practiceHold:
            PracticeStepView(model: model, title: "Try it once",
                             lead: "Hold \(hotkey) and say: ", line: "“um remind me to call Mom on Sunday, uh, at noon.”")
        case .practiceHandsFree:
            PracticeStepView(model: model, title: "Try hands-free",
                             lead: "Press \(ShortcutRecorderRow.keys(DictationController.shortcutConfiguration(model.settings).handsFree).joined(separator: " ")) (or double-tap \(hotkey)), say: ",
                             line: "“Let’s move the launch to Friday,” then press it again to finish.")
        case .data:
            DataStepView(model: model)
        case .flowBar:
            StepScaffold(model: model, section: nil, title: "This is the Flow Bar",
                         message: "It rests just above your Dock. Hold \(hotkey) in any app and it opens up to listen. Click it for hands-free, right-click for more, or hide it any time from the menu bar.",
                         primary: "Start dictating") {
                model.next()
            } illustration: {
                MIllustrationWell { FlowBarSketch() }
            }
        }
    }

    func openPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Scaffold

/// The common step layout: header, illustration, title and body, extra content, footer.
struct StepScaffold<Illustration: View, Extra: View>: View {
    let model: OnboardingModel
    let section: String?
    let title: String
    let message: String
    let primary: String
    var primaryEnabled = true
    var illustrationFirst = true
    var leading: (title: String, action: () -> Void)?
    let onPrimary: () -> Void
    let illustration: Illustration
    let extra: Extra
    @Environment(\.theme) private var theme

    init(model: OnboardingModel, section: String?, title: String, message: String, primary: String, primaryEnabled: Bool = true,
         illustrationFirst: Bool = true, leading: (title: String, action: () -> Void)? = nil, onPrimary: @escaping () -> Void,
         @ViewBuilder illustration: () -> Illustration, @ViewBuilder extra: () -> Extra = { EmptyView() }) {
        self.model = model
        self.section = section
        self.title = title
        self.message = message
        self.primary = primary
        self.primaryEnabled = primaryEnabled
        self.illustrationFirst = illustrationFirst
        self.leading = leading
        self.onPrimary = onPrimary
        self.illustration = illustration()
        self.extra = extra()
    }

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: OnboardingGeometry.gap) {
            StepHeader(model: model, section: section)
            // The illustration takes what the copy leaves, so long copy shrinks the well, never the footer.
            if illustrationFirst { illustration.layoutPriority(1) }
            VStack(alignment: .leading, spacing: OnboardingGeometry.titleGap) {
                Text(title).textStyle(TypeTokens.stepTitle).foregroundStyle(c.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(message).textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !illustrationFirst { illustration.layoutPriority(1) }
            extra
            Spacer(minLength: 0)
            StepFooter(model: model, primary: primary, primaryEnabled: primaryEnabled, leading: leading, onPrimary: onPrimary)
        }
        .padding(OnboardingGeometry.padding)
        .frame(width: OnboardingGeometry.step.width, height: OnboardingGeometry.step.height, alignment: .topLeading)
    }
}

/// "02 / 12 · Permissions" and the 120 × 2 progress bar.
struct StepHeader: View {
    let model: OnboardingModel
    let section: String?
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let index = model.step.rawValue + 1
        let count = OnboardingStep.allCases.count
        HStack {
            Text(String(format: "%02d / %02d", index, count) + (section.map { " · \($0)" } ?? ""))
                .textStyle(TypeTokens.keycapSmall)
                .foregroundStyle(c.textTertiary.color)
            Spacer()
            ZStack(alignment: .leading) {
                Capsule(style: .circular).fill(c.edgePanel.color)
                Capsule(style: .circular).fill(c.inkFill.color)
                    .frame(width: OnboardingGeometry.progress.width * CGFloat(index) / CGFloat(count))
            }
            .frame(width: OnboardingGeometry.progress.width, height: OnboardingGeometry.progress.height)
            .accessibilityElement()
            .accessibilityLabel("Step \(index) of \(count)")
        }
    }
}

/// "Back" (or "Skip") on the left and the one clay action on the right.
struct StepFooter: View {
    let model: OnboardingModel
    let primary: String
    let primaryEnabled: Bool
    let leading: (title: String, action: () -> Void)?
    let onPrimary: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            let back = leading ?? ("Back", { model.back() })
            Button(action: back.action) {
                Text(back.title).textStyle(TypeTokens.label.weight(400)).foregroundStyle(theme.colors.textTertiary.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(back.title)
            Spacer()
            MButton(primary, kind: .primary, action: onPrimary)
                .disabled(!primaryEnabled)
                .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Steps with their own layout

struct WelcomeStep: View {
    let model: OnboardingModel
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        VStack(spacing: OnboardingGeometry.gap) {
            StepHeader(model: model, section: nil)
            Spacer(minLength: 0)
            VStack(spacing: OnboardingGeometry.welcomeGap) {
                Image(nsImage: BrandImages.appIcon)
                    .resizable()
                    .frame(width: OnboardingGeometry.appIcon, height: OnboardingGeometry.appIcon)
                    .accessibilityLabel("Murmur app icon")
                VStack(spacing: Spacing.s12) {
                    Text("Speak, and it’s written.").textStyle(TypeTokens.welcomeTitle).foregroundStyle(c.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    Text("Murmur turns your voice into clean, punctuated text in any app. Free, open source, and private by default.")
                        .textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: Spacing.s12) {
                MButton("Get started", kind: .primary, fullWidth: true) { model.next() }
                    .keyboardShortcut(.defaultAction)
                Text("v\(version) · macOS 14 or later").textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color)
            }
        }
        .padding(OnboardingGeometry.padding)
        .frame(width: OnboardingGeometry.step.width, height: OnboardingGeometry.step.height)
    }
}

struct LanguagesStep: View {
    let model: OnboardingModel
    @Environment(\.theme) private var theme
    @State private var chosen: Set<String> = Set(AppSettings.shared.languages)
    @State private var search = ""

    var body: some View {
        let shown = LanguageNames.common.filter { search.isEmpty || $0.1.localizedCaseInsensitiveContains(search) }
        StepScaffold(model: model, section: "Setup", title: "Which languages do you speak?",
                     message: "Murmur switches between them automatically, even mid-sentence. Choose none to let it detect every time.",
                     primary: chosen.isEmpty ? "Continue" : "Continue with \(chosen.count)", illustrationFirst: false) {
            model.next()
        } illustration: {
            VStack(alignment: .leading, spacing: Spacing.s12) {
                MSearchField("Search \(LanguageNames.common.count) languages", text: $search)
                // The chips scroll when they don't fit above the footer.
                ViewThatFits(in: .vertical) {
                    chips(shown)
                    ScrollView { chips(shown) }.scrollIndicators(.automatic)
                }
            }
        }
    }

    private func chips(_ shown: [(String, String)]) -> some View {
        FlowLayout(spacing: Spacing.s8) {
            ForEach(shown, id: \.0) { code, name in
                MChip(name, selected: chosen.contains(code)) {
                    if chosen.contains(code) { chosen.remove(code) } else { chosen.insert(code) }
                    model.settings.languages = chosen.sorted()
                }
            }
        }
    }
}

struct PracticeStepView: View {
    let model: OnboardingModel
    let title: String
    let lead: String
    let line: String
    @Environment(\.theme) private var theme
    @State private var text = ""

    var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: OnboardingGeometry.gap) {
            StepHeader(model: model, section: "Practice")
            VStack(alignment: .leading, spacing: OnboardingGeometry.titleGap) {
                Text(title).textStyle(TypeTokens.stepTitle).foregroundStyle(c.textPrimary.color).accessibilityAddTraits(.isHeader)
                (Text(lead).foregroundStyle(c.textSecondary.color) + Text(line).font(theme.font(TypeTokens.quote)).foregroundStyle(c.textPrimary.color))
                    .textStyle(TypeTokens.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Spacing.s12) {
                Text("Practice field").textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color)
                MTextField("Click here, then dictate", text: $text, multiline: true)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: Spacing.s8) {
                        IconView(.check, size: HubGeometry.iconGlyph, color: c.textPrimary.color)
                        Text("That worked.").textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                    }
                }
                Spacer(minLength: 0)
                // The real Flow Bar, following this dictation.
                FlowBarView(model: model.practiceBar)
                    .frame(height: FlowBarController.canvas.height)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
            }
            .padding(Spacing.s16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(c.bgPanel.color))
            .overlay(shape.strokeBorder(c.edgeToast.color, lineWidth: Stroke.hairline))
            StepFooter(model: model, primary: "Looks right", primaryEnabled: true, leading: ("Skip", { model.next() })) { model.next() }
        }
        .padding(OnboardingGeometry.padding)
        .frame(width: OnboardingGeometry.step.width, height: OnboardingGeometry.step.height, alignment: .topLeading)
        .onAppear { model.syncPracticeBar() }
    }
}

struct DataStepView: View {
    let model: OnboardingModel
    @Environment(\.theme) private var theme
    @State private var never = AppSettings.shared.neverStore
    @State private var keepAudio = AppSettings.shared.keepAudio

    var body: some View {
        let c = theme.colors
        StepScaffold(model: model, section: "Privacy", title: "Your data, your call",
                     message: "Either way, audio and transcripts never leave this Mac.", primary: "Continue", illustrationFirst: false) {
            model.next()
        } illustration: {
            VStack(alignment: .leading, spacing: Spacing.s10) {
                MSelectableCard(selected: !never, label: "Keep History on this Mac", padding: Spacing.s14) { never = false } content: {
                    VStack(alignment: .leading, spacing: Spacing.s4) {
                        Text("Keep History on this Mac").textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                        Text("Every dictation is saved here, so nothing you say is lost. No analytics, no crash reports.")
                            .textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color).fixedSize(horizontal: false, vertical: true)
                    }
                }
                MSelectableCard(selected: never, label: "Keep nothing", padding: Spacing.s14) { never = true } content: {
                    VStack(alignment: .leading, spacing: Spacing.s4) {
                        Text("Keep nothing").textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                        Text("No History, nothing written to disk. Paste last still works until Murmur quits.")
                            .textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Text("Keep audio for 14 days").textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                    Spacer()
                    MToggle(isOn: $keepAudio, label: "Keep audio for 14 days", size: .small).disabled(never)
                }
                .padding(.horizontal, Spacing.s4)
            }
        }
        .onChange(of: never) {
            model.settings.neverStore = never
            if never { keepAudio = false }
        }
        .onChange(of: keepAudio) { model.settings.keepAudio = keepAudio }
    }
}

// MARK: - Illustrations (original drawings)

/// A sketch of the system's microphone prompt.
struct MicPromptMock: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(spacing: Spacing.s10) {
            IconView(.mic, size: HubGeometry.iconGlyph, color: c.textPrimary.color)
                .frame(width: OnboardingGeometry.mockIconBox, height: OnboardingGeometry.mockIconBox)
                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(c.edgeStrong.color, lineWidth: Stroke.hairline))
            Text("“Murmur” would like to access the microphone.")
                .textStyle(TypeTokens.hint.weight(600)).foregroundStyle(c.textPrimary.color).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: HubGeometry.settingsControlGap) {
                MockButton(title: "Don’t Allow", filled: false)
                MockButton(title: "Allow", filled: true)
            }
        }
        .padding(Spacing.s16)
        .frame(width: OnboardingGeometry.promptCard)
        .background(shape.fill(c.bgPanel.color))
        .overlay(shape.strokeBorder(c.edgeToast.color, lineWidth: Stroke.hairline))
        .accessibilityHidden(true)
    }
}

struct MockButton: View {
    let title: String
    let filled: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: OnboardingGeometry.mockButtonRadius, style: .continuous)
        Text(title)
            .textStyle(TypeTokens.flowSub)
            .foregroundStyle(filled ? c.onInk.color : c.textPrimary.color)
            .frame(maxWidth: .infinity)
            .frame(height: OnboardingGeometry.mockButtonHeight)
            .background(shape.fill(filled ? c.inkFill.color : .clear))
            .overlay { if !filled { shape.strokeBorder(c.edgeStrong.color, lineWidth: Stroke.hairline) } }
    }
}

/// A sketch of Privacy & Security › Accessibility with Murmur switched on.
struct AccessibilityMock: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
        VStack(spacing: 0) {
            Text("Privacy & Security › Accessibility").textStyle(TypeTokens.hint.weight(600)).foregroundStyle(c.textPrimary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s8)
            Hairline()
            HStack(spacing: Spacing.s10) {
                Image(nsImage: BrandImages.appIcon).resizable().frame(width: OnboardingGeometry.mockIcon, height: OnboardingGeometry.mockIcon)
                Text("Murmur").textStyle(TypeTokens.hint.weight(500)).foregroundStyle(c.textPrimary.color)
                Spacer()
                MockSwitch(on: true)
            }
            .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s10)
            Hairline()
            HStack(spacing: Spacing.s10) {
                RoundedRectangle(cornerRadius: Radius.keycapSmall, style: .continuous).strokeBorder(c.edgeStrong.color, lineWidth: Stroke.hairline)
                    .frame(width: OnboardingGeometry.mockIcon, height: OnboardingGeometry.mockIcon)
                Text("Terminal").textStyle(TypeTokens.hint).foregroundStyle(c.textTertiary.color)
                Spacer()
                MockSwitch(on: false)
            }
            .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s10)
        }
        .frame(width: OnboardingGeometry.settingsCard)
        .background(shape.fill(c.bgPanel.color))
        .clipShape(shape)
        .overlay(shape.strokeBorder(c.edgeToast.color, lineWidth: Stroke.hairline))
        .accessibilityHidden(true)
    }
}

struct MockSwitch: View {
    let on: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let size = OnboardingGeometry.mockToggle
        let knob = size.height - Spacing.s4
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule(style: .circular).fill(on ? c.inkFill.color : .clear)
            if !on { Capsule(style: .circular).strokeBorder(c.borderControl.color, lineWidth: Stroke.hairline) }
            Circle().fill(on ? c.onInk.color : c.stone.color).frame(width: knob, height: knob).padding(Spacing.s4 / 2)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The push-to-talk key held down, with how long it's been held.
struct HoldKeyMock: View {
    let key: String
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: OnboardingGeometry.holdKeyRadius, style: .continuous)
        VStack(spacing: OnboardingGeometry.holdGap) {
            Text(key)
                .textStyle(TypeTokens.keycapHold)
                .foregroundStyle(c.textPrimary.color)
                .padding(.horizontal, OnboardingGeometry.holdKeyPaddingH)
                .frame(minWidth: OnboardingGeometry.holdKey.width, minHeight: OnboardingGeometry.holdKey.height)
                .background(shape.fill(c.bgPanel.color))
                .overlay(shape.strokeBorder(c.edgeKey.color, lineWidth: Stroke.hairline))
                .overlay(alignment: .bottom) {
                    shape.inset(by: Stroke.hairline).stroke(c.edgeToast.color, lineWidth: Stroke.keycapBottom)
                        .mask(alignment: .bottom) { Rectangle().frame(height: Stroke.keycapBottom + Stroke.hairline) }
                }
                .offset(y: Stroke.keycapBottom)
            HStack(spacing: Spacing.s10) {
                Text("down").textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color)
                ZStack(alignment: .leading) {
                    Capsule(style: .circular).strokeBorder(c.edgeStrong.color, lineWidth: Stroke.hairline)
                    Capsule(style: .circular).fill(c.inkFill.color).frame(width: OnboardingGeometry.holdMeter.width * OnboardingGeometry.holdMeterFill)
                }
                .frame(width: OnboardingGeometry.holdMeter.width, height: OnboardingGeometry.holdMeter.height)
                Text("held 0.6s").textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The models: loading dots, then the names once they're ready.
struct ModelsMock: View {
    let ready: Bool
    let model: OnboardingModel
    @Environment(\.theme) private var theme

    static func friendly(_ names: [String: String], _ id: String) -> String {
        (names[id] ?? id).replacingOccurrences(of: " (recommended)", with: "")
    }

    var body: some View {
        let c = theme.colors
        VStack(spacing: Spacing.s12) {
            if ready {
                IconView(.check, size: HubGeometry.iconButton, color: c.textPrimary.color)
                Text("\(Self.friendly(ModelNames.engines, model.settings.engine)) and \(Self.friendly(ModelNames.cleanup, model.settings.cleanupProvider))")
                    .textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color).multilineTextAlignment(.center)
            } else {
                WaitingLine(text: "Downloading and loading…", running: true)
            }
        }
        .padding(Spacing.s20)
    }
}

/// "••••• Waiting for permission": five small ink dots rippling (`MurmurDots`), and a line of text.
struct WaitingLine: View {
    let text: String
    let running: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let size = OnboardingGeometry.rippleDot
        let motion = theme.motion
        HStack(spacing: Spacing.s8) {
            TimelineView(.animation(paused: !running)) { context in
                let now = context.date.timeIntervalSinceReferenceDate * motion.timeScale
                HStack(spacing: size * MotionTokens.dotsLift) {
                    ForEach(0..<FlowGeometry.dots, id: \.self) { i in
                        let ripple = motion.reduce ? 0.5 - 0.5 * cos(2 * .pi * now / MotionTokens.dotsPulseReduced)
                            : max(0, sin(now / MotionTokens.dotsPeriod * 2 * .pi - Double(i) * MotionTokens.dotsPhaseStep))
                        Circle().fill(c.textPrimary.color).frame(width: size, height: size)
                            .opacity(MotionTokens.dotsOpacityLow + (1 - MotionTokens.dotsOpacityLow) * ripple)
                    }
                }
            }
            .accessibilityHidden(true)
            Text(text).textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color)
        }
    }
}

/// The mic test: the level meter and the line to read.
struct MicTestMeter: View {
    let model: OnboardingModel
    @Environment(\.theme) private var theme
    @State private var smoother = MeterSmoother()

    var body: some View {
        let c = theme.colors
        VStack(spacing: Spacing.s20) {
            TimelineView(.animation(paused: model.preview || model.step != .micTest)) { context in
                MLevelMeter(level: model.preview ? MeterTokens.previewLevel : smoother.step(now: context.date.timeIntervalSinceReferenceDate, target: model.hub.micLevel))
            }
            Text("“Pack my box with five dozen jugs.”").textStyle(TypeTokens.quote).foregroundStyle(c.textPrimary.color)
        }
    }
}

/// The meter's smoothing (`MurmurLevels`: 0.35 rising and 0.08 falling, per frame at 60 fps).
@MainActor
final class MeterSmoother {
    private var value = 0.0
    private var last: TimeInterval?

    func step(now: TimeInterval, target: Double) -> Double {
        let frames = last.map { max(0, now - $0) * 60 } ?? 1
        last = now
        let k = target > value ? MeterTokens.attackPerFrame : MeterTokens.releasePerFrame
        value += (target - value) * (1 - pow(1 - k, frames))
        return value
    }
}

/// The microphone choice under the mic test.
struct MicrophonePicker: View {
    let model: HubModel
    @State private var devices = AudioDevices.inputs()
    @State private var selected = AppSettings.shared.microphoneUID ?? ""

    var body: some View {
        MSelect("Microphone", selection: $selected,
                options: [("", "System default")] + devices.map { ($0.uid, $0.name + ($0.isDefault ? " (default)" : "")) }, icon: .mic)
            .onChange(of: selected) { model.controller.selectMicrophone(uid: selected.isEmpty ? nil : selected) }
    }
}

/// The two ways to talk, each with its shortcut and a Change button (the v1 recorder).
struct ShortcutCards: View {
    let model: HubModel
    @Environment(\.theme) private var theme
    @State private var config: HotkeyConfiguration = DictationController.shortcutConfiguration(.shared)

    var body: some View {
        VStack(spacing: Spacing.s10) {
            card("Push-to-talk", "Hold, speak, release", "Best for quick replies and short notes.", shortcut: config.pushToTalk) { config.pushToTalk = $0 }
            card("Hands-free", "Tap to start, tap to stop", "Best for long emails and thinking out loud.", shortcut: config.handsFree) { config.handsFree = $0 }
        }
    }

    func card(_ title: String, _ how: String, _ best: String, shortcut: Shortcut, set: @escaping (Shortcut) -> Void) -> some View {
        let c = theme.colors
        return MCard(padding: Spacing.s14, radius: Radius.cardLarge) {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                Text(title).textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                ShortcutRecorderRow(title: how, detail: best, shortcut: shortcut, model: model) { new in
                    set(new)
                    model.controller.setShortcuts(config)
                }
                .padding(.horizontal, -HubGeometry.settingsRowPadding.width)
            }
        }
    }
}

/// The Flow Bar step's drawing: the idle pill just above a sketched Dock, with a hand-drawn arrow.
struct FlowBarSketch: View {
    @Environment(\.theme) private var theme

    static let arrow = "M20 2c-10 18 8 34 0 60 M14 55l6 8 6-8"

    var body: some View {
        let c = theme.colors
        let dock = UnevenRoundedRectangle(topLeadingRadius: Radius.button, topTrailingRadius: Radius.button, style: .continuous)
        ZStack(alignment: .bottom) {
            VStack(spacing: OnboardingGeometry.pillCaptionGap) {
                Text("This little pill").textStyle(TypeTokens.trigger).foregroundStyle(c.textPrimary.color)
                ArrowSketch(data: Self.arrow)
                    .stroke(c.textPrimary.color, style: StrokeStyle(lineWidth: Stroke.hairline, lineCap: .round, lineJoin: .round))
                    .frame(width: OnboardingGeometry.arrow.width, height: OnboardingGeometry.arrow.height)
                Spacer(minLength: 0)
            }
            .padding(.top, OnboardingGeometry.pillCaptionTop)
            FlowIdlePill().padding(.bottom, OnboardingGeometry.pillAboveDock)
            HStack(spacing: Spacing.s10) {
                ForEach(0..<OnboardingGeometry.dockTiles, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.keycapSmall, style: .continuous).strokeBorder(c.edgeStrong.color, lineWidth: Stroke.hairline)
                        .frame(width: OnboardingGeometry.dockTile, height: OnboardingGeometry.dockTile)
                }
            }
            .frame(width: OnboardingGeometry.dockSketch.width, height: OnboardingGeometry.dockSketch.height)
            .overlay(dock.stroke(c.edgeToast.color, lineWidth: Stroke.hairline).padding(.bottom, -Stroke.hairline).clipped())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel("The Flow Bar rests just above the Dock")
    }
}

/// The hand-drawn arrow, from its SVG path (40 × 66 viewBox).
struct ArrowSketch: Shape {
    let data: String

    func path(in rect: CGRect) -> Path {
        let p = SVGPath.parse(data)
        let box = CGRect(origin: .zero, size: OnboardingGeometry.arrow)
        let s = min(rect.width / box.width, rect.height / box.height)
        return p.applying(CGAffineTransform(translationX: rect.midX - box.width * s / 2, y: rect.minY).scaledBy(x: s, y: s))
    }
}
