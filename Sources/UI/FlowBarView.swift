import SwiftUI

/// The Flow Bar's content (UI_REDESIGN.md §5.1). It fills the panel's fixed canvas: the pill sits at the
/// bottom centre, and the tooltip, alert or toast sits above it. Every number comes from `LiveTokens`
/// or the static Flow Bar tokens; motion follows the theme (Reduce Motion, slow-motion time scale).
public struct FlowBarView: View {
    let model: FlowBarModel

    public init(model: FlowBarModel) {
        self.model = model
    }

    public var body: some View {
        ThemeProvider { FlowBarCanvas(model: model) }
    }
}

struct FlowBarCanvas: View {
    let model: FlowBarModel
    @Environment(\.theme) private var theme
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        let motion = theme.motion
        VStack(spacing: model.pill == .none ? 0 : t.tooltipGap) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                if let notice = model.notice {
                    FlowCard(notice: notice, model: model)
                        .id(notice.kind.rawValue + notice.message)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: motion.offset(t.toastRise))).animation(motion.easeOut(t.toastIn)),
                            removal: .opacity.animation(motion.easeIn(t.toastOut))))
                } else if model.tooltipVisible {
                    FlowTooltip(text: model.tooltipText)
                        .transition(.asymmetric(insertion: .opacity.animation(motion.easeOut(MotionTokens.hover)),
                                                removal: .opacity.animation(motion.easeIn(MotionTokens.tooltipOut))))
                }
            }
            if model.pill != .none {
                FlowPillView(model: model)
                    .transition(.asymmetric(
                        insertion: .scale(scale: motion.scale(t.appearScale), anchor: .bottom).combined(with: .opacity)
                            .animation(motion.spring(SpringToken(response: t.appearResponse, damping: t.appearDamping))),
                        removal: .opacity.animation(motion.easeIn(t.disappearDuration))))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, FlowGeometry.canvasMargin)
        .animation(motion.spring(SpringToken(response: t.springResponse, damping: t.springDamping)), value: model.pill)
        .animation(motion.easeOut(t.toastIn), value: model.notice)
        .animation(motion.easeOut(MotionTokens.hover), value: model.tooltipVisible)
    }
}

// MARK: - Pill

