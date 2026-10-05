import AppKit
import SwiftUI

/// The Flow Bar's content (UI_REDESIGN.md v2 §5.1). It fills the panel's fixed canvas: one surface sits
/// at the bottom centre and morphs (width spring, bottom-anchored) between the pill's states and the
/// cards that replace it; the tooltip sits above the hovered pill. Colors follow the **system**
/// appearance (the panel sets it); text ignores the Hub's text size.
public struct FlowBarView: View {
    let model: FlowBarModel

    public init(model: FlowBarModel) {
        self.model = model
    }

    public var body: some View {
        ThemeProvider {
            FlowBarCanvas(model: model)
                .transformEnvironment(\.theme) { $0.textScale = TypeTokens.scaleDefault }
        }
    }
}

/// Live colors from the tokens, picked by the panel's appearance.
struct FlowPalette {
    let t: Tokens
    let increaseContrast: Bool

    var fill: Color { .token(t.fillLight, t.fillDark) }
    var ring: Color { increaseContrast ? FlowBarColors.light.increasedContrast.flowRing.color : .token(t.ringLight, t.ringDark) }
    var text: Color { .token(t.textLight, t.textDark) }
    var secondary: Color { .token(t.secondaryTextLight, t.secondaryTextDark) }
    var idleMark: Color { .token(t.idleMarkLight, t.idleMarkDark) }
    var live: Color { .token(t.liveLight, t.liveDark) }
    var stopGlyph: Color { .token(t.stopGlyphLight, t.stopGlyphDark) }
    var cancel: Color { .token(t.cancelLight, t.cancelDark) }
    var button: Color { .token(t.buttonLight, t.buttonDark) }
    var buttonText: Color { .token(t.buttonTextLight, t.buttonTextDark) }
    var buttonRing: Color { .token(t.buttonRingLight, t.buttonRingDark) }
    var keyRing: Color { .token(t.keyRingLight, t.keyRingDark) }
    var keyBottom: Color { .token(t.keyBottomLight, t.keyBottomDark) }
    var timer: Color { .token(t.timerLight, t.timerDark) }
    var stillWave: Color { .token(t.stillWaveLight, t.stillWaveDark) }
}

struct FlowBarCanvas: View {
    let model: FlowBarModel
    @Environment(\.theme) private var theme

