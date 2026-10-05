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
        model.onAction = { [weak app] action, notice in
            guard let app else { return }
            switch action {
            case .retry:
                if notice.kind == .micError { app.controller.retryMicrophone() } else { app.controller.retryFailed() }
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
        case .micError: .micError
        }
        return FlowBarNotice(kind: kind, message: n.message)
    }
}

/// Murmur's sounds, synthesized from the sound tokens each time they change, so tuning a pitch or a
/// length in the token panel is heard on the next dictation. All original: sines with overtones,
/// a short pitch glide and an exponential fade; no recorded audio.
final class Sounds: SoundPlaying {
    @MainActor private static var cache: [String: NSSound] = [:]

    struct Note: CustomStringConvertible {
        var hz: Double
        var share: Double
        var description: String { "\(hz)/\(share)" }
    }

    @MainActor func play(_ sound: UISound) {
        let t = LiveTokens.shared.value
        if sound == .done && !t.soundDoneEnabled { return }
        let notes: [Note], length: Double, volume: Double, glide: Double
        switch sound {
        case .start:
            notes = [Note(hz: t.soundStartPitchLow, share: 0.42), Note(hz: t.soundStartPitchHigh, share: 0.58)]
            length = t.soundStartLength; volume = t.soundVolume; glide = t.soundGlide
        case .stop:
            notes = [Note(hz: t.soundStopPitchHigh, share: 0.42), Note(hz: t.soundStopPitchLow, share: 0.58)]
            length = t.soundStopLength; volume = t.soundVolume; glide = -t.soundGlide
        case .done:
            // The second note overlaps the first's tail, which is what makes a chime ring.
            notes = [Note(hz: t.soundDonePitchLow, share: 0.35), Note(hz: t.soundDonePitchHigh, share: 0.65)]
            length = t.soundDoneLength; volume = t.soundDoneVolume; glide = 0
        case .error:
            notes = [Note(hz: t.soundErrorPitchHigh, share: 0.4), Note(hz: t.soundErrorPitchLow, share: 0.6)]
            length = t.soundErrorLength; volume = t.soundVolume; glide = -t.soundGlide / 2
        }
        let overlap = sound == .done
        let key = "\(sound)-\(notes)-\(length)-\(volume)-\(glide)-\(t.soundBrightness)-\(t.soundBellness)-\(t.soundAttack)"
        if Self.cache[key] == nil {
            let samples = Self.render(notes: notes, length: length, volume: volume, glide: glide,
                                      brightness: t.soundBrightness, bellness: t.soundBellness, attack: t.soundAttack, overlap: overlap)
            Self.cache[key] = NSSound(data: Self.wav(samples))
        }
        Self.cache[key]?.stop()
        Self.cache[key]?.play()
    }

    static let rate = 44_100.0

    static func render(notes: [Note], length: Double, volume: Double, glide: Double, brightness: Double,
                       bellness: Double, attack: Double, overlap: Bool) -> [Float] {
        let total = Int(length * rate)
        var out = [Float](repeating: 0, count: total + Int(0.05 * rate))
        var start = 0
        // Overtones: ratio drifts from an exact harmonic toward a bell's inharmonic partials.
        let partials: [(ratio: Double, amp: Double, decay: Double)] = [
            (1, 1, 1),
            (2 + 0.76 * bellness, 0.6 * brightness, 2.2),
            (3 + 2.2 * bellness, 0.35 * brightness, 3.5),
            (4.2 + 1.2 * bellness, 0.18 * brightness, 5),
        ]
        for (index, note) in notes.enumerated() {
            let n = Int(length * note.share * rate)
            // With overlap, each note rings past its slot; without, they follow each other.
            let ring = overlap ? Int(Double(n) * (index == notes.count - 1 ? 1 : 2.2)) : n
            var phases = [Double](repeating: 0, count: partials.count)
            for k in 0..<ring where start + k < out.count {
                let x = Double(k) / Double(max(ring, 1))
                let hz = note.hz * (1 + glide * min(1, Double(k) / (0.04 * rate)))
                let env = min(1, Double(k) / max(1, attack * rate)) * exp(-4.5 * x)
                var v = 0.0
                for (p, partial) in partials.enumerated() {
                    phases[p] += 2 * .pi * hz * partial.ratio / rate
                    v += sin(phases[p]) * partial.amp * exp(-4.5 * x * (partial.decay - 1))
                }
                out[start + k] += Float(v * env * volume / 1.6)
            }
            start += n
        }
        return out.map { max(-1, min(1, $0)) }
    }

    static func wav(_ samples: [Float]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16(s * 32_000))) }
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
