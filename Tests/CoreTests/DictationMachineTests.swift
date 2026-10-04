@testable import Core
import Testing

@Suite("Dictation state machine")
struct DictationMachineTests {
    typealias M = DictationMachine

    @Test func holdHappyPath() {
        var s = DictationState.idle
        s = M.next(s, on: .start(.hold))!
        #expect(s == .recording(.hold))
        s = M.next(s, on: .stop)!
        #expect(s == .transcribing)
        s = M.next(s, on: .transcribed("hello"))!
        #expect(s == .cleaning)
        s = M.next(s, on: .cleaned("Hello."))!
        #expect(s == .inserting)
        s = M.next(s, on: .inserted)!
        #expect(s == .idle)
    }

    @Test func handsFreeStarts() {
        #expect(M.next(.idle, on: .start(.handsFree)) == .recording(.handsFree))
        #expect(M.next(.idle, on: .start(.command)) == .recording(.command))
    }

    @Test(arguments: [DictationState.recording(.hold), .recording(.handsFree), .transcribing, .cleaning])
    func cancelFromCancellableStates(_ state: DictationState) {
        #expect(M.next(state, on: .cancel) == .cancelled)
    }

    @Test(arguments: [DictationState.idle, .inserting, .cancelled, .error(.pasteFailed, text: "x")])
    func cancelIgnoredElsewhere(_ state: DictationState) {
        #expect(M.next(state, on: .cancel) == nil)
    }

    @Test(arguments: [
        DictationState.recording(.hold), .recording(.handsFree), .transcribing, .cleaning, .inserting,
        .cancelled, .error(.transcriptionFailed, text: nil),
    ])
    func startIgnoredWhileBusy(_ state: DictationState) {
        #expect(M.next(state, on: .start(.hold)) == nil)
        #expect(M.next(state, on: .start(.handsFree)) == nil)
    }

    @Test func shortOrSilentClipReturnsToIdle() {
        #expect(M.next(.recording(.hold), on: .discard) == .idle)
        #expect(M.next(.transcribing, on: .discard) == .idle)
    }

    @Test func transcriptionFailureKeepsState() {
        #expect(M.next(.transcribing, on: .transcriptionFailed) == .error(.transcriptionFailed, text: nil))
    }

    @Test func insertionFailuresKeepText() {
        #expect(M.next(.inserting, on: .insertionFailed(.pasteFailed, text: "Keep me")) == .error(.pasteFailed, text: "Keep me"))
        #expect(M.next(.inserting, on: .insertionFailed(.noTextBox, text: "Keep me")) == .error(.noTextBox, text: "Keep me"))
    }

    @Test func dismissReturnsToIdle() {
        #expect(M.next(.cancelled, on: .dismiss) == .idle)
        #expect(M.next(.error(.pasteFailed, text: "x"), on: .dismiss) == .idle)
        #expect(M.next(.idle, on: .dismiss) == nil)
    }

    @Test func outOfOrderEventsIgnored() {
        #expect(M.next(.idle, on: .stop) == nil)
        #expect(M.next(.idle, on: .transcribed("x")) == nil)
        #expect(M.next(.recording(.hold), on: .cleaned("x")) == nil)
        #expect(M.next(.cleaning, on: .inserted) == nil)
        #expect(M.next(.transcribing, on: .stop) == nil)
    }

    @Test func holderIgnoresBusyPress() {
        let holder = DictationStateHolder()
        #expect(holder.send(.start(.hold)) == .recording(.hold))
        #expect(holder.send(.start(.hold)) == nil)
        #expect(holder.state == .recording(.hold))
    }
}
