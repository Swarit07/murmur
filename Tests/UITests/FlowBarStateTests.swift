import AppKit
import Core
import Foundation
import SwiftUI
import Testing
@testable import UI

/// §8 and UI_REDESIGN.md v2 §5.1: every Flow Bar state against the board values it must use.
@Suite("Flow Bar states")
@MainActor
struct FlowBarStateTests {
    let t = Tokens.defaults

    func model(_ state: FlowBarState, hover: Bool = false, elapsed: TimeInterval? = nil, words: Int? = nil) -> FlowBarModel {
        let model = FlowBarModel()
        model.showAtAllTimes = true
        model.force(FlowBarGalleryEntry(state.name, state, hover: hover, elapsed: elapsed, words: words))
        return model
    }

    func size(_ state: FlowBarState, hover: Bool = false, timer: Bool = false) -> CGSize {
        let m = model(state, hover: hover)
        return FlowMetrics.size(m.surface, model: m, timer: timer)
    }

    /// §3.5: the board's sizes, from the tokens.
    @Test func pillSizesMatchTheBoard() {
        LiveTokens.shared.reset()
        #expect(size(.hidden) == .zero)
        #expect(size(.idle) == CGSize(width: 52, height: 12))
        #expect(size(.idle, hover: true) == CGSize(width: 76, height: 28))
        // Hold: padding 16, a 6 pt live dot, gap 10, a 112 pt wave, padding 16.
        #expect(size(.listening(handsFree: false)) == CGSize(width: 160, height: 36))
        // Hands-free: padding 6, two 24 pt buttons, a 96 pt wave, gaps of 10; the timer adds a column.
        #expect(size(.listening(handsFree: true)) == CGSize(width: 176, height: 36))
        #expect(size(.listening(handsFree: true), timer: true).width == 176 + 10 + FlowGeometry.timerWidth)
        #expect(size(.processing) == CGSize(width: 144, height: 36))
    }

    @Test func cardsMatchTheBoard() {
        LiveTokens.shared.reset()
        FontRegistry.registerBundledFonts()
        let noAudio = size(.notice(FlowBarNotice(kind: .noAudio, message: "")))
        #expect(noAudio.width == 276)
        #expect(size(.notice(FlowBarNotice(kind: .pasteError, message: ""))).height == 40)
        #expect(size(.notice(FlowBarNotice(kind: .cancelled, message: ""))).height == 42)
        // Every card fits the panel's fixed canvas, so the window never resizes.
        let canvas = FlowBarController.canvas
        for entry in FlowBarState.gallery {
            let m = model(entry.state, hover: entry.hover, words: entry.words)
            let s = FlowMetrics.size(m.surface, model: m, timer: true)
            #expect(s.width + FlowGeometry.canvasMargin * 2 <= canvas.width, "\(entry.name) is \(s.width) wide")
            #expect(s.height + FlowGeometry.canvasMargin * 2 <= canvas.height, "\(entry.name) is \(s.height) high")
        }
    }

    @Test func tunedTokensChangeTheBar() {
        var tuned = Tokens.defaults
        tuned.processingWidth = 150
        tuned.idleHeight = 8
        LiveTokens.shared.value = tuned
        defer { LiveTokens.shared.reset() }
        #expect(size(.processing).width == 150)
        #expect(size(.idle).height == 8)
    }

    /// §5.1: buttons per notice, primary first.
    @Test func noticeButtons() {
        func actions(_ kind: FlowBarNotice.Kind) -> [FlowBarNotice.Action] { FlowBarNotice(kind: kind, message: "").actions }
        #expect(actions(.cancelled) == [.undo, .openHistory])
        #expect(actions(.pasteError) == [])
        #expect(actions(.transcriptionError) == [.retry])
        #expect(actions(.noTextBox) == [.dismiss])
        #expect(actions(.noAudio) == [.switchMicrophone, .testMic])
        #expect(actions(.hidden) == [.undo])
        #expect(actions(.suggestion) == [.add, .dismiss])
    }

