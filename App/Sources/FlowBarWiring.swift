import AppKit
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

        model.onClick = { [weak app] in app?.controller.toggleHandsFree() }
        model.onStop = { [weak app] in app?.controller.stopHandsFree() }
        model.onCancel = { [weak app] in app?.controller.cancelCurrent() }
        model.onAction = { [weak app] action, _ in
            guard let app else { return }
            switch action {
            case .retry: app.controller.retryFailed()
            case .undo: app.controller.undoCancel()
            case .openHistory:
                app.controller.clearMessage()
                app.showHistory()
            case .dismiss: app.controller.clearMessage()
            case .pasteLast: app.controller.pasteLast()
            }
        }
        model.onMenu = { [weak self, weak app] item in
            guard let self, let app else { return }
            switch item {
            case .pasteLast: app.controller.pasteLast()
            case .copyLast: app.controller.copyLast()
            case .hideForHour: self.bar.hide(for: 3600)
            case .resetPosition: self.bar.resetPosition()
            case .openHistory: app.showHistory()
            case .settings: app.showSettings()
            }
        }
        NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] note in
            let key = note.object as? String
            MainActor.assumeIsolated {
                if key == "showFlowBar" { self?.model.showAtAllTimes = AppSettings.shared.showFlowBar }
            }
        }
    }

    func render(_ status: DictationStatus) {
        if case .recording = status.phase, lastPhase.map({ if case .recording = $0 { false } else { true } }) ?? true {
            // The bar follows the window you dictate into.
            bar.followFocusedScreen()
        }
        lastPhase = status.phase
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

    static func flowNotice(_ n: DictationStatus.Notice) -> FlowBarNotice {
        let kind: FlowBarNotice.Kind = switch n.kind {
        case .pasteError: .pasteError
        case .transcriptionError: .transcriptionError
        case .noTextBox: .noTextBox
        case .cancelled: .cancelled
        case .info: .info
        }
        return FlowBarNotice(kind: kind, message: n.message)
    }
}

/// Murmur's sounds, synthesized from the sound tokens each time they change, so tuning a pitch or a
/// length in the token panel is heard on the next dictation.
final class Sounds: SoundPlaying {
    @MainActor private static var cache: [String: NSSound] = [:]

    @MainActor func play(_ sound: UISound) {
        let t = LiveTokens.shared.value
        let tones: [(Double, Double)]
        let length: Double
        switch sound {
        case .start: tones = [(t.soundStartPitchLow, 0.45), (t.soundStartPitchHigh, 0.55)]; length = t.soundStartLength
        case .stop: tones = [(t.soundStopPitchHigh, 0.45), (t.soundStopPitchLow, 0.55)]; length = t.soundStopLength
        case .error: tones = [(t.soundErrorPitchHigh, 0.4), (t.soundErrorPitchLow, 0.6)]; length = t.soundErrorLength
        }
        let key = "\(sound)-\(tones)-\(length)-\(t.soundVolume)"
        if Self.cache[key] == nil {
            Self.cache[key] = NSSound(data: Self.wav(tones: tones, length: length, volume: t.soundVolume))
        }
        Self.cache[key]?.stop()
        Self.cache[key]?.play()
    }

    /// Two short sine tones with a soft octave partial, fast attack and exponential release.
    static func wav(tones: [(hz: Double, share: Double)], length: Double, volume: Double, rate: Double = 44_100) -> Data {
        var samples: [Int16] = []
        let gap = 0.012
        for (index, tone) in tones.enumerated() {
            let n = Int(max(0.01, length * tone.share - gap) * rate)
            for k in 0..<n {
                let time = Double(k) / rate
                let attack = min(1, Double(k) / (0.004 * rate))
                let release = exp(-5 * Double(k) / Double(n))
                let wave = sin(2 * .pi * tone.hz * time) + 0.25 * sin(4 * .pi * tone.hz * time)
                samples.append(Int16(max(-1, min(1, wave * attack * release * volume / 1.25)) * 32_000))
            }
            if index < tones.count - 1 { samples += [Int16](repeating: 0, count: Int(gap * rate)) }
        }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: s)) }
        return d
    }
}

