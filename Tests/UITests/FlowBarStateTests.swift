import Foundation
import Testing
@testable import UI

/// Section 8: every Flow Bar state against the token values it must use.
@Suite("Flow Bar states")
@MainActor
struct FlowBarStateTests {
    let t = Tokens.defaults

    func size(_ state: FlowBarState) -> CGSize {
        let model = FlowBarModel()
        model.showAtAllTimes = true
        model.forced = state
        defer { model.forced = nil }
        return model.barSize
    }

    @Test func geometryComesFromTheTokens() {
        LiveTokens.shared.reset()
        #expect(size(.hidden) == .zero)
        #expect(size(.idle) == CGSize(width: t.idleWidth, height: t.idleHeight))
        #expect(size(.listening(handsFree: false)) == CGSize(width: t.activeWidth, height: t.activeHeight))
        #expect(size(.listening(handsFree: true)) == CGSize(width: t.handsFreeWidth, height: t.activeHeight))
        #expect(size(.processing) == CGSize(width: t.activeWidth, height: t.activeHeight))
        #expect(size(.inserted) == CGSize(width: t.activeWidth, height: t.activeHeight))
        for kind in FlowBarNotice.Kind.allCases {
            #expect(size(.notice(FlowBarNotice(kind: kind, message: "x"))) == CGSize(width: t.noticeWidth, height: t.noticeHeight))
        }
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