struct FlowPillView: View {
    let model: FlowBarModel
    @Environment(\.theme) private var theme
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        let size = model.pillSize
        let pill = model.pill
        let shape = Capsule(style: .circular)
        ZStack {
            shape.fill(Color.token(t.surfaceLight, t.surfaceDark))
            switch pill {
            case .hover:
                FlowSquares()
                    .transition(.opacity.animation(motion.easeOut(t.buttonsIn)))
            case .hold, .handsFree, .processing:
                FlowWaveform(model: model, processing: pill == .processing)
            case .inserted:
                FlowCheck()
            case .none, .idle:
                EmptyView()
            }
            if pill == .handsFree {
                HStack(spacing: 0) {
                    FlowRoundButton(kind: .cancel) { model.onCancel?() }
                    Spacer(minLength: 0)
                    FlowRoundButton(kind: .stop) { model.onStop?() }
                }
                .padding(.horizontal, t.buttonPadding)
                .transition(.opacity.combined(with: .scale(scale: motion.scale(t.appearScale)))
                    .animation(motion.easeOut(t.buttonsIn).delay(motion.seconds(t.springResponse * MotionTokens.barButtonsAt))))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.token(t.borderLight, t.borderDark), lineWidth: t.borderWidth))
        .shadow(color: t.shadowEnabled ? Color.black.opacity(t.shadowOpacity) : .clear, radius: t.shadowRadius, y: -t.shadowY)
        // The idle pill is tiny; it answers over the hover pill's area so it is easy to reach.
        .contentShape(PillTarget(target: model.pillTarget))
        .onTapGesture {
            model.noteTap()
            switch model.displayed {
            case .idle, .notice, .listening(handsFree: false): model.onClick?()
            default: break
            }
        }
        .contextMenu {
            ForEach(FlowBarMenuItem.allCases, id: \.self) { item in
                Button(item.rawValue) { model.onMenu?(item) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Murmur Flow Bar")
        .accessibilityValue(stateDescription)
        .accessibilityAddTraits(pill == .hold || pill == .handsFree ? .updatesFrequently : [])
        .accessibilityAction(named: "Start or stop hands-free dictation") { model.onClick?() }
    }

    private var motion: Motion { theme.motion }

    private var stateDescription: String {
        let prefix = model.command ? "Command Mode, " : ""
        switch model.pill {
        case .none: return "Hidden"
        case .idle, .hover: return "Ready. \(model.tooltipText)."
        case .hold: return prefix + "Listening"
        case .handsFree: return prefix + "Listening hands-free"
        case .processing: return prefix + "Transcribing"
        case .inserted: return "Inserted"
        }
    }
}

/// The pill's hit area: a rectangle of the target size, sharing the pill's bottom edge and centre.
struct PillTarget: Shape {
    let target: CGSize

    func path(in rect: CGRect) -> Path {
        let slop = FlowGeometry.hoverTargetSlop
        return Path(CGRect(x: rect.midX - target.width / 2, y: rect.maxY + slop - target.height, width: target.width, height: target.height))
    }
}

/// The hovered idle pill's 14 `flow-dot` squares. Static: nothing animates while idle.
struct FlowSquares: View {
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        let count = max(1, t.idleSquares)
        let width = Double(count - 1) * t.squarePitch + t.squareSide
        Canvas { context, size in
            let y = (size.height - t.squareSide) / 2
            for i in 0..<count {
                let rect = CGRect(x: Double(i) * t.squarePitch, y: y, width: t.squareSide, height: t.squareSide)
                context.fill(Path(rect), with: .color(Color.token(t.dotLight, t.dotDark)))
            }
        }
        .frame(width: width, height: t.squareSide)
        .accessibilityHidden(true)
    }
}

/// Smooths the microphone level per displayed frame and keeps the bars' recent history (newest on the
/// right). A plain class held in `@State`: it changes every frame and must not invalidate the view.
@MainActor
final class WaveformDriver {
    private var history: [Double] = []
    private var smoothed = 0.0
    private var lastFrame: TimeInterval?
    private var lastShift: TimeInterval = 0