// MARK: - Token panel

/// Shows every token live and lets numbers and colors be edited while watching the bar. "Copy as
/// Swift" puts the current values on the clipboard for pasting into Tokens.swift.
struct TokenPanel: View {
    @State private var rows: [(key: String, value: String)] = TokenPanel.rows()
    @State private var filter = ""

    static func rows() -> [(key: String, value: String)] {
        guard let data = try? JSONEncoder().encode(LiveTokens.shared.value),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let order = Mirror(reflecting: LiveTokens.shared.value).children.compactMap(\.label)
        return order.compactMap { key in dict[key].map { (key, "\($0)") } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder)
                Button("Copy as Swift") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(LiveTokens.shared.swiftSource, forType: .string)
                }
                Button("Reset") {
                    LiveTokens.shared.reset()
                    rows = Self.rows()
                }
            }
            .padding(10)
            List {
                ForEach(rows.indices.filter { filter.isEmpty || rows[$0].key.localizedCaseInsensitiveContains(filter) }, id: \.self) { i in
                    HStack {
                        Text(rows[i].key).font(.system(.body, design: .monospaced))
                        Spacer()
                        TextField("", text: Binding(get: { rows[i].value }, set: { rows[i].value = $0 }))
                            .frame(width: 140)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { apply(i) }
                    }
                }
            }
        }
    }

    /// Writes one edited value back through JSON, so types follow the Tokens struct.
    func apply(_ i: Int) {
        guard let data = try? JSONEncoder().encode(LiveTokens.shared.value),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let key = rows[i].key, text = rows[i].value
        switch dict[key] {
        case is Bool: dict[key] = text.lowercased() == "true"
        case is NSNumber: dict[key] = Double(text) ?? dict[key]
        default: dict[key] = text
        }
        if let updated = try? JSONSerialization.data(withJSONObject: dict), let tokens = try? JSONDecoder().decode(Tokens.self, from: updated) {
            LiveTokens.shared.value = tokens
        }
        rows = Self.rows()
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

    func run(trials: Int = 50, report: @escaping (String) -> Void) {
        guard !running else { return }
        running = true
        Task {
            report("Focus test starts in 5 seconds: click into a text field (TextEdit or Notes) and leave the mouse alone.")
            try? await Task.sleep(for: .seconds(5))
            let original = NSEvent.mouseLocation
            var failures: [String] = []
            for trial in 1...trials {
                let before = FocusContext.snapshot()
                click(at: bar.barCenter)
                try? await Task.sleep(for: .milliseconds(350))
                let during = FocusContext.snapshot()
                let murmurActive = NSApp.isActive
                controller.discardCurrent()
                try? await Task.sleep(for: .milliseconds(200))
                let after = FocusContext.snapshot()
                if murmurActive || !before.sameFocus(as: during) || !before.sameFocus(as: after) {
                    failures.append("trial \(trial): before \(before.description), during \(during.description), after \(after.description)\(murmurActive ? ", Murmur became active" : "")")
                }
            }
            CGWarpMouseCursorPosition(CGPoint(x: original.x, y: (NSScreen.screens.first?.frame.height ?? 0) - original.y))
            running = false
            let line = "Focus test: \(trials - failures.count)/\(trials) kept focus."
            let log = ([line] + failures).joined(separator: "\n")
            let url = MurmurPaths.appSupport.appendingPathComponent("focus-test-\(Int(Date().timeIntervalSince1970)).txt")
            try? log.write(to: url, atomically: true, encoding: .utf8)
            report(failures.isEmpty ? "\(line) Pass." : "\(line) Details: \(url.path)")
        }
    }

    /// A left click at a screen point (AppKit coordinates).
    func click(at point: NSPoint) {
        let flipped = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: flipped, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: flipped, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: flipped, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}
