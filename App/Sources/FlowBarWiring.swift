import AppKit
import HubUI
import MurmurKit
import SwiftUI

/// Maps the dictation controller onto the Flow Bar and the bar's buttons back onto the controller.
@MainActor
final class FlowBarWiring {
    let model = FlowBarModel()
    let bar: FlowBarController
    unowned let app: AppDelegate
    private var lastPhase: DictationStatus.Phase?

    init(app: AppDelegate) {
        self.app = app
        bar = FlowBarController(model: model)
        model.showAtAllTimes = AppSettings.shared.showFlowBar
        model.levelSource = app.controller.micLevel
        model.shortcutLabel = Self.shortcutLabel(DictationController.shortcutConfiguration(.shared).pushToTalk)

        model.onClick = { [weak app] in app?.controller.toggleHandsFree() }
        model.onStop = { [weak app] in app?.controller.stopHandsFree() }
        model.onCancel = { [weak app] in app?.controller.cancelCurrent() }
        model.onAction = { [weak self, weak app] action, notice in
            guard let app else { return }
            switch action {
            case .retry:
                if notice.kind == .micError { app.controller.retryMicrophone() } else { app.controller.retryFailed() }
            case .undo:
                if notice.kind == .hidden {
                    self?.bar.unhide()
                    app.controller.clearMessage()
                } else {
                    app.controller.undoCancel()
                }
            case .add: app.controller.acceptSuggestion()
            case .openHistory:
                app.controller.clearMessage()
                app.showHistory()
            case .dismiss:
                if notice.kind == .suggestion { app.controller.dismissSuggestion() } else { app.controller.clearMessage() }
            case .pasteLast: app.controller.pasteLast()
            case .switchMicrophone, .testMic:
                // Both open the microphone settings, where the device picker and the level meter live.
                app.controller.clearMessage()
                app.showSettings()
            }
        }
        model.onMenu = { [weak self, weak app] item in
            guard let self, let app else { return }
            switch item {
            case .startHandsFree: app.controller.toggleHandsFree()
            case .pasteLast: app.controller.pasteLast()
            case .hideForHour:
                self.bar.hide(for: 3600)
                app.controller.notice("Flow Bar hidden for an hour.", kind: .flowBarHidden)
            case .resetPosition: self.bar.resetPosition()
            case .settings: app.showSettings()
            }
        }
        NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] note in
            let key = note.object as? String
            MainActor.assumeIsolated {
                if key == "showFlowBar" { self?.model.showAtAllTimes = AppSettings.shared.showFlowBar }
                if key == "shortcuts" {
                    self?.model.shortcutLabel = Self.shortcutLabel(DictationController.shortcutConfiguration(.shared).pushToTalk)
                }
            }
        }
    }

    func render(_ status: DictationStatus) {
        if case .recording = status.phase, lastPhase.map({ if case .recording = $0 { false } else { true } }) ?? true {
            // The bar follows the window you dictate into.
            bar.followFocusedScreen()
        }
        lastPhase = status.phase
        model.command = status.command
        if status.phase == .inserted {
            // "Inserted · 24 words": a count only; the text itself never leaves the controller's status.
            model.insertedWords = status.lastTranscript.map { $0.split(whereSeparator: \.isWhitespace).count }
        }
        if status.notice != nil { model.microphoneName = app.controller.microphoneName }
        model.state = Self.state(for: status)
    }

    static func state(for status: DictationStatus) -> FlowBarState {
        switch status.phase {
        case .recording(let handsFree): return .listening(handsFree: handsFree)
        case .processing: return .processing
        case .inserted: return status.notice.map { .notice(flowNotice($0)) } ?? .inserted
        case .loading, .idle, .error:
            if let n = status.notice { return .notice(flowNotice(n)) }
            return .idle
        }
    }

    /// The push-to-talk shortcut as the tooltip names it: symbol and name for a single modifier
    /// ("⌃ Ctrl"), the recorder's display name otherwise.
    static func shortcutLabel(_ shortcut: Shortcut) -> String {
        guard case .modifiers(let mods) = shortcut, mods.count == 1, let key = mods.first else { return shortcut.displayName }
        return switch key {
        case .fn: "fn"
        case .control: "\(key.symbol) Ctrl"
        case .option: "\(key.symbol) Option"
        case .command: "\(key.symbol) Cmd"
        case .shift: "\(key.symbol) Shift"
        }
    }

    static func flowNotice(_ n: DictationStatus.Notice) -> FlowBarNotice {
        let kind: FlowBarNotice.Kind = switch n.kind {
        case .pasteError: .pasteError
        case .transcriptionError: .transcriptionError
        case .noTextBox: .noTextBox
        case .cancelled: .cancelled
        case .info: .info
        case .micError: .micError
        case .flowBarHidden: .hidden
        case .suggestion: .suggestion
        case .noAudio: .noAudio
        }
        return FlowBarNotice(kind: kind, message: n.message)
    }
}

