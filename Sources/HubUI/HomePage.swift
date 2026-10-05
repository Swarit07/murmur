import AppKit
import AVFoundation
import MurmurKit
import SwiftUI
import UI

/// Home (UI_REDESIGN.md v2 §5.3): today's date, "Welcome back, *name*", the stat strip, the style
/// feature card, then History grouped by day with Cleaned | Raw. History behaves as before (A4): search,
/// copy, play, retry or recover, undo the AI edit, keyboard selection (↑↓ or j k, Return copies).
struct HomePage: View {
    @Bindable var model: HubModel
    @Environment(\.theme) private var theme
    @State private var all: [DictationRecord] = []
    @State private var records: [DictationRecord] = []
    @State private var search = ""
    @State private var selection: DictationRecord.ID?
    @State private var player: AVAudioPlayer?
    @State private var busy: Set<String> = []
    @State private var showRaw = "cleaned"
    @AppStorage("murmur.hub.styleCardDismissed") private var cardDismissed = false
    @FocusState private var listFocused: Bool

    var body: some View {
        let c = theme.colors
        ScrollView {
            VStack(alignment: .leading, spacing: HubGeometry.sectionGapHome) {
                header
                if model.searchOpen {
                    MSearchField("Search History", text: $search)
                        .frame(maxWidth: HubGeometry.searchFieldWidth)
                }
                if !cardDismissed && search.isEmpty { featureCard }
                if all.isEmpty {
                    MEmptyState("Hold \(model.hotkeyLabel) in any app, speak, and let go. Everything you dictate is kept here, so nothing you say is lost.")
                } else if records.isEmpty {
                    Text("Nothing in History contains “\(search)”.").textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
                } else {
                    history
                }
            }
            .padding(.top, HubGeometry.pagePaddingTopHome)
            .padding(.horizontal, HubGeometry.pagePaddingSide)
            .padding(.bottom, HubGeometry.pagePaddingTop)
            .frame(maxWidth: HubGeometry.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .onChange(of: search) { reload() }
        .onChange(of: model.searchOpen) { if !model.searchOpen { search = "" } }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.didChange).receive(on: RunLoop.main)) { _ in reload() }
    }

    // MARK: Header

