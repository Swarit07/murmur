import SwiftUI

/// The Flow Bar's content. Every number comes from `LiveTokens`. Original drawing: a capsule with a
/// level-driven waveform, a looping three-dot indicator, and notice cards.
struct FlowBarView: View {
    let model: FlowBarModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var t: Tokens { LiveTokens.shared.value }

    var body: some View {
        let size = model.barSize
        VStack {
            Spacer(minLength: 0)
            if model.displayed != .hidden {
                bar
                    .frame(width: size.width, height: size.height)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85, anchor: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, FlowBarPanel.shadowMargin)
        .animation(reduceMotion ? .easeInOut(duration: t.appearDuration) : .spring(response: t.springResponse, dampingFraction: t.springDamping), value: model.displayed)
    }

    @ViewBuilder var bar: some View {
        let shape = RoundedRectangle(cornerRadius: model.displayed.isNotice ? min(t.cornerRadius, 14) : min(t.cornerRadius, model.barSize.height / 2), style: .continuous)
        content
            .padding(.horizontal, model.displayed.isNotice ? 14 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    if t.useBlur { VisualEffectBlur() }
                    shape.fill(model.displayed == .idle ? Color.token(t.idleLight, t.idleDark) : Color.token(t.surfaceLight, t.surfaceDark))
                }
                .clipShape(shape)
            }
            .overlay(shape.strokeBorder(Color.token(t.borderLight, t.borderDark), lineWidth: t.borderWidth))
            .shadow(color: .black.opacity(t.shadowOpacity), radius: t.shadowRadius, y: -t.shadowY)
            .contentShape(shape)
            .onTapGesture {
                model.noteTap()
                switch model.displayed {
                case .idle, .listening(handsFree: false): model.onClick?()
                default: break
                }
            }
            .contextMenu {
                ForEach(FlowBarMenuItem.allCases, id: \.self) { item in
                    Button(item.rawValue) { model.onMenu?(item) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Murmur Flow Bar, \(model.displayed.name)")
    }

    @ViewBuilder var content: some View {
        switch model.displayed {
        case .hidden, .idle:
            Color.clear
        case .listening(let handsFree):
            HStack(spacing: 10) {
                if handsFree { circleButton("xmark", color: Color.token(t.cancelLight, t.cancelDark), label: "Cancel") { model.onCancel?() } }
                if model.command { commandMark }
                Waveform(levels: model.levels, tokens: t, color: model.command ? Color.token(t.commandLight, t.commandDark) : nil)
                if handsFree { circleButton("stop.fill", color: Color.token(t.stopLight, t.stopDark), label: "Stop and insert") { model.onStop?() } }
            }
        case .processing:
            HStack(spacing: 8) {
                if model.command { commandMark }
                ProcessingDots(period: t.processingLoopPeriod, color: model.command ? Color.token(t.commandLight, t.commandDark) : Color.token(t.waveformLight, t.waveformDark), reduceMotion: reduceMotion)
            }
        case .inserted:
            Image(systemName: "checkmark")
                .font(.system(size: t.labelSize + 2, weight: .bold))
                .foregroundStyle(Color.token(t.successLight, t.successDark))
                .accessibilityLabel("Inserted")
        case .notice(let notice):
            NoticeCard(notice: notice, model: model, tokens: t)
        }
    }

    /// Marks a Command Mode recording, so it never looks like plain dictation.
    var commandMark: some View {
        Image(systemName: "sparkles")
            .font(.system(size: t.labelSize, weight: .semibold))
            .foregroundStyle(Color.token(t.commandLight, t.commandDark))
            .accessibilityLabel("Command Mode")
    }

    func circleButton(_ symbol: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: t.buttonSize - 2, weight: .bold))
                .foregroundStyle(color)
                .frame(width: t.activeHeight - 12, height: t.activeHeight - 12)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension FlowBarState {
    var isNotice: Bool { if case .notice = self { true } else { false } }
}

struct Waveform: View {
    let levels: [Double]
    let tokens: Tokens
    var color: Color?

    var body: some View {
        HStack(alignment: .center, spacing: tokens.waveformBarGap) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                // Bars toward the middle reach higher, so the shape reads as a voice, not a meter.
                let center = Double(levels.count - 1) / 2
                let weight = 1 - 0.45 * abs(Double(index) - center) / max(1, center)
                Capsule()
                    .fill(color ?? Color.token(tokens.waveformLight, tokens.waveformDark))
                    .frame(width: tokens.waveformBarWidth, height: tokens.waveformMinHeight + (tokens.waveformMaxHeight - tokens.waveformMinHeight) * level * weight)
            }
        }
        .animation(.linear(duration: 1 / max(1, tokens.waveformFrameRate)), value: levels)
        .accessibilityLabel("Listening")
    }
}

struct ProcessingDots: View {
    let period: Double
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let local = (phase - Double(i) * 0.18).truncatingRemainder(dividingBy: 1)
                    let pulse = reduceMotion ? 0.6 : 0.35 + 0.65 * max(0, sin(.pi * (local < 0 ? local + 1 : local)))
                    Circle().fill(color.opacity(pulse)).frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityLabel("Processing")
    }
}

struct NoticeCard: View {
    let notice: FlowBarNotice
    let model: FlowBarModel
    let tokens: Tokens

    var icon: (String, Color) {
        switch notice.kind {
        case .pasteError, .transcriptionError: ("exclamationmark.triangle.fill", Color.token(tokens.errorLight, tokens.errorDark))
        case .micError: ("mic.slash.fill", Color.token(tokens.errorLight, tokens.errorDark))
        case .noTextBox: ("text.cursor", Color.token(tokens.secondaryTextLight, tokens.secondaryTextDark))
        case .cancelled: ("xmark.circle.fill", Color.token(tokens.secondaryTextLight, tokens.secondaryTextDark))
        case .info: ("info.circle.fill", Color.token(tokens.secondaryTextLight, tokens.secondaryTextDark))
        case .hidden: ("eye.slash", Color.token(tokens.secondaryTextLight, tokens.secondaryTextDark))
        case .suggestion: ("character.book.closed.fill", Color.token(tokens.commandLight, tokens.commandDark))
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon.0).foregroundStyle(icon.1)
            Text(notice.message)
                .font(.system(size: tokens.labelSize, weight: .token(tokens.labelWeight)))
                .foregroundStyle(Color.token(tokens.textLight, tokens.textDark))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(notice.actions, id: \.self) { action in
                Button(title(action)) { model.onAction?(action, notice) }
                    .buttonStyle(.plain)
                    .font(.system(size: tokens.buttonSize, weight: .semibold))
                    .foregroundStyle(Color.token(tokens.textLight, tokens.textDark))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            if notice.countdown != nil {
                Circle()
                    .trim(from: 0, to: model.countdownRemaining)
                    .stroke(Color.token(tokens.secondaryTextLight, tokens.secondaryTextDark), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            }
        }
        .onHover { model.countdownPaused = $0 }
    }

    func title(_ action: FlowBarNotice.Action) -> String {
        switch action {
        case .retry: "Retry"
        case .undo: "Undo"
        case .openHistory: "Open History"
        case .dismiss: "Dismiss"
        case .pasteLast: "Paste"
        case .add: "Add"
        }
    }
}

/// Behind-window blur for the bar surface.
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