/// Murmur's sounds: the WAVs `Tools/make_sounds.py` synthesizes from the sound tokens (§6.3), loaded
/// once and replayed. All original; no recorded audio.
final class Sounds: SoundPlaying {
    @MainActor private static var cache: [UISound: NSSound] = [:]

    @MainActor func play(_ sound: UISound) {
        if Self.cache[sound] == nil, let url = SoundFiles.url(sound.rawValue) {
            Self.cache[sound] = NSSound(contentsOf: url, byReference: true)
        }
        Self.cache[sound]?.stop()
        Self.cache[sound]?.play()
    }
}

// MARK: - Focus test (M2 gate: the bar never takes focus in 50 trials)

/// Clicks the bar 50 times with synthetic mouse events while a text field elsewhere has focus, and
/// checks after every click that the same app and element still have focus and Murmur never activated.
@MainActor
final class FocusTest {
    let bar: FlowBarController
    let controller: DictationController
    var running = false

    init(bar: FlowBarController, controller: DictationController) {
        self.bar = bar
        self.controller = controller
    }

    func run(trials: Int = 50, delay: Double = 5, report: @escaping (String) -> Void) {
        guard !running else { return }
        running = true
        Task {
            report("Focus test starts in \(Int(delay)) seconds: click into a text field (TextEdit or Notes) and leave the mouse alone.")
            try? await Task.sleep(for: .seconds(delay))
            let original = NSEvent.mouseLocation
            // Fifty start sounds would be noise; the test is about focus.
            let soundsWere = AppSettings.shared.soundsEnabled
            AppSettings.shared.soundsEnabled = false
            defer { AppSettings.shared.soundsEnabled = soundsWere }
            // Clear the "starts in N seconds" message: a click on a notice card rightly starts nothing.
            bar.model.forced = nil
            try? await Task.sleep(for: .milliseconds(300))
            let target = FocusContext.snapshot()
            let tapsBefore = bar.model.taps
            var failures: [String] = []
            var started = 0
            var misses: [String] = []
            for trial in 1...trials {
                let before = FocusContext.snapshot()
                let shown = bar.model.displayed.name
                let tapsAtStart = bar.model.taps
                let point = bar.barCenter
                move(to: point)
                try? await Task.sleep(for: .milliseconds(60))
                bar.refreshMouseHandling()
                click(at: point)
                try? await Task.sleep(for: .milliseconds(350))
                let during = FocusContext.snapshot()
                let murmurActive = NSApp.isActive
                if controller.isRecording {
                    started += 1
                } else {
                    misses.append("trial \(trial): bar showed \(shown), tap \(bar.model.taps > tapsAtStart ? "received" : "not received"), refused: \(controller.lastBeginRefusal ?? "no reason recorded")")
                }
                controller.discardCurrent()
                try? await Task.sleep(for: .milliseconds(200))
                let after = FocusContext.snapshot()
                if murmurActive || !before.sameFocus(as: during) || !before.sameFocus(as: after) {
                    failures.append("trial \(trial): before \(before.description), during \(during.description), after \(after.description)\(murmurActive ? ", Murmur became active" : "")")
                }
            }
            move(to: original)
            running = false
            let taps = bar.model.taps - tapsBefore
            let line = "Focus test: \(trials - failures.count)/\(trials) kept focus in \(target.appName ?? "?"); \(taps)/\(trials) clicks reached the bar; \(started)/\(trials) started hands-free."
            let log = ([line, "target: \(target.description)"] + failures + misses).joined(separator: "\n")
            let url = MurmurPaths.appSupport.appendingPathComponent("focus-test-\(Int(Date().timeIntervalSince1970)).txt")
            try? log.write(to: url, atomically: true, encoding: .utf8)
            report(failures.isEmpty ? "\(line) Pass." : "\(line) Details: \(url.path)")
        }
    }

    func move(to point: NSPoint) {
        let flipped = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: flipped, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// A left click at a screen point (AppKit coordinates).
    func click(at point: NSPoint) {
        let flipped = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        let source = CGEventSource(stateID: .hidSystemState)
        // A real single click carries click state 1; without it AppKit reports clickCount 0 and a tap
        // gesture does not fire.
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: flipped, mouseButton: .left)
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            event?.post(tap: .cghidEventTap)
            if type == .leftMouseDown { usleep(40_000) }
        }
    }
}