    /// §5.1 timings: cancelled 5 s with a ring, paste error 4 s, alerts sticky 8 s, no text box until
    /// dismissed.
    @Test func countdownsComeFromTheTokens() {
        LiveTokens.shared.reset()
        #expect(FlowBarNotice(kind: .cancelled, message: "").countdown == 5)
        #expect(FlowBarNotice(kind: .cancelled, message: "").showsRing)
        #expect(FlowBarNotice(kind: .pasteError, message: "").countdown == 4)
        #expect(FlowBarNotice(kind: .transcriptionError, message: "").countdown == 8)
        #expect(FlowBarNotice(kind: .noAudio, message: "").countdown == 8)
        #expect(FlowBarNotice(kind: .noTextBox, message: "").countdown == nil)
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

    /// The tooltip waits for its delay, shows only over the idle pill, and names the user's key.
    @Test func tooltipFollowsHover() async throws {
        LiveTokens.shared.reset()
        let model = FlowBarModel()
        model.state = .idle
        model.setHovering(true)
        #expect(model.surface == .hover)
        #expect(!model.tooltipVisible)
        try await Task.sleep(for: .seconds(t.tooltipDelay + 0.2))
        #expect(model.tooltipVisible)
        model.state = .listening(handsFree: false)
        #expect(!model.tooltipVisible)
        model.state = .idle
        model.setHovering(false)
        #expect(model.surface == .idle)
        model.shortcutLabel = "⌃ Ctrl"
        #expect(model.tooltipText == "Hold ⌃ Ctrl to dictate")
    }

    /// §6.1 `bar.idleFade`: the idle pill fades after a quiet spell, and hovering brings it back.
    @Test func idlePillFades() async throws {
        var tuned = Tokens.defaults
        tuned.idleFadeDelay = 0.2
        LiveTokens.shared.value = tuned
        defer { LiveTokens.shared.reset() }
        let model = FlowBarModel()
        model.state = .listening(handsFree: false)
        model.state = .idle
        #expect(!model.idleFaded)
        try await Task.sleep(for: .seconds(0.5))
        #expect(model.idleFaded)
        model.setHovering(true)
        #expect(!model.idleFaded)
    }

    /// The hands-free timer appears after 3 s.
    @Test func handsFreeTimerAppearsLater() {
        LiveTokens.shared.reset()
        let early = model(.listening(handsFree: true), elapsed: 1)
        #expect(!early.timerVisible(at: Date()))
        let later = model(.listening(handsFree: true), elapsed: 7)
        #expect(later.timerVisible(at: Date()))
        #expect(FlowTimer.text(7) == "0:07")
        #expect(FlowTimer.text(312) == "5:12")
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

    /// §6.2: silence is the 0.7 pt hairline; full level stays inside the frame.
    @Test func waveShape() {
        let silent = FlowWave.path(width: 112, height: 22, time: 3, level: 0).boundingRect
        #expect(abs(silent.height - WaveTokens.hairline * 2) < 0.01)
        let loud = FlowWave.path(width: 112, height: 22, time: 3, level: 1).boundingRect
        #expect(loud.minY >= 0 && loud.maxY <= 22)
        #expect(loud.height > 10)
    }

    @Test func savedOverridesSurviveNewTokens() throws {
        // An override saved before a token existed still loads, and keeps its value.
        let saved = try JSONSerialization.data(withJSONObject: ["processingWidth": 140.0])
        let merged = try #require(Tokens.merged(over: saved))
        #expect(merged.processingWidth == 140)
        #expect(merged.liveLight == Tokens.defaults.liveLight)
    }
}

/// §6.3: the bundled WAVs match the sound tokens (rerun Tools/make_sounds.py after changing one).
/// Regression: ISSUE-005, found by /qa on 2026-10-05. After a dictation the controller's phase stays
/// "inserted"; a redraw after the check's moment (a forced notice clearing) showed a stale check that
/// ignored clicks, so click-to-start hands-free did nothing until the next dictation.
@Suite("Flow Bar inserted state")
@MainActor
struct FlowBarInsertedTests {
    @Test func staleInsertedRedrawsAsIdle() {
        let model = FlowBarModel()
        model.showAtAllTimes = true
        model.state = .inserted
        #expect(model.displayed == .inserted)
        model.insertedSettled = true  // the check's moment has passed
        model.forced = .notice(FlowBarNotice(kind: .info, message: "Focus test starts in 2 seconds"))
        model.forced = nil
        #expect(model.displayed == .idle)
    }

    @Test func freshInsertedStillShowsTheCheck() {
        let model = FlowBarModel()
        model.showAtAllTimes = true
        model.state = .inserted
        model.forced = .notice(FlowBarNotice(kind: .info, message: "x"))
        model.forced = nil
        #expect(model.displayed == .inserted)
    }

    @Test func nextDictationShowsTheCheckAgain() {
        let model = FlowBarModel()
        model.showAtAllTimes = true
        model.state = .inserted
        model.insertedSettled = true
        model.state = .processing
        model.state = .inserted
        #expect(model.displayed == .inserted)
    }
}

/// A saved drag offset (from another display, or a drag past the edge) can never put the bar off screen.
@Suite("Flow Bar placement")
@MainActor
struct FlowBarPlacementTests {
    let visible = NSRect(x: 0, y: 0, width: 1512, height: 949)
    let canvas = FlowBarController.canvas
    var base: NSPoint { NSPoint(x: visible.midX, y: visible.minY + LiveTokens.shared.value.bottomMargin) }

    @Test func offScreenOffsetIsPulledBack() {
        // The offset that hid the bar on a 1512 × 982 MacBook screen (320 pt below its resting place).
        let o = FlowBarController.clamp(CGSize(width: 87.5, height: -319.9), base: base, visible: visible, canvas: canvas)
        #expect(o.width == 87.5)
        #expect(o.height == 0)
    }

    @Test func staysInsideEveryEdge() {
        for drag in [CGSize(width: -5000, height: 0), CGSize(width: 5000, height: 0), CGSize(width: 0, height: 5000)] {
            let o = FlowBarController.clamp(drag, base: base, visible: visible, canvas: canvas)
            let x = base.x + o.width, y = base.y + o.height
            #expect(x - canvas.width / 2 >= visible.minX)
            #expect(x + canvas.width / 2 <= visible.maxX)
            #expect(y + canvas.height - FlowGeometry.canvasMargin <= visible.maxY)
        }
    }

    @Test func ordinaryDragIsKept() {
        let o = FlowBarController.clamp(CGSize(width: -120, height: 40), base: base, visible: visible, canvas: canvas)
        #expect(o == CGSize(width: -120, height: 40))
    }
}

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