    var body: some View {
        let t = LiveTokens.shared.value
        let motion = theme.motion
        VStack(spacing: t.tooltipGap) {
            Spacer(minLength: 0)
            if model.tooltipVisible {
                FlowTooltip(text: "Hold", key: model.shortcutLabel, trail: "to dictate")
                    .transition(.asymmetric(insertion: .opacity.animation(motion.easeOut(MotionTokens.hover)),
                                            removal: .opacity.animation(motion.easeIn(MotionTokens.tooltipOut))))
            }
            if model.surface != .none {
                FlowSurfaceView(model: model)
                    .transition(.opacity.animation(motion.easeOut(MotionTokens.hover)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, FlowGeometry.canvasMargin)
        .animation(motion.easeOut(MotionTokens.hover), value: model.tooltipVisible)
    }
}

// MARK: - Measurement

/// The surface's size in every state, computed from the tokens and the measured text, so the shape can
/// spring to its new size before the content lays out, and the panel can hit-test it exactly.
@MainActor
enum FlowMetrics {
    static func width(_ text: String, _ style: TextStyleToken) -> CGFloat {
        let font = TypeTokens.nsFont(style)
        let w = (text as NSString).size(withAttributes: [.font: font, .kern: style.tracking * font.pointSize]).width
        return w.rounded(.up)
    }

    static func button(_ title: String, primary: Bool, icon: Bool = false) -> CGFloat {
        FlowGeometry.buttonPaddingH * 2 + width(title, primary ? TypeTokens.hint.weight(500) : TypeTokens.hint)
            + (icon ? FlowGeometry.buttonIcon + FlowGeometry.buttonIconGap : 0)
    }

    static func size(_ surface: FlowSurface, model: FlowBarModel, timer: Bool) -> CGSize {
        let t = LiveTokens.shared.value
        let gap = t.contentGap
        switch surface {
        case .none: return .zero
        case .idle: return CGSize(width: t.idleWidth, height: t.idleHeight)
        case .hover: return CGSize(width: t.hoverWidth, height: t.hoverHeight)
        case .hold: return CGSize(width: t.holdPadding * 2 + t.liveDot + gap + t.waveHoldWidth, height: t.activeHeight)
        case .handsFree:
            let extra = timer ? gap + FlowGeometry.timerWidth : 0
            return CGSize(width: t.handsFreePadding * 2 + t.roundButton * 2 + gap * 2 + t.waveHandsFreeWidth + extra, height: t.activeHeight)
        case .processing: return CGSize(width: t.processingWidth, height: t.activeHeight)
        case .inserted:
            var w = FlowGeometry.insertedPaddingLeft + FlowGeometry.check + FlowGeometry.insertedGap + width("Inserted", TypeTokens.label)
            if let words = model.insertedWords { w += FlowGeometry.insertedGap + width(FlowCopy.words(words), TypeTokens.label.weight(400)) }
            return CGSize(width: w + FlowGeometry.insertedPadding, height: t.activeHeight)
        case .card(let notice):
            return cardSize(notice, model: model)
        }
    }

    static func cardSize(_ notice: FlowBarNotice, model: FlowBarModel) -> CGSize {
        let t = LiveTokens.shared.value
        let gap = t.contentGap
        let copy = FlowCopy(notice: notice, microphone: model.microphoneName)
        switch notice.kind {
        case .cancelled:
            let i = FlowGeometry.cancelledInsets
            let w = i.leading + FlowGeometry.ring + gap + width(copy.title, TypeTokens.label) + FlowGeometry.cancelledLabelTrail
                + gap + button("Undo", primary: true) + gap + button("Open History", primary: false) + i.trailing
            return CGSize(width: w, height: i.top + FlowGeometry.buttonHeightSmall + i.bottom)
        case .pasteError:
            let keys = ["⌘", "V"].map { max(FlowGeometry.pasteKeyHeight, width($0, TypeTokens.keycapSmall) + FlowGeometry.inlineKeyPaddingH * 2) }
            let w = FlowGeometry.pastePaddingLeft + FlowGeometry.cardIcon + gap + width(copy.title, TypeTokens.label.weight(400)) + gap
                + keys.reduce(0, +) + FlowGeometry.pasteKeyGap + FlowGeometry.pastePadding
            return CGSize(width: w, height: FlowGeometry.pasteHeight)
        case .noAudio:
            let i = FlowGeometry.noAudioPadding
            return CGSize(width: t.noAudioWidth, height: i + textHeight(sub: true) + gap + FlowGeometry.buttonHeightSmall + i)
        default:
            let i = FlowGeometry.errorInsets
            let text = max(width(copy.title, TypeTokens.label), copy.sub.map { width($0, TypeTokens.flowSub) } ?? 0)
            let buttons = notice.actions.map { button(copy.label($0), primary: $0 == notice.actions.first && $0 != .dismiss, icon: $0 == .retry) }
            let w = i.leading + FlowGeometry.cardIcon + gap + min(text, FlowCopy.maxTextWidth) + buttons.reduce(0) { $0 + gap + $1 } + i.trailing
            return CGSize(width: w, height: i.top + max(textHeight(sub: copy.sub != nil), FlowGeometry.buttonHeight) + i.bottom)
        }
    }

    static func textHeight(sub: Bool) -> CGFloat {
        TypeTokens.label.lineHeight + (sub ? TypeTokens.flowSub.lineHeight : 0)
    }

    /// The tooltip's size, for hit-testing.
    static func tooltip(key: String) -> CGSize {
        let gap = FlowGeometry.tooltipKeyGap
        let keyWidth = max(FlowGeometry.inlineKeyHeight, width(key, TypeTokens.keycapInline) + FlowGeometry.inlineKeyPaddingH * 2)
        let w = FlowGeometry.tooltipPaddingH * 2 + width("Hold", TypeTokens.hint.weight(500)) + gap + keyWidth + gap + width("to dictate", TypeTokens.hint.weight(500))
        return CGSize(width: w, height: LiveTokens.shared.value.tooltipHeight)
    }
}

/// The words on each card (§5.1). The board's copy is used where it is true of this app.
struct FlowCopy {
    let notice: FlowBarNotice
    let microphone: String

    static let maxTextWidth = FlowGeometry.cardTextMaxWidth

    static func words(_ n: Int) -> String { n == 1 ? "1 word" : "\(n) words" }

    var icon: Icon {
        switch notice.kind {
        case .pasteError: .clipboard
        case .transcriptionError, .micError: .alert
        case .noTextBox: .textfield
        case .noAudio: .micOff
        case .suggestion: .dictionary
        case .cancelled, .info, .hidden: .info
        }
    }

    var title: String {
        switch notice.kind {
        case .cancelled: "Cancelled"
        case .pasteError: "Copied to clipboard — press"
        case .transcriptionError: "Couldn’t transcribe that"
        case .micError: "Microphone isn’t available"
        case .noTextBox: "No text box selected"
        case .noAudio: "We couldn’t hear you"
        case .info, .hidden, .suggestion: notice.message
        }
    }

    var sub: String? {
        switch notice.kind {
        case .transcriptionError: "Audio saved in History"
        case .micError: "\(microphone) · check it’s connected"
        // The text is not on the clipboard here (insertion stops before pasting), so the board's
        // "Saved to History and clipboard" would be untrue.
        case .noTextBox: "Saved to History · ⌃⌘V pastes it"
        case .noAudio: "No speech from \(microphone)"
        default: nil
        }
    }

    func label(_ action: FlowBarNotice.Action) -> String {
        switch action {
        case .retry: "Retry"
        case .undo: "Undo"
        case .openHistory: "Open History"
        case .dismiss: "Dismiss"
        case .pasteLast: "Paste"
        case .add: "Add"
        case .switchMicrophone: "Switch microphone"
        case .testMic: "Test mic"
        }
    }
}

// MARK: - Surface

/// The one morphing surface: the pill in each state, or a card in its place.
struct FlowSurfaceView: View {
    let model: FlowBarModel
    @Environment(\.theme) private var theme
    @State private var shake: CGFloat = 0
    @State private var nudged = false
    @State private var nudging = false

    var body: some View {
        let surface = model.surface
        if surface == .handsFree, let since = model.listeningSince {
            // Only a hands-free recording ticks (for its timer); nothing runs while idle.
            TimelineView(.periodic(from: since, by: 1)) { context in
                surfaceBody(surface, timer: model.timerVisible(at: context.date), elapsed: context.date.timeIntervalSince(since))
            }
        } else {
            surfaceBody(surface, timer: false, elapsed: 0)
        }
    }

    func surfaceBody(_ surface: FlowSurface, timer: Bool, elapsed: TimeInterval) -> some View {
        let t = LiveTokens.shared.value
        let p = FlowPalette(t: t, increaseContrast: theme.increaseContrast)
        let motion = theme.motion
        let size = FlowMetrics.size(surface, model: model, timer: timer)
        let isCard: Bool = if case .card = surface { true } else { false }
        let radius = isCard ? t.cardRadius : size.height / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        return ZStack {
            shape.fill(p.fill)
            FlowSurfaceContent(model: model, surface: surface, timer: timer, elapsed: elapsed, palette: p)
                .id(surface.id)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: isCard ? motion.offset(t.toastRise) : 0))
                        .animation(motion.easeOut(t.toastIn).delay(motion.seconds(t.springResponse) * MotionTokens.contentDelayShare)),
                    removal: .opacity.animation(motion.easeIn(t.toastOut))))
            shape.strokeBorder(p.ring, lineWidth: t.ringWidth)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .contentShape(PillTarget(target: model.surface == .idle ? CGSize(width: t.hoverWidth, height: t.hoverHeight) : size))
        // The idle pill sits centered on the hover pill's footprint, so hover grows it from its middle.
        .padding(.bottom, surface == .idle ? (t.hoverHeight - t.idleHeight) / 2 : 0)
        .opacity(model.idleFaded && surface == .idle ? t.idleFadedOpacity : 1)
        .scaleEffect(nudging ? motion.scale(MotionTokens.barNudgeScale) : 1, anchor: .bottom)
        .offset(x: shake)
        .animation(motion.spring(SpringToken(response: t.springResponse, damping: t.springDamping)), value: size)
        .animation(motion.spring(SpringToken(response: t.springResponse, damping: t.springDamping)), value: surface.id)
        .animation(motion.easeInOut(t.idleFadeDuration), value: model.idleFaded)
        .onChange(of: surface.id) { _, id in
            if id == "card-transcriptionError" || id == "card-micError" { runShake() }
            if surface != .handsFree { nudged = false }
        }
        .onChange(of: elapsed >= t.nudgeAt) { _, reached in if reached && !nudged { runNudge() } }
        .onTapGesture {
            model.noteTap()
            switch model.displayed {
            case .idle, .listening(handsFree: false): model.onClick?()
            default: break
            }
        }
        .contextMenu {
            Button(FlowBarMenuItem.startHandsFree.rawValue) { model.onMenu?(.startHandsFree) }
            Button(FlowBarMenuItem.pasteLast.rawValue) { model.onMenu?(.pasteLast) }.keyboardShortcut("v", modifiers: [.control, .command])
            Button(FlowBarMenuItem.hideForHour.rawValue) { model.onMenu?(.hideForHour) }
            Button(FlowBarMenuItem.settings.rawValue) { model.onMenu?(.settings) }.keyboardShortcut(",", modifiers: .command)
            Divider()
            Button(FlowBarMenuItem.resetPosition.rawValue) { model.onMenu?(.resetPosition) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Murmur Flow Bar")
        .accessibilityValue(stateDescription(surface, elapsed: elapsed))
        .accessibilityAddTraits(surface == .hold || surface == .handsFree ? .updatesFrequently : [])
        .accessibilityAction(named: "Start or stop hands-free dictation") { model.onClick?() }
    }

    /// The transcription error's gentle 2 pt horizontal shake (a single fade under Reduce Motion).
    func runShake() {
        let t = LiveTokens.shared.value
        guard !theme.motion.reduce else { return }
        let step = t.shakeDuration / (MotionTokens.alertShakeCycles * 2)
        Task { @MainActor in
            for i in 0..<Int(MotionTokens.alertShakeCycles * 2) {
                withAnimation(theme.motion.linear(step)) { shake = i.isMultiple(of: 2) ? CGFloat(t.shakeAmplitude) : -CGFloat(t.shakeAmplitude) }
                try? await Task.sleep(for: .seconds(theme.motion.seconds(step)))
            }
            withAnimation(theme.motion.linear(step)) { shake = 0 }
        }
    }

    /// At five minutes of hands-free, one 4% scale pulse (§5.1 #4).
    func runNudge() {
        nudged = true
        let half = MotionTokens.barNudge / 2
        Task { @MainActor in
            withAnimation(theme.motion.easeOut(half)) { nudging = true }
            try? await Task.sleep(for: .seconds(theme.motion.seconds(half)))
            withAnimation(theme.motion.easeIn(half)) { nudging = false }
        }
    }

    func stateDescription(_ surface: FlowSurface, elapsed: TimeInterval) -> String {
        let prefix = model.command ? "Command Mode, " : ""
        switch surface {
        case .none: return "Hidden"
        case .idle, .hover: return "Ready. \(model.tooltipText)."
        case .hold: return prefix + "Listening"
        case .handsFree: return prefix + "Listening hands-free, \(FlowTimer.text(elapsed))"
        case .processing: return prefix + "Transcribing"
        case .inserted: return "Inserted" + (model.insertedWords.map { ", " + FlowCopy.words($0) } ?? "")
        case .card(let notice):
            let copy = FlowCopy(notice: notice, microphone: model.microphoneName)
            return [copy.title, copy.sub].compactMap { $0 }.joined(separator: ". ")
        }
    }
}

enum FlowTimer {
    static func text(_ elapsed: TimeInterval) -> String {
        let s = max(0, Int(elapsed))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The pill's hit area: a rectangle of the target size around the pill's centre (the idle pill is tiny,
/// so it answers over the hover pill's area).
struct PillTarget: Shape {
    let target: CGSize

    func path(in rect: CGRect) -> Path {
        let slop = FlowGeometry.hoverTargetSlop
        return Path(CGRect(x: rect.midX - target.width / 2 - slop, y: rect.midY - target.height / 2 - slop,
                           width: target.width + slop * 2, height: target.height + slop * 2))
    }
}

/// What the surface draws inside its shape.
struct FlowSurfaceContent: View {
    let model: FlowBarModel
    let surface: FlowSurface
    let timer: Bool
    let elapsed: TimeInterval
    let palette: FlowPalette

    var body: some View {
        let t = LiveTokens.shared.value
        let p = palette
        switch surface {
        case .none:
            EmptyView()
        case .idle:
            RoundedRectangle(cornerRadius: FlowGeometry.idleDashRadius, style: .continuous)
                .fill(p.idleMark)
                .frame(width: t.idleDashWidth, height: t.idleDashHeight)
        case .hover:
            FlowWave(model: model, width: FlowGeometry.stillWave.width, height: FlowGeometry.stillWave.height, still: true, color: p.stillWave)
        case .hold:
            HStack(spacing: t.contentGap) {
                Circle().fill(p.live).frame(width: t.liveDot, height: t.liveDot)
                FlowWave(model: model, width: t.waveHoldWidth, height: t.waveHeight, still: false, color: p.live)
            }
        case .handsFree:
            HStack(spacing: t.contentGap) {
                FlowRoundButton(kind: .cancel, palette: p) { model.onCancel?() }
                FlowWave(model: model, width: t.waveHandsFreeWidth, height: t.waveHeight, still: false, color: p.live)
                if timer {
                    Text(FlowTimer.text(elapsed))
                        .textStyle(TypeTokens.keycapSmall)
                        .monospacedDigit()
                        .foregroundStyle(p.timer)
                        .frame(width: FlowGeometry.timerWidth)
                        .transition(.opacity)
                }
                FlowRoundButton(kind: .stop, palette: p) { model.onStop?() }
            }
        case .processing:
            FlowDots(model: model, color: p.text)
        case .inserted:
            HStack(spacing: FlowGeometry.insertedGap) {
                FlowCheck(color: p.text)
                Text("Inserted").textStyle(TypeTokens.label).foregroundStyle(p.text)
                if let words = model.insertedWords {
                    Text(FlowCopy.words(words)).textStyle(TypeTokens.label.weight(400)).foregroundStyle(p.secondary)
                }
            }
            .padding(.leading, FlowGeometry.insertedPaddingLeft)
            .padding(.trailing, FlowGeometry.insertedPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .card(let notice):
            FlowCard(model: model, notice: notice, palette: p)
        }
    }
}

// MARK: - Waveform, dots, check, ring

/// Smooths the microphone level once per displayed frame (one-pole, attack and release time constants).
/// A plain class held in `@State`: it changes every frame and must not invalidate the view.
@MainActor
final class LevelSmoother {
    private var value = 0.0
    private var last: TimeInterval?

    func step(now: TimeInterval, target: Double, attack: Double, release: Double, reduceMotion: Bool) -> Double {
        let dt = last.map { min(0.1, max(0, now - $0)) } ?? 0
        last = now
        if target < value && reduceMotion {
            // Reduce Motion: the wave still follows the mic (it's data), without release smoothing.
            value = target
        } else {
            let tau = target > value ? attack : release
            value += (target - value) * (tau > 0 ? 1 - exp(-dt / tau) : 1)
        }
        return value
    }
}

/// The live waveform (§6.2): the logo's tail, a filled shape between a top and a bottom contour,
/// ported from `drawWave` in the motion reference. One `Canvas`, redrawn by a `TimelineView` that runs
/// only while listening. The still variant draws one frame at a fixed level.
struct FlowWave: View {
    let model: FlowBarModel
    let width: CGFloat
    let height: CGFloat
    let still: Bool
    let color: Color
    @Environment(\.theme) private var theme
    @State private var smoother = LevelSmoother()

    var body: some View {
        let t = LiveTokens.shared.value
        let running: Bool = if case .listening = model.displayed { !still } else { false }
        let reduce = theme.motion.reduce
        TimelineView(.animation(paused: !running)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let level: Double = still ? FlowGeometry.stillWaveLevel
                : min(1, smoother.step(now: now, target: model.level(at: now), attack: t.waveformAttack, release: t.waveformRelease, reduceMotion: reduce) * t.waveformGain)
            // Under Reduce Motion the lobes hold still; only the amplitude follows the mic.
            let time = still || reduce ? WaveTokens.stillTime : now * theme.motion.timeScale
            Canvas { gc, size in
                gc.fill(Self.path(width: Double(size.width), height: Double(size.height), time: time, level: level), with: .color(color))
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    static func lobeHeight(_ k: Double, _ time: Double, _ salt: Double) -> Double {
        let a = sin(k * WaveTokens.hashA + salt * WaveTokens.hashB) * WaveTokens.hashScale
        let r = a - floor(a)
        return WaveTokens.lobeLow + (1 - WaveTokens.lobeLow) * (0.5 + 0.5 * sin(time * (WaveTokens.lobeSpeed + r * WaveTokens.lobeSpeedSpread) + r * 2 * .pi))
    }

    static func path(width w: Double, height h: Double, time: Double, level: Double) -> Path {
        let mid = h / 2
        let amp = max(0, h / 2 - WaveTokens.edgeMargin)
        let lobes = max(WaveTokens.minimumLobes, w / WaveTokens.lobeWidth)
        let n = Int(max(WaveTokens.minimumSamples, (w * WaveTokens.samplesPerPoint).rounded()))
        let drift = time * MotionTokens.waveTravel
        let gain = min(1, max(0, level))
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        top.reserveCapacity(n + 1)
        bottom.reserveCapacity(n + 1)
        for i in 0...n {
            let u = Double(i) / Double(n)
            let rise = u < WaveTokens.rise ? sin(u / WaveTokens.rise * .pi / 2) : 1
            let fall = u < WaveTokens.fallFrom ? 1 : pow(max(0, 1 - (u - WaveTokens.fallFrom) / (1 - WaveTokens.fallFrom)), WaveTokens.fallExponent)
            let env = rise * fall
            let p = u * lobes * .pi - drift
            let k = floor(p / .pi)
            let lobe = pow(max(0, sin(p - k * .pi)), WaveTokens.lobeExponent)
            let up = WaveTokens.hairline + amp * gain * env * lobeHeight(k, time, 1) * lobe
            let down = WaveTokens.hairline + WaveTokens.bottomShare * amp * gain * env * lobeHeight(k, time, 2) * lobe
            top.append(CGPoint(x: u * w, y: mid - up))
            bottom.append(CGPoint(x: u * w, y: mid + down))
        }
        var path = Path()
        path.addLines(top + bottom.reversed())
        path.closeSubpath()
        return path
    }
}

/// Processing (§5.1 #5): five dots rippling left to right (`MurmurDots`); a slow opacity pulse under
/// Reduce Motion.
struct FlowDots: View {
    let model: FlowBarModel
    let color: Color
    @Environment(\.theme) private var theme

    var body: some View {
        let t = LiveTokens.shared.value
        let size = t.dotSize
        let count = FlowGeometry.dots
        let running = model.displayed == .processing
        let motion = theme.motion
        TimelineView(.animation(paused: !running)) { context in
            let now = context.date.timeIntervalSinceReferenceDate * motion.timeScale
            HStack(spacing: t.dotGap) {
                ForEach(0..<count, id: \.self) { i in
                    let ripple: Double = motion.reduce
                        ? 0.5 - 0.5 * cos(2 * .pi * now / MotionTokens.dotsPulseReduced)
                        : max(0, sin(now / t.dotsPeriod * 2 * .pi - Double(i) * MotionTokens.dotsPhaseStep))
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .opacity(MotionTokens.dotsOpacityLow + (1 - MotionTokens.dotsOpacityLow) * ripple)
                        .offset(y: motion.reduce ? 0 : -ripple * size * MotionTokens.dotsLift)
                }
            }
            .frame(height: size * 3, alignment: .bottom)
            .padding(.bottom, size)
        }
        .accessibilityHidden(true)
    }
}

/// The inserted check: a 16 pt stroke drawn in 180 ms.
struct FlowCheck: View {
    let color: Color
    @Environment(\.theme) private var theme
    @State private var drawn = false

    var body: some View {
        let t = LiveTokens.shared.value
        IconShape(.check)
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(color, style: StrokeStyle(lineWidth: FlowGeometry.checkStroke, lineCap: .round, lineJoin: .round))
            .frame(width: FlowGeometry.check, height: FlowGeometry.check)
            .onAppear { withAnimation(theme.motion.easeOut(t.checkDraw)) { drawn = true } }
            .accessibilityHidden(true)
    }
}

/// The countdown ring (§3.5): 22 pt, 2 pt stroke, track at 22%, the seconds left in the middle. It
/// drains linearly and pauses while the pointer is over the card.
struct FlowRing: View {
    let remaining: Double
    let duration: Double
    let color: Color
    @Environment(\.theme) private var theme

    var body: some View {
        let stroke = FlowGeometry.ringStroke
        ZStack {
            Circle().stroke(color.opacity(OpacityTokens.ringTrack), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: remaining)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(theme.motion.linear(MotionTokens.hover / 2), value: remaining)
            Text("\(max(0, Int((remaining * duration).rounded(.up))))")
                .textStyle(TypeTokens.ringDigit)
                .foregroundStyle(color)
        }
        .padding(stroke / 2)
        .frame(width: FlowGeometry.ring, height: FlowGeometry.ring)
        .accessibilityHidden(true)
    }
}

/// The hands-free pill's round buttons: the cancel circle with a 12 pt X, and the live stop circle with
/// an 8 pt square.
struct FlowRoundButton: View {
    enum Kind { case cancel, stop }
    let kind: Kind
    let palette: FlowPalette
    let action: () -> Void

    var body: some View {
        let t = LiveTokens.shared.value
        Button(action: action) {
            ZStack {
                Circle().fill(kind == .cancel ? palette.cancel : palette.live)
                switch kind {
                case .cancel:
                    IconShape(.cancel)
                        .stroke(palette.text, style: StrokeStyle(lineWidth: FlowGeometry.cancelStroke * FlowGeometry.cancelGlyph / IconTokens.grid, lineCap: .round))
                        .frame(width: FlowGeometry.cancelGlyph, height: FlowGeometry.cancelGlyph)
                case .stop:
                    RoundedRectangle(cornerRadius: FlowGeometry.stopSquareRadius, style: .continuous)
                        .fill(palette.stopGlyph)
                        .frame(width: FlowGeometry.stopSquare, height: FlowGeometry.stopSquare)
                }
            }
            .frame(width: t.roundButton, height: t.roundButton)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(kind == .cancel ? "Cancel and discard" : "Stop and transcribe")
    }
}

// MARK: - Tooltip and cards

/// "Hold [key] to dictate" above the hovered idle pill: a 28 pt ink pill, `hint` 12/500, the key in an
/// inline key cap with ivory rings.
struct FlowTooltip: View {
    let text: String
    let key: String
    let trail: String
    @Environment(\.theme) private var theme

    var body: some View {
        let p = FlowPalette(t: LiveTokens.shared.value, increaseContrast: theme.increaseContrast)
        HStack(spacing: FlowGeometry.tooltipKeyGap) {
            Text(text)
            FlowKey(label: key, height: FlowGeometry.inlineKeyHeight, style: TypeTokens.keycapInline, palette: p)
            Text(trail)
        }
        .textStyle(TypeTokens.hint.weight(500))
        .foregroundStyle(p.text)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, FlowGeometry.tooltipPaddingH)
        .frame(height: LiveTokens.shared.value.tooltipHeight)
        .background(Capsule(style: .circular).fill(p.fill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text) \(key) \(trail)")
    }
}

/// A key cap on the bar: no fill, an ivory ring and a 1.5 pt bottom ring.
struct FlowKey: View {
    let label: String
    let height: CGFloat
    let style: TextStyleToken
    let palette: FlowPalette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.keycapSmall, style: .continuous)
        Text(label)
            .textStyle(style)
            .foregroundStyle(palette.text)
            .fixedSize()
            .padding(.horizontal, FlowGeometry.inlineKeyPaddingH)
            .frame(minWidth: height, minHeight: height, maxHeight: height)
            .overlay {
                shape.strokeBorder(palette.keyRing, lineWidth: Stroke.hairline)
                shape.inset(by: FlowGeometry.inlineKeyBottom / 2)
                    .stroke(palette.keyBottom, lineWidth: FlowGeometry.inlineKeyBottom)
                    .mask(alignment: .bottom) { Rectangle().frame(height: FlowGeometry.inlineKeyBottom) }
            }
    }
}

/// A button inside a card: primary (ivory fill, ink text, 12/500) or a ring (12/400).
struct FlowCardButton: View {
    let title: String
    let primary: Bool
    let icon: Icon?
    let height: CGFloat
    let palette: FlowPalette
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlowGeometry.buttonRadius, style: .continuous)
        let ink = primary ? palette.buttonText : palette.text
        Button(action: action) {
            HStack(spacing: FlowGeometry.buttonIconGap) {
                if let icon {
                    IconView(icon, size: FlowGeometry.buttonIcon, color: ink, gridStroke: FlowGeometry.cancelStroke)
                }
                Text(title).textStyle(primary ? TypeTokens.hint.weight(500) : TypeTokens.hint).foregroundStyle(ink).fixedSize()
            }
            .padding(.horizontal, FlowGeometry.buttonPaddingH)
            .frame(height: height)
            .background(shape.fill(primary ? palette.button : (hovering ? palette.buttonRing : .clear)))
            .overlay { if !primary { shape.strokeBorder(palette.buttonRing, lineWidth: Stroke.hairline) } }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .animation(theme.motion.easeOut(MotionTokens.hover), value: hovering)
        .accessibilityLabel(title)
    }
}

/// The card that replaces the pill (§5.1 #7-11 and the SPEC notices).
struct FlowCard: View {
    let model: FlowBarModel
    let notice: FlowBarNotice
    let palette: FlowPalette

    var body: some View {
        let t = LiveTokens.shared.value
        let p = palette
        let copy = FlowCopy(notice: notice, microphone: model.microphoneName)
        let gap = t.contentGap
        Group {
            switch notice.kind {
            case .cancelled:
                let i = FlowGeometry.cancelledInsets
                HStack(spacing: gap) {
                    FlowRing(remaining: model.countdownRemaining, duration: notice.countdown ?? t.cancelledToastDuration, color: p.text)
                    Text(copy.title).textStyle(TypeTokens.label).foregroundStyle(p.text).padding(.trailing, FlowGeometry.cancelledLabelTrail)
                    FlowCardButton(title: copy.label(.undo), primary: true, icon: nil, height: FlowGeometry.buttonHeightSmall, palette: p) { model.onAction?(.undo, notice) }
                    FlowCardButton(title: copy.label(.openHistory), primary: false, icon: nil, height: FlowGeometry.buttonHeightSmall, palette: p) { model.onAction?(.openHistory, notice) }
                }
                .padding(EdgeInsets(top: i.top, leading: i.leading, bottom: i.bottom, trailing: i.trailing))
            case .pasteError:
                HStack(spacing: gap) {
                    IconView(copy.icon, size: FlowGeometry.cardIcon, color: p.text)
                    Text(copy.title).textStyle(TypeTokens.label.weight(400)).foregroundStyle(p.text)
                    HStack(spacing: FlowGeometry.pasteKeyGap) {
                        ForEach(["⌘", "V"], id: \.self) { FlowKey(label: $0, height: FlowGeometry.pasteKeyHeight, style: TypeTokens.keycapSmall, palette: p) }
                    }
                }
                .padding(.leading, FlowGeometry.pastePaddingLeft)
                .padding(.trailing, FlowGeometry.pastePadding)
            case .noAudio:
                VStack(alignment: .leading, spacing: gap) {
                    HStack(spacing: gap) {
                        IconView(copy.icon, size: FlowGeometry.cardIcon, color: p.text)
                        FlowCardText(title: copy.title, sub: copy.sub, palette: p)
                    }
                    .padding(.leading, FlowGeometry.noAudioInset)
                    HStack(spacing: FlowGeometry.buttonGap) {
                        FlowCardButton(title: copy.label(.switchMicrophone), primary: true, icon: nil, height: FlowGeometry.buttonHeightSmall, palette: p) { model.onAction?(.switchMicrophone, notice) }
                        FlowCardButton(title: copy.label(.testMic), primary: false, icon: nil, height: FlowGeometry.buttonHeightSmall, palette: p) { model.onAction?(.testMic, notice) }
                    }
                }
                .padding(FlowGeometry.noAudioPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                let i = FlowGeometry.errorInsets
                HStack(spacing: gap) {
                    IconView(copy.icon, size: FlowGeometry.cardIcon, color: p.text)
                    FlowCardText(title: copy.title, sub: copy.sub, palette: p)
                        .frame(maxWidth: FlowCopy.maxTextWidth, alignment: .leading)
                    ForEach(notice.actions, id: \.self) { action in
                        FlowCardButton(title: copy.label(action), primary: action == notice.actions.first && action != .dismiss,
                                       icon: action == .retry ? .retry : nil, height: FlowGeometry.buttonHeight, palette: p) { model.onAction?(action, notice) }
                    }
                }
                .padding(EdgeInsets(top: i.top, leading: i.leading, bottom: i.bottom, trailing: i.trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel([copy.title, copy.sub].compactMap { $0 }.joined(separator: ". "))
    }
}

/// A card's title (`label`) and optional sub-line (`flow-sub`, secondary).
struct FlowCardText: View {
    let title: String
    let sub: String?
    let palette: FlowPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).textStyle(TypeTokens.label).foregroundStyle(palette.text).lineLimit(1)
            if let sub { Text(sub).textStyle(TypeTokens.flowSub).foregroundStyle(palette.secondary).lineLimit(1) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