    func heights(now: TimeInterval, target: Double, synthetic: Bool, tokens t: Tokens, reduceMotion: Bool) -> [Double] {
        let count = max(1, t.waveformBars)
        let step = 1 / max(1, t.waveformSampleRate)
        if synthetic {
            // A made-up voice sampled at the scroll rate: the same picture on every render, for snapshots.
            let base = (now / step).rounded(.down) * step
            return (0..<count).map { FlowBarModel.syntheticVoice(at: base - Double(count - 1 - $0) * step) }
        }
        if history.count != count { history = Array(repeating: 0, count: count) }
        let dt = lastFrame.map { min(step * 3, max(0, now - $0)) } ?? 0
        lastFrame = now
        let rising = target > smoothed
        if !rising && reduceMotion {
            // Reduce Motion: the bars still follow the microphone, without release smoothing.
            smoothed = target
        } else {
            let tau = rising ? t.waveformAttack : t.waveformRelease
            smoothed += (target - smoothed) * (tau > 0 ? 1 - exp(-dt / tau) : 1)
        }
        if now - lastShift >= step {
            lastShift = now
            history.removeFirst()
            history.append(smoothed)
        }
        return history
    }
}

/// The waveform (§3.5): ten bars in one `Canvas`, redrawn by a `TimelineView` that runs only while
/// listening or processing. A silent bar is a `flow-dot` square, so silence looks like the idle squares;
/// bars turn white as audio arrives (clay in Command Mode). Processing settles the bars to squares and
/// runs a left-to-right shimmer (a slow pulse under Reduce Motion).
struct FlowWaveform: View {
    let model: FlowBarModel
    let processing: Bool
    @Environment(\.theme) private var theme
    @State private var driver = WaveformDriver()
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        let tokens = t
        let count = max(1, tokens.waveformBars)
        let pitch = tokens.waveformBarWidth + tokens.waveformBarGap
        let width = Double(count - 1) * pitch + tokens.waveformBarWidth
        let running: Bool = switch model.displayed {
        case .listening, .processing: true
        default: false
        }
        let motion = theme.motion
        let dot = Color.token(tokens.dotLight, tokens.dotDark)
        let bright = model.command ? Color.token(tokens.commandLight, tokens.commandDark) : Color.token(tokens.waveformLight, tokens.waveformDark)
        TimelineView(.animation(paused: !running)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let levels = driver.heights(now: now, target: processing ? 0 : model.level(at: now),
                                        synthetic: model.forced != nil && !processing, tokens: tokens, reduceMotion: motion.reduce)
            let glow = processing ? Self.shimmer(count: count, now: now, motion: motion, width: tokens.shimmerWidth) : nil
            Canvas { gc, size in
                let center = Double(count - 1) / 2
                for (i, level) in levels.enumerated() {
                    let weight = 1 - tokens.waveformCenterBias * abs(Double(i) - center) / max(1, center)
                    let h = tokens.waveformMinHeight + (tokens.waveformMaxHeight - tokens.waveformMinHeight) * level * weight
                    let rect = CGRect(x: Double(i) * pitch, y: (size.height - h) / 2, width: tokens.waveformBarWidth, height: h)
                    let path = Path(roundedRect: rect, cornerRadius: tokens.waveformBarWidth / 2)
                    gc.fill(path, with: .color(dot))
                    let white = glow?[i] ?? min(1, level / max(0.001, tokens.waveformWhiteLevel))
                    if white > 0 { gc.fill(path, with: .color(bright.opacity(white))) }
                }
            }
        }
        .frame(width: width, height: tokens.waveformMaxHeight)
        .accessibilityHidden(true)
    }

    /// How bright each square is in the processing shimmer, 0…1.
    static func shimmer(count: Int, now: TimeInterval, motion: Motion, width: Double) -> [Double] {
        if motion.reduce {
            let period = motion.seconds(MotionTokens.processingPeriodReduced)
            let pulse = 0.5 - 0.5 * cos(2 * .pi * now / period)
            return Array(repeating: pulse, count: count)
        }
        let period = motion.seconds(LiveTokens.shared.value.processingLoopPeriod)
        let phase = now.truncatingRemainder(dividingBy: period) / period
        let band = max(0.01, width)
        let centre = phase * (1 + 2 * band) - band
        return (0..<count).map { i in
            let x = count > 1 ? Double(i) / Double(count - 1) : 0.5
            return max(0, 1 - abs(x - centre) / band)
        }
    }
}

/// The inserted check: drawn once, held, then the pill shrinks back to idle.
struct FlowCheck: View {
    @Environment(\.theme) private var theme
    @State private var drawn = false
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        IconShape(.check)
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(Color.token(t.successLight, t.successDark), style: StrokeStyle(lineWidth: FlowGeometry.glyphStroke, lineCap: .round, lineJoin: .round))
            .frame(width: FlowGeometry.checkGlyph, height: FlowGeometry.checkGlyph)
            .onAppear { withAnimation(theme.motion.easeOut(t.checkDraw)) { drawn = true } }
            .accessibilityHidden(true)
    }
}

/// The hands-free pill's round buttons: a warm-gray cancel circle with an X, and the clay stop circle
/// with a white rounded square.
struct FlowRoundButton: View {
    enum Kind { case cancel, stop }
    let kind: Kind
    let action: () -> Void
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(kind == .cancel ? Color.token(t.cancelLight, t.cancelDark) : Color.token(t.stopLight, t.stopDark))
                switch kind {
                case .cancel:
                    IconShape(.close)
                        .stroke(Color.token(t.cancelGlyphLight, t.cancelGlyphDark), style: StrokeStyle(lineWidth: FlowGeometry.glyphStroke, lineCap: .round))
                        .frame(width: FlowGeometry.cancelGlyph, height: FlowGeometry.cancelGlyph)
                case .stop:
                    RoundedRectangle(cornerRadius: FlowGeometry.stopGlyphRadius, style: .continuous)
                        .fill(Color.token(t.textLight, t.textDark))
                        .frame(width: FlowGeometry.stopGlyph, height: FlowGeometry.stopGlyph)
                }
            }
            .frame(width: t.buttonDiameter, height: t.buttonDiameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(kind == .cancel ? "Cancel dictation" : "Stop and insert")
    }
}

