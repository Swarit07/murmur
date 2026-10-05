import Core
import Foundation
import Testing
@testable import UI

/// Section 8: every Flow Bar state against the token values it must use.
@Suite("Flow Bar states")
@MainActor
struct FlowBarStateTests {
    let t = Tokens.defaults

    func size(_ state: FlowBarState, hover: Bool = false) -> CGSize {
        let model = FlowBarModel()
        model.showAtAllTimes = true
        model.force(FlowBarGalleryEntry(state.name, state, hover: hover))
        return model.pillSize
    }

    /// §3.5 and §5.1: the pill's size in every state, from the tokens.
    @Test func geometryComesFromTheTokens() {
        LiveTokens.shared.reset()
        #expect(size(.hidden) == .zero)
        #expect(size(.idle) == CGSize(width: t.idleWidth, height: t.idleHeight))
        #expect(size(.idle, hover: true) == CGSize(width: t.hoverWidth, height: t.activeHeight))
        #expect(size(.listening(handsFree: false)) == CGSize(width: t.activeWidth, height: t.activeHeight))
        #expect(size(.listening(handsFree: true)) == CGSize(width: t.handsFreeWidth, height: t.activeHeight))
        #expect(size(.processing) == CGSize(width: t.activeWidth, height: t.activeHeight))
        #expect(size(.inserted) == CGSize(width: t.activeWidth, height: t.activeHeight))
        // A notice sits above the idle pill.
        for kind in FlowBarNotice.Kind.allCases where kind != .hidden {
            #expect(size(.notice(FlowBarNotice(kind: kind, message: "x"))) == CGSize(width: t.idleWidth, height: t.idleHeight))
        }
    }

    /// The measured proportions (§3.5). The brief's absolute column (68, 102 at H = 28) implies H ≈ 29
    /// for its ratio column, so the widths are checked against each other and the rest against H loosely.
    @Test func proportionsMatchTheReference() {
        let h = V1Flow.pillHeight
        #expect(abs(V1Flow.activeWidth / V1Flow.hoverWidth - 3.54 / 2.33) < 0.03)
        #expect(abs(V1Flow.buttonDiameter / h - 0.60) < 0.05)
        #expect(abs(V1Flow.buttonPadding / h - 0.19) < 0.03)
        // A silent bar is a square, so silence looks like the idle squares.
        #expect(t.waveformMinHeight == t.waveformBarWidth)
        // The idle squares and the bars share one centre area (~37 pt).
        let squares = Double(t.idleSquares - 1) * t.squarePitch + t.squareSide
        let bars = Double(t.waveformBars - 1) * (t.waveformBarWidth + t.waveformBarGap) + t.waveformBarWidth
        #expect(abs(squares - bars) < 1.5)
    }

    @Test func alertsAndToasts() {
        #expect(FlowBarNotice(kind: .transcriptionError, message: "").style == .alert)
        #expect(FlowBarNotice(kind: .noAudio, message: "").style == .alert)
        #expect(FlowBarNotice(kind: .micError, message: "").style == .alert)
        for kind in [FlowBarNotice.Kind.pasteError, .cancelled, .noTextBox, .info, .hidden, .suggestion] {
            #expect(FlowBarNotice(kind: kind, message: "").style == .toast)
        }
    }

    /// The panel is fixed at the largest state, so it never resizes while the content animates.
    @Test func canvasHoldsTheLargestState() {
        LiveTokens.shared.reset()
        let canvas = FlowBarController.canvas
        #expect(canvas.width >= t.noticeWidth + V1Flow.canvasMargin * 2)
        #expect(canvas.width >= V1Flow.toastMaxWidth + V1Flow.canvasMargin * 2)
        #expect(canvas.height >= t.activeHeight + t.tooltipGap + V1Flow.alertMaxHeight + V1Flow.canvasMargin * 2)
    }

    /// The tooltip waits for its delay and shows only over the idle pill.
    @Test func tooltipFollowsHover() async throws {
        let model = FlowBarModel()
        model.state = .idle
        model.setHovering(true)
        #expect(model.pill == .hover)
        #expect(!model.tooltipVisible)
        try await Task.sleep(for: .seconds(t.tooltipDelay + 0.2))
        #expect(model.tooltipVisible)
        model.state = .listening(handsFree: false)
        #expect(!model.tooltipVisible)
        model.state = .idle
        model.setHovering(false)
        #expect(model.pill == .idle)
        #expect(!model.tooltipVisible)
        model.shortcutLabel = "⌃ Ctrl"
        #expect(model.tooltipText == "Click or hold ⌃ Ctrl to start dictating")
    }