    var header: some View {
        let c = theme.colors
        let name = NSFullUserName().split(separator: " ").first.map(String.init)
        return VStack(alignment: .leading, spacing: Spacing.s8) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .textStyle(TypeTokens.caption)
                .foregroundStyle(c.textTertiary.color)
            HStack(alignment: .center, spacing: Spacing.s16) {
                if let name, !name.isEmpty {
                    SerifTitle("Welcome back, ", italic: name)
                } else {
                    SerifTitle("Welcome back")
                }
                Spacer(minLength: Spacing.s16)
                MStatStrip(stats)
            }
        }
    }

    /// "7-day streak · 6,343 words · 112 wpm" from the last 1,000 dictations; a stat that can't be
    /// computed is left out.
    var stats: [String?] {
        let calendar = Calendar.current
        let done = all.filter { $0.status == .inserted }
        let today = calendar.startOfDay(for: Date())
        let week = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let weekRecords = done.filter { $0.startedAt >= week }
        let weekWords = weekRecords.reduce(0) { $0 + Self.words($1.bestText) }
        let minutes = weekRecords.reduce(0.0) { $0 + $1.durationMs } / 60_000
        // Consecutive days with a dictation, ending today (or yesterday, if nothing yet today).
        let days = Set(done.map { calendar.startOfDay(for: $0.startedAt) })
        var day = days.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return [
            streak > 1 ? "\(streak)-day streak" : nil,
            weekWords > 0 ? "\(weekWords.formatted()) words" : nil,
            minutes > 0.05 && weekWords > 0 ? "\(Int((Double(weekWords) / minutes).rounded())) wpm" : nil,
        ]
    }

    // MARK: Feature card

    var featureCard: some View {
        let c = theme.colors
        return MFeatureCard {
            VStack(alignment: .leading, spacing: HubGeometry.featureTextGap) {
                SerifTitle("Make Murmur sound like ", italic: "you", style: TypeTokens.featureTitle)
                Text("Pick a style for messages, work chats and email. Murmur switches on its own, based on the app you’re typing in.")
                    .textStyle(TypeTokens.body)
                    .foregroundStyle(c.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: HubGeometry.featureParagraphWidth, alignment: .leading)
                HStack(spacing: Spacing.s8) {
                    MButton("Set up styles", kind: .primary) { model.go(.style) }
                    MButton("Not now", kind: .link) { cardDismissed = true }
                        .padding(.horizontal, HubGeometry.buttonPaddingHSmall)
                }
                .padding(.top, Spacing.s8)
            }
        } visual: {
            VStack(spacing: HubGeometry.featureSamplesGap) {
                ForEach(Self.featureSamples, id: \.category) { sample in
                    let style = WritingStyle(rawValue: model.settings.styles[sample.category.rawValue] ?? "formal") ?? .formal
                    MCard(padding: 0) {
                        HStack(alignment: .top, spacing: Spacing.s10) {
                            MAppTile(sample.icon)
                            VStack(alignment: .leading, spacing: Spacing.s4 / 2) {
                                Text("\(sample.label) · \(Self.styleName(style))").textStyle(TypeTokens.tagTight).foregroundStyle(c.textTertiary.color)
                                Text(style.apply(to: sample.text)).textStyle(TypeTokens.sampleCompact).foregroundStyle(c.textPrimary.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, HubGeometry.samplePadding.width)
                        .padding(.vertical, HubGeometry.samplePadding.height)
                    }
                }
            }
            .frame(width: HubGeometry.featureSamplesWidth)
        }
    }

    static let featureSamples: [(category: AppCategory, label: String, icon: Icon, text: String)] = [
        (.personal, "Messages", .chat, "Running 10 min late, save me a seat?"),
        (.work, "Work chat", .lines, "Build’s ready for review. Feedback by Friday?"),
        (.email, "Email", .mail, "Thank you for the notes. Let’s plan to ship on Friday."),
    ]

    static func styleName(_ style: WritingStyle) -> String {
        switch style {
        case .formal: "Formal."
        case .casual: "Casual"
        case .veryCasual: "very casual"
        case .excited: "Excited!"
        }
    }

    // MARK: History

    var history: some View {
        let c = theme.colors
        let groups = Self.days(records)
        return VStack(alignment: .leading, spacing: HubGeometry.sectionGapHome) {
            ForEach(Array(groups.enumerated()), id: \.element.0) { index, group in
                VStack(alignment: .leading, spacing: Spacing.s12) {
                    HStack {
                        MCaption(Self.dayTitle(group.0))
                        Spacer()
                        if index == 0 {
                            MSegmented("Show", selection: $showRaw, items: [("cleaned", "Cleaned"), ("raw", "Raw")], size: .small)
                        }
                    }
                    MListContainer {
                        ForEach(group.1) { r in
                            if r.id != group.1.first?.id { Hairline() }
                            HistoryRowView(record: r, showRaw: showRaw == "raw", selected: selection == r.id, busy: busy.contains(r.id),
                                           canPlay: audioURL(r) != nil, canRetry: canRetry(r),
                                           copy: { copy(text(r)) }, play: { play(r) }, retry: { retry(r) })
                                .contentShape(Rectangle())
                                .onTapGesture { selection = r.id; listFocused = true }
                                .contextMenu { rowMenu(r) }
                        }
                    }
                }
            }
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { copy(selected.flatMap(text)); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "jk")) { press in
            move(press.characters == "j" ? 1 : -1)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History")
        .accessibilityHint("Up and down arrows move, Return copies")
        .foregroundStyle(c.textPrimary.color)
    }

    func text(_ r: DictationRecord) -> String? {
        showRaw == "raw" ? (r.rawText ?? r.bestText) : r.bestText
    }

    static func words(_ text: String?) -> Int {
        text?.split(whereSeparator: { $0.isWhitespace }).count ?? 0
    }

    /// Records grouped by calendar day, newest first (records arrive newest first).
    static func days(_ records: [DictationRecord]) -> [(Date, [DictationRecord])] {
        var out: [(Date, [DictationRecord])] = []
        for r in records {
            let day = Calendar.current.startOfDay(for: r.startedAt)
            if out.last?.0 == day { out[out.count - 1].1.append(r) } else { out.append((day, [r])) }
        }
        return out
    }

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: Date())).day, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: Date())
        return sameYear ? day.formatted(.dateTime.month(.wide).day()) : day.formatted(.dateTime.month(.wide).day().year())
    }

    var selected: DictationRecord? { records.first { $0.id == selection } }

    func reload() {
        all = (try? model.store.recent(limit: 1000)) ?? []
        records = search.isEmpty ? all : ((try? model.store.recent(limit: 1000, search: search)) ?? [])
    }

    func move(_ delta: Int) {
        guard !records.isEmpty else { return }
        let i = records.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : records.count)
        selection = records[max(0, min(records.count - 1, i + delta))].id
    }

    func copy(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func audioURL(_ r: DictationRecord) -> URL? {
        guard let path = r.audioPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Retry or Recover needs audio under 14 days old; failed rows must also be 5 s or longer (A4).
    func canRetry(_ r: DictationRecord) -> Bool {
        guard audioURL(r) != nil, Date().timeIntervalSince(r.startedAt) < 14 * 86_400 else { return false }
        switch r.status {
        case .recorded, .transcribed: return true
        case .transcriptionFailed, .pasteFailed, .noTextBox, .cancelled: return r.durationMs >= 5_000
        case .inserted: return false
        }
    }

    func play(_ r: DictationRecord) {
        guard let url = audioURL(r) else { return }
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func retry(_ r: DictationRecord) {
        busy.insert(r.id)
        Task {
            _ = await model.controller.retry(recordId: r.id)
            busy.remove(r.id)
        }
    }

    @ViewBuilder func rowMenu(_ r: DictationRecord) -> some View {
        Button("Copy") { copy(text(r)) }
        if audioURL(r) != nil { Button("Play audio") { play(r) } }
        if canRetry(r) { Button(r.status == .recorded || r.status == .transcribed ? "Recover" : "Retry") { retry(r) } }
        if r.cleanText != nil, r.rawText != nil, r.cleanText != r.rawText {
            Divider()
            Button(r.useRaw ? "Redo AI edit (use cleaned text)" : "Undo AI edit (use original words)") {
                _ = try? model.store.update(id: r.id) { $0.useRaw.toggle() }
            }
            Button("Copy original words") { copy(r.rawText) }
        }
    }
}

/// One History row (§5.3): time, the app's tile, the transcript, and "Mail · 15 w"; hover shows Copy,
/// Play, Retry and a "raw" chip that peeks at the words as spoken.
struct HistoryRowView: View {
    let record: DictationRecord
    let showRaw: Bool
    let selected: Bool
    let busy: Bool
    let canPlay: Bool
    let canRetry: Bool
    let copy: () -> Void
    let play: () -> Void
    let retry: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false
    @State private var peek = false

    /// A finished dictation with no words: the audio had no speech.
    var silent: Bool { (record.status == .inserted || record.status == .transcribed) && (record.bestText ?? "").isEmpty }

    var body: some View {
        let c = theme.colors
        let active = hovering || selected || forced == .hover
        let rawDiffers = record.rawText != nil && record.rawText != record.bestText
        let shown = peek || showRaw ? (record.rawText ?? record.bestText) : record.bestText
        HStack(alignment: .center, spacing: HubGeometry.historyColumnGap) {
            Text(record.startedAt, format: .dateTime.hour().minute())
                .textStyle(TypeTokens.meta)
                .monospacedDigit()
                .foregroundStyle(c.textTertiary.color)
                .frame(width: HubGeometry.historyTimeColumn, alignment: .leading)
            MAppTile(silent ? .mic : Self.icon(for: record.appBundleId), faint: silent)
            HStack(spacing: Spacing.s8) {
                if silent {
                    Text("Audio was silent").textStyle(TypeTokens.body).foregroundStyle(c.textTertiary.color)
                    IconView(.info, size: HubGeometry.searchIcon, color: c.textTertiary.color)
                        .mTooltip("Nothing was said, so nothing was typed")
                } else {
                    if record.mode == "command" { MTag("command") }
                    Text(shown ?? Self.statusLabel(record))
                        .textStyle(TypeTokens.body)
                        .foregroundStyle(shown == nil || record.status != .inserted && record.status != .transcribed ? c.textTertiary.color : c.textPrimary.color)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .trailing) {
                Text(busy ? "Retrying…" : meta)
                    .textStyle(TypeTokens.meta)
                    .foregroundStyle(c.textTertiary.color)
                    .lineLimit(1)
                    .opacity(active && !busy ? 0 : 1)
                HStack(spacing: Spacing.s4) {
                    MIconButton(.copy, label: "Copy", size: .small, action: copy)
                    if canPlay { MIconButton(.wave, label: "Play audio", size: .small, action: play) }
                    if canRetry { MIconButton(.retry, label: record.status == .recorded || record.status == .transcribed ? "Recover" : "Retry", size: .small, action: retry) }
                    if rawDiffers && !silent {
                        Text("raw")
                            .textStyle(TypeTokens.keycapSmall.weight(400))
                            .foregroundStyle(c.textPrimary.color)
                            .padding(.horizontal, HubGeometry.keycapPaddingHInline)
                            .frame(height: HubGeometry.iconButtonSmall)
                            .background(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).fill(c.fillSelected.color))
                            .onHover { peek = $0 }
                            .accessibilityLabel("Show the words as spoken")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { peek.toggle() }
                    }
                }
                .opacity(active && !busy ? 1 : 0)
                .allowsHitTesting(active && !busy)
            }
            .frame(minWidth: HubGeometry.historyMetaColumn, alignment: .trailing)
            .animation(theme.motion.easeOut(MotionTokens.rowActionsFade), value: active)
        }
        .padding(.horizontal, HubGeometry.historyRowPadding.width)
        .padding(.vertical, HubGeometry.historyRowPadding.height)
        .background(selected ? c.fillSelected.color : (active ? c.fillHover.color : .clear))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(record.startedAt.formatted(.dateTime.hour().minute())), \(silent ? "Audio was silent" : (shown ?? Self.statusLabel(record)))")
    }

    var meta: String {
        let words = silent ? 0 : HomePage.words(record.bestText)
        let app = record.appName.flatMap { $0.isEmpty ? nil : $0 }
        let tail = record.status == .inserted || record.status == .transcribed || silent ? "\(words) w" : Self.statusShort(record)
        return [app, tail].compactMap { $0 }.joined(separator: " · ")
    }

    /// The app's tile: Messages-like apps, work chat, mail, code, or a note for everything else.
    static func icon(for bundleId: String?) -> Icon {
        switch AppCategory.of(bundleId: bundleId, url: nil) {
        case .personal: return .chat
        case .work: return .lines
        case .email: return .mail
        case .other:
            guard let bundleId else { return .note }
            return codeApps.contains(where: { bundleId.hasPrefix($0) }) ? .code : .note
        }
    }

    static let codeApps = ["com.apple.Terminal", "com.googlecode.iterm2", "com.microsoft.VSCode", "com.apple.dt.Xcode", "dev.zed.Zed",
                           "com.todesktop.230313mzl4w4u92", "com.jetbrains.", "com.sublimetext.", "dev.warp.", "com.mitchellh.ghostty"]

    static func statusLabel(_ r: DictationRecord) -> String {
        switch r.status {
        case .recorded: "Interrupted before transcription"
        case .transcribed: "Not cleaned up (interrupted)"
        case .inserted: "Inserted"
        case .cancelled: "Cancelled"
        case .transcriptionFailed: "Transcription failed"
        case .pasteFailed: "Not pasted: the text was on the clipboard"
        case .noTextBox: "No text box"
        }
    }

    static func statusShort(_ r: DictationRecord) -> String {
        switch r.status {
        case .recorded, .transcribed: "interrupted"
        case .inserted: "inserted"
        case .cancelled: "cancelled"
        case .transcriptionFailed: "failed"
        case .pasteFailed: "not pasted"
        case .noTextBox: "no text box"
        }
    }
}