// MARK: - Tooltip, alert, toast

/// "Click or hold <key> to start dictating", above the hovered idle pill.
struct FlowTooltip: View {
    let text: String
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        Text(text)
            .modifier(FlowText(style: TypeTokens.flowText, size: t.labelSize))
            .foregroundStyle(Color.token(t.textLight, t.textDark))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, FlowGeometry.tooltipPaddingH)
            .frame(height: t.tooltipHeight)
            .background(Capsule(style: .circular).fill(Color.token(t.tooltipLight, t.tooltipDark)))
            .accessibilityLabel(text)
    }
}

/// A Flow Bar text style at the live-tuned size (line height moves with it).
struct FlowText: ViewModifier {
    let style: TextStyleToken
    let size: Double

    func body(content: Content) -> some View {
        content.textStyle(Self.style(style, size: size))
    }

    static func style(_ style: TextStyleToken, size: Double) -> TextStyleToken {
        var s = style
        s.lineHeight += size - s.size
        s.size = size
        return s
    }
}

struct CardSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// An alert or a toast, by the notice's style. Reports its size so the panel can hit-test it.
struct FlowCard: View {
    let notice: FlowBarNotice
    let model: FlowBarModel

    var body: some View {
        Group {
            switch notice.style {
            case .alert: FlowAlert(notice: notice, model: model)
            case .toast: FlowToast(notice: notice, model: model)
            }
        }
        .background(GeometryReader { proxy in Color.clear.preference(key: CardSizeKey.self, value: proxy.size) })
        .onPreferenceChange(CardSizeKey.self) { size in
            MainActor.assumeIsolated { model.cardSize = size }
        }
    }
}

extension FlowBarNotice.Action {
    var title: String {
        switch self {
        case .retry: "Retry"
        case .undo: "Undo"
        case .openHistory: "Open History"
        case .dismiss: "Dismiss"
        case .pasteLast: "Paste"
        case .add: "Add"
        case .selectMicrophone: "Select microphone"
        case .troubleshoot: "Troubleshoot"
        }
    }
}

/// The ring with "!" beside a notice's text: error or info color.
struct FlowNoticeIcon: View {
    let error: Bool
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        IconView(.warning, size: FlowGeometry.alertIcon,
                 color: error ? Color.token(t.errorLight, t.errorDark) : Color.token(t.infoLight, t.infoDark))
    }
}

/// A filled button on the bar's dark cards (alert buttons and the toast's Undo).
struct FlowCardButton: View {
    let title: String
    var width: CGFloat?
    var height: CGFloat = FlowGeometry.alertButtonHeight
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        Button(action: action) {
            Text(title)
                .modifier(FlowText(style: TypeTokens.flowText, size: t.labelSize))
                .foregroundStyle(Color.token(t.textLight, t.textDark))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, FlowGeometry.keycapPaddingH * 2)
                .frame(minWidth: width ?? FlowGeometry.toastButtonSize.width)
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: FlowGeometry.alertButtonRadius, style: .continuous)
                    .fill(hovering ? Color.token(t.alertButtonHoverLight, t.alertButtonHoverDark) : Color.token(t.alertButtonLight, t.alertButtonDark)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .animation(theme.motion.easeOut(MotionTokens.hover), value: hovering)
        .accessibilityLabel(title)
    }
}

/// The card surface shared by alerts and toasts: black fill, 1 pt `flow-alert-border`.
struct FlowCardSurface: ViewModifier {
    let radius: CGFloat
    private var t: Tokens { LiveTokens.shared.value }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(Color.token(t.surfaceLight, t.surfaceDark)))
            .overlay(shape.strokeBorder(Color.token(t.alertBorderLight, t.alertBorderDark), lineWidth: t.borderWidth))
            .contentShape(shape)
    }
}