    /// Levels are read from the lock-protected source; nothing is pushed per buffer.
    @Test func levelsComeFromTheSource() {
        LiveTokens.shared.reset()
        let model = FlowBarModel()
        let source = MicLevelSource()
        model.levelSource = source
        #expect(model.level(at: 0) == 0)
        source.write(Float(t.waveformCeilingDb))
        #expect(model.level(at: 0) == 1)
        source.write(Float(t.waveformFloorDb))
        #expect(model.level(at: 0) == 0)
    }

    @Test func tunedTokensChangeTheBar() {
        var tuned = Tokens.defaults
        tuned.activeWidth = 150
        tuned.idleHeight = 8
        LiveTokens.shared.value = tuned
        defer { LiveTokens.shared.reset() }
        #expect(size(.processing).width == 150)
        #expect(size(.idle).height == 8)
    }

    /// The spec's state table: buttons per notice.
    @Test func noticeButtons() {
        func actions(_ kind: FlowBarNotice.Kind) -> [FlowBarNotice.Action] { FlowBarNotice(kind: kind, message: "").actions }
        #expect(actions(.pasteError) == [.dismiss])
        #expect(actions(.transcriptionError) == [.retry, .dismiss])
        #expect(actions(.micError) == [.retry, .dismiss])
        #expect(actions(.cancelled) == [.undo, .openHistory])
        #expect(actions(.noTextBox) == [.dismiss])
        #expect(actions(.hidden) == [.undo])
        #expect(actions(.suggestion) == [.add, .dismiss])
        #expect(actions(.noAudio) == [.selectMicrophone, .troubleshoot])
    }

    @Test func countdownsComeFromTheTokens() {
        LiveTokens.shared.reset()
        #expect(FlowBarNotice(kind: .cancelled, message: "").countdown == t.cancelledToastDuration)
        #expect(FlowBarNotice(kind: .noTextBox, message: "").countdown == t.noticeDuration)
        #expect(FlowBarNotice(kind: .pasteError, message: "").countdown == nil)
        #expect(FlowBarNotice(kind: .transcriptionError, message: "").countdown == nil)
    }

    @Test func hiddenForAnHourOnlyHidesTheIdleBar() {
        let model = FlowBarModel()
        model.showAtAllTimes = true
        model.hiddenUntil = Date().addingTimeInterval(3600)
        model.state = .idle
        #expect(model.displayed == .hidden)
        model.state = .listening(handsFree: false)
        #expect(model.displayed == .listening(handsFree: false))
        model.hiddenUntil = nil
        model.state = .idle
        #expect(model.displayed == .idle)
    }

    @Test func idleBarFollowsShowAtAllTimes() {
        let model = FlowBarModel()
        model.showAtAllTimes = false
        model.state = .idle
        #expect(model.displayed == .hidden)
        model.showAtAllTimes = true
        #expect(model.displayed == .idle)
    }

    @Test func savedOverridesSurviveNewTokens() throws {
        // An override saved before a token existed still loads, and keeps its value.
        let saved = try JSONSerialization.data(withJSONObject: ["activeWidth": 140.0])
        let merged = try #require(Tokens.merged(over: saved))
        #expect(merged.activeWidth == 140)
        #expect(merged.commandLight == Tokens.defaults.commandLight)
    }
}

/// §6.3: the bundled WAVs match the sound tokens (rerun Tools/make_sounds.py after changing one).
@Suite("Sound files")
struct SoundFileTests {
    @Test func wavsMatchTheTokens() throws {
        for (name, tone) in SoundFiles.all {
            let url = try #require(SoundFiles.url(name), "missing \(name).wav")
            let data = try Data(contentsOf: url)
            #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
            func u16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
            func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
            #expect(u16(22) == 1, "\(name): mono")
            #expect(u32(24) == SoundTokens.sampleRate, "\(name): sample rate")
            #expect(u16(34) == 16, "\(name): 16-bit")
            let frames = u32(40) / 2
            let expected = Int((SoundFiles.length(tone) * Double(SoundTokens.sampleRate)).rounded())
            #expect(abs(frames - expected) <= tone.notes.count, "\(name): \(frames) frames, tokens say \(expected)")
            var peak = 0
            for i in stride(from: 44, to: data.count - 1, by: 2) {
                peak = max(peak, abs(Int(Int16(bitPattern: UInt16(data[i]) | UInt16(data[i + 1]) << 8))))
            }
            let peakDb = 20 * log10(Double(peak) / 32767)
            #expect(abs(peakDb - tone.peakDb) < 0.2, "\(name): peak \(peakDb) dBFS, tokens say \(tone.peakDb)")
        }
    }
}