/// Alerts (§3.5, §5.1): ring icon beside the title, close X top right, one-sentence body, two buttons.
struct FlowAlert: View {
    let notice: FlowBarNotice
    let model: FlowBarModel
    private var t: Tokens { LiveTokens.shared.value }

    var copy: (title: String, body: String) {
        switch notice.kind {
        case .transcriptionError: ("We couldn't transcribe that", "Your recording is saved in History, so you can try again.")
        case .noAudio: ("We didn't catch that", "No speech came through from your \(model.microphoneName) microphone.")
        case .micError: ("Your microphone isn't available", notice.message)
        default: (notice.message, "")
        }
    }

    var body: some View {
        let indent = FlowGeometry.alertIcon + FlowGeometry.iconGap
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: FlowGeometry.iconGap) {
                FlowNoticeIcon(error: true)
                Text(copy.title)
                    .modifier(FlowText(style: TypeTokens.flowAlert.weight(600), size: t.alertTextSize))
                    .foregroundStyle(Color.token(t.textLight, t.textDark))
                    .lineLimit(1)
                Spacer(minLength: FlowGeometry.iconGap)
                Button { model.onAction?(.dismiss, notice) } label: {
                    IconShape(.close)
                        .stroke(Color.token(t.secondaryTextLight, t.secondaryTextDark), style: StrokeStyle(lineWidth: FlowGeometry.glyphStroke, lineCap: .round))
                        .frame(width: FlowGeometry.alertClose, height: FlowGeometry.alertClose)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Close")
            }
            if !copy.body.isEmpty {
                Text(copy.body)
                    .modifier(FlowText(style: TypeTokens.flowText, size: t.labelSize))
                    .foregroundStyle(Color.token(t.secondaryTextLight, t.secondaryTextDark))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, indent)
                    .padding(.top, FlowGeometry.alertTitleGap)
            }
            HStack(spacing: FlowGeometry.alertButtonGap) {
                ForEach(Array(notice.actions.enumerated()), id: \.offset) { index, action in
                    FlowCardButton(title: action.title, width: FlowGeometry.alertButtonWidths[min(index, FlowGeometry.alertButtonWidths.count - 1)]) {
                        model.onAction?(action, notice)
                    }
                }
            }
            .padding(.leading, indent)
            .padding(.top, FlowGeometry.alertBodyGap)
        }
        .padding(t.alertPadding)
        .frame(width: t.noticeWidth, alignment: .leading)
        .frame(minHeight: t.noticeHeight)
        .modifier(FlowCardSurface(radius: t.alertRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.title)
    }
}

/// Toasts (§3.5, §5.1): ring icon, one line of text, then its actions; a countdown ring when the toast
/// dismisses itself (it pauses while the pointer is over the toast).
struct FlowToast: View {
    let notice: FlowBarNotice
    let model: FlowBarModel
    @Environment(\.theme) private var theme
    private var t: Tokens { LiveTokens.shared.value }

    var text: String {
        switch notice.kind {
        case .pasteError: "Copied. Press ⌘V to paste."
        case .cancelled: "Transcript cancelled"
        case .noTextBox: "Click a text box, then press"
        default: notice.message
        }
    }

    var buttons: [FlowBarNotice.Action] { notice.actions.filter { $0 != .openHistory } }

    /// The text's width: its natural width, capped so the toast stays within its maximum.
    var textWidth: CGFloat {
        let style = FlowText.style(TypeTokens.flowText, size: t.labelSize)
        let natural = (text as NSString).size(withAttributes: [.font: TypeTokens.nsFont(style, scale: theme.textScale)]).width.rounded(.up)
        var reserved = FlowGeometry.toastPaddingH * 2 + FlowGeometry.alertIcon + FlowGeometry.iconGap
        reserved += CGFloat(buttons.count) * (FlowGeometry.toastButtonSize.width + FlowGeometry.toastGap)
        if notice.actions.contains(.openHistory) { reserved += FlowGeometry.toastButtonSize.width * 2 }
        if notice.kind == .noTextBox { reserved += (FlowGeometry.keycap + FlowGeometry.keycapGap) * 3 + FlowGeometry.toastGap }
        if notice.countdown != nil { reserved += FlowGeometry.countdownRing + FlowGeometry.toastGap }
        return min(natural, max(FlowGeometry.toastButtonSize.width, FlowGeometry.toastMaxWidth - reserved))
    }

    var body: some View {
        HStack(spacing: FlowGeometry.toastGap) {
            HStack(spacing: FlowGeometry.iconGap) {
                FlowNoticeIcon(error: notice.kind == .pasteError)
                Text(text)
                    .modifier(FlowText(style: TypeTokens.flowText, size: t.labelSize))
                    .foregroundStyle(Color.token(t.textLight, t.textDark))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: textWidth, alignment: .leading)
            }
            if notice.kind == .noTextBox {
                HStack(spacing: FlowGeometry.keycapGap) {
                    ForEach(["⌃", "⌘", "V"], id: \.self) { FlowKeycap(label: $0) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Control Command V")
            }
            ForEach(buttons, id: \.self) { action in
                FlowCardButton(title: action.title, height: FlowGeometry.toastButtonSize.height) { model.onAction?(action, notice) }
            }
            if notice.actions.contains(.openHistory) {
                Button { model.onAction?(.openHistory, notice) } label: {
                    Text(FlowBarNotice.Action.openHistory.title)
                        .modifier(FlowText(style: TypeTokens.flowText, size: t.labelSize))
                        .foregroundStyle(Color.token(t.secondaryTextLight, t.secondaryTextDark))
                        .underline()
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Open History")
            }
            if notice.countdown != nil {
                FlowCountdownRing(remaining: model.countdownRemaining)
            }
        }
        .padding(.vertical, FlowGeometry.toastPaddingV)
        .padding(.horizontal, FlowGeometry.toastPaddingH)
        .frame(minWidth: t.toastWidth, minHeight: t.toastHeight)
        .modifier(FlowCardSurface(radius: t.toastRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.kind == .pasteError ? "\(text) \(notice.message)" : text)
    }
}

/// A key on the dark toast, for the paste shortcut.
struct FlowKeycap: View {
    let label: String
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        Text(label)
            .modifier(FlowText(style: TypeTokens.flowText, size: t.labelSize))
            .foregroundStyle(Color.token(t.textLight, t.textDark))
            .fixedSize()
            .padding(.horizontal, FlowGeometry.keycapPaddingH)
            .frame(minWidth: FlowGeometry.keycap, minHeight: FlowGeometry.keycap)
            .background(RoundedRectangle(cornerRadius: FlowGeometry.keycapRadius, style: .continuous)
                .fill(Color.token(t.alertButtonLight, t.alertButtonDark)))
            .overlay(RoundedRectangle(cornerRadius: FlowGeometry.keycapRadius, style: .continuous)
                .strokeBorder(Color.token(t.alertBorderLight, t.alertBorderDark), lineWidth: t.borderWidth))
    }
}

/// The countdown ring: 16 pt, 2 pt stroke, emptying linearly; it pauses while the pointer is over the toast.
struct FlowCountdownRing: View {
    let remaining: Double
    @Environment(\.theme) private var theme
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        ZStack {
            Circle().stroke(Color.token(t.alertBorderLight, t.alertBorderDark), lineWidth: FlowGeometry.countdownStroke)
            Circle()
                .trim(from: 0, to: remaining)
                .stroke(Color.token(t.secondaryTextLight, t.secondaryTextDark), style: StrokeStyle(lineWidth: FlowGeometry.countdownStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: FlowGeometry.countdownRing, height: FlowGeometry.countdownRing)
        .animation(theme.motion.easeOut(MotionTokens.hover / 2), value: remaining)
        .accessibilityHidden(true)
    }
}
