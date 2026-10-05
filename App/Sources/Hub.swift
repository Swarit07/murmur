import AppKit
import AVFoundation
import Combine
import MurmurKit
import ServiceManagement
import SwiftUI

/// The Hub's pages (spec section 6): Home (History), Dictionary, Snippets, Style, and Settings split into
/// General, System, Experimental, and Data and Privacy.
enum HubPage: String, CaseIterable, Identifiable, Hashable {
    case home, dictionary, snippets, style, general, system, experimental, privacy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .dictionary: "Dictionary"
        case .snippets: "Snippets"
        case .style: "Style"
        case .general: "General"
        case .system: "System"
        case .experimental: "Experimental"
        case .privacy: "Data and Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .home: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .style: "textformat"
        case .general: "gearshape"
        case .system: "macwindow"
        case .experimental: "flask"
        case .privacy: "lock.shield"
        }
    }

    static let main: [HubPage] = [.home, .dictionary, .snippets, .style]
    static let settings: [HubPage] = [.general, .system, .experimental, .privacy]
}

/// Shared state for the Hub and onboarding: the controller, History, and the live mic level.
@MainActor
@Observable
final class HubModel {
    let controller: DictationController
    let store: HistoryStore
    let settings = AppSettings.shared
    var page: HubPage = .home
    var backStack: [HubPage] = []
    var forwardStack: [HubPage] = []
    /// Latest microphone level, 0…1, for the level meters.
    var micLevel: Double = 0
    /// The controller's latest status, for the sidebar's status card.
    var status: DictationStatus?

    init(controller: DictationController, store: HistoryStore) {
        self.controller = controller
        self.store = store
        status = controller.status
    }

    func go(_ page: HubPage) {
        guard page != self.page else { return }
        backStack.append(self.page)
        forwardStack.removeAll()
        self.page = page
    }

    func back() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(page)
        page = previous
    }

    func forward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(page)
        page = next
    }

    /// Option+Up and Option+Down move through the sidebar (spec keyboard use).
    func step(_ delta: Int) {
        let all = HubPage.main + HubPage.settings
        guard let i = all.firstIndex(of: page) else { return }
        go(all[(i + delta + all.count) % all.count])
    }

    func push(level dbfs: Float) {
        micLevel = min(1, max(0, (Double(dbfs) + 60) / 50))
    }
}

/// The Hub: a full-height translucent sidebar and a page with its own header row, laid out by hand
/// under a transparent title bar. No SwiftUI toolbar or split view, so nothing in the title bar can
/// overlap the page content (it clipped the first section heading once).
struct HubView: View {
    @Bindable var model: HubModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Height of the unified title bar; the traffic lights sit centered in it.
    static let headerHeight: CGFloat = 52

    var body: some View {
        HStack(spacing: 0) {
            HubSidebar(model: model)
                .frame(width: 214)
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    navButton("chevron.left", help: "Back (⌘[)", enabled: !model.backStack.isEmpty) { model.back() }
                        .keyboardShortcut("[", modifiers: .command)
                    navButton("chevron.right", help: "Forward (⌘])", enabled: !model.forwardStack.isEmpty) { model.forward() }
                        .keyboardShortcut("]", modifiers: .command)
                    Text(model.page.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .padding(.leading, 8)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: Self.headerHeight)
                .background(WindowDragArea())
                .background(Color(nsColor: .windowBackgroundColor))
                .zIndex(1)
                Divider().zIndex(1)
                Group {
                    switch model.page {
                    case .home: HomePage(model: model)
                    case .dictionary: DictionaryView(store: model.store)
                    case .snippets: SnippetsView(store: model.store)
                    case .style: StylePage(model: model)
                    case .general: GeneralPage(model: model)
                    case .system: SystemPage(model: model)
                    case .experimental: ExperimentalPage(model: model)
                    case .privacy: PrivacyPage(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(model.page)
                .transition(.opacity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: model.page)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 760, minHeight: 480)
        .background {
            // Option+Up / Option+Down between pages.
            Button("") { model.step(-1) }.keyboardShortcut(.upArrow, modifiers: .option).opacity(0).frame(width: 0, height: 0)
            Button("") { model.step(1) }.keyboardShortcut(.downArrow, modifiers: .option).opacity(0).frame(width: 0, height: 0)
        }
    }

    func navButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(help)
    }
}

struct HubSidebar: View {
    let model: HubModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                BrandMark(size: 22)
                Text("Murmur").font(.headline)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
            ForEach(HubPage.main) { row($0) }
            Text("Settings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 16)
                .padding(.bottom, 4)
            ForEach(HubPage.settings) { row($0) }
            Spacer(minLength: 12)
            StatusCard(model: model)
        }
        .padding(.horizontal, 10)
        .padding(.top, HubView.headerHeight + 2)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) { WindowDragArea().frame(height: HubView.headerHeight) }
        .background(VisualEffect(material: .sidebar))
    }

    func row(_ page: HubPage) -> some View {
        SidebarRow(page: page, selected: model.page == page) { model.go(page) }
    }
}

struct SidebarRow: View {
    let page: HubPage
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(page.title).fontWeight(selected ? .semibold : .regular).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(selected ? 0.09 : hovering ? 0.045 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The sidebar's footer: whether Murmur is ready, and the shortcut to use.
struct StatusCard: View {
    let model: HubModel

    var body: some View {
        let (title, color) = describe(model.status?.phase ?? .loading)
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                Text("Hold \(DictationController.shortcutConfiguration(model.settings).pushToTalk.displayName) to dictate")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
        .help(model.status?.message ?? title)
        .accessibilityElement(children: .combine)
    }

    func describe(_ phase: DictationStatus.Phase) -> (String, Color) {
        switch phase {
        case .loading: ("Loading models…", .orange)
        case .idle, .inserted: ("Ready", .green)
        case .recording: ("Listening", .red)
        case .processing: ("Working…", .blue)
        case .error: ("Needs attention", .orange)
        }
    }
}

// MARK: - Home (History, A4)

struct HomePage: View {
    let model: HubModel
    @State private var all: [DictationRecord] = []
    @State private var records: [DictationRecord] = []
    @State private var search = ""
    @State private var selection: DictationRecord.ID?
    @State private var player: AVAudioPlayer?
    @State private var busy: Set<String> = []
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if all.isEmpty {
                EmptyState(
                    symbol: "waveform",
                    title: "Your dictations will appear here",
                    text: "Hold \(DictationController.shortcutConfiguration(model.settings).pushToTalk.displayName) in any app, speak, and let go. Everything you dictate is kept here, so nothing you say is lost.")
            } else {
                VStack(spacing: 12) {
                    stats
                    SearchField(prompt: "Search History", text: $search)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
                if records.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "No matches", text: "Nothing in History contains “\(search)”.")
                } else {
                    list
                }
                Divider()
                Text("\(records.count) \(records.count == 1 ? "dictation" : "dictations") · ↑↓ or j k to move · Return copies")
                    .font(.caption).foregroundStyle(.secondary).padding(6)
            }
        }
        .onChange(of: search) { reload() }
        .onAppear { reload(); listFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.didChange).receive(on: RunLoop.main)) { _ in reload() }
    }

    var stats: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let week = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        let done = all.filter { $0.status == .inserted }
        let todayWords = done.filter { $0.startedAt >= today }.reduce(0) { $0 + Self.words($1.bestText) }
        let weekRecords = done.filter { $0.startedAt >= week }
        let weekWords = weekRecords.reduce(0) { $0 + Self.words($1.bestText) }
        let minutes = weekRecords.reduce(0.0) { $0 + $1.durationMs } / 60_000
        return HStack(spacing: 10) {
            StatTile(symbol: "sun.max", label: "Words today", value: todayWords.formatted())
            StatTile(symbol: "calendar", label: "Words this week", value: weekWords.formatted())
            StatTile(symbol: "speedometer", label: "Speaking pace", value: minutes > 0.05 ? "\(Int((Double(weekWords) / minutes).rounded())) wpm" : "—")
        }
    }

    var list: some View {
        List(selection: $selection) {
            ForEach(Self.days(records), id: \.0) { day, rows in
                Text(Self.dayTitle(day))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, day == Self.days(records).first?.0 ? 0 : 10)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
                    .accessibilityAddTraits(.isHeader)
                ForEach(rows) { r in
                    HistoryRow(record: r, busy: busy.contains(r.id), canPlay: audioURL(r) != nil,
                               play: { play(r) }, copy: { copy(r.bestText) }, retry: canRetry(r) ? { retry(r) } : nil)
                        .tag(r.id)
                        .contextMenu { rowMenu(r) }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .focused($listFocused)
        .onKeyPress(.return) { copy(selected?.bestText); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "jk")) { press in
            move(press.characters == "j" ? 1 : -1)
            return .handled
        }
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
        Button("Copy") { copy(r.bestText) }
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

struct HistoryRow: View {
    let record: DictationRecord
    let busy: Bool
    let canPlay: Bool
    let play: () -> Void
    let copy: () -> Void
    let retry: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(record.startedAt, format: .dateTime.hour().minute())
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.bestText ?? statusLabel)
                    .foregroundStyle(record.bestText == nil ? .secondary : .primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    if record.mode == "command" {
                        Text("Command")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                        if let instruction = record.rawText { Text("“\(instruction)”").lineLimit(1) }
                    }
                    if let app = record.appName, !app.isEmpty { Text(app) }
                    if record.useRaw {
                        Text("·")
                        Text("Original words (AI edit undone)").foregroundStyle(.orange)
                    } else if record.status != .inserted, record.bestText != nil {
                        Text("·")
                        Text(statusLabel).foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            if busy {
                ProgressView().controlSize(.small).padding(4)
            } else if hovering {
                HStack(spacing: 2) {
                    if canPlay { iconButton("play.fill", help: "Play audio", action: play) }
                    iconButton("doc.on.doc", help: "Copy", action: copy)
                    if let retry { iconButton("arrow.clockwise", help: "Retry", action: retry) }
                }
                .padding(3)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }
        }
        .onHover { hovering = $0 }
    }

    func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 22).contentShape(Rectangle()) }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel(help)
    }

    var statusLabel: String {
        switch record.status {
        case .recorded: "Interrupted before transcription"
        case .transcribed: "Not cleaned up (interrupted)"
        case .inserted: "Inserted"
        case .cancelled: "Cancelled"
        case .transcriptionFailed: "Transcription failed"
        case .pasteFailed: "Not pasted: the text was on the clipboard"
        case .noTextBox: "No text box"
        }
    }
}

// MARK: - Style

struct StylePage: View {
    let model: HubModel
    @State private var level = AppSettings.shared.cleanupLevel
    @State private var category = "personal"
    @State private var styles = AppSettings.shared.styles
    @State private var transforms = AppSettings.shared.transformsEnabled

    static let categories = [("personal", "Personal messages"), ("work", "Work messages"), ("email", "Email"), ("other", "Other")]
    /// Names are written in their own style, as in the spec (S4).
    static let styleOptions: [(id: String, name: String, detail: String, example: String, categories: Set<String>)] = [
        ("formal", "Formal.", "Caps and punctuation", "Hey, are you free for lunch tomorrow? Let's do 12 if that works.", ["personal", "work", "email", "other"]),
        ("casual", "Casual", "Caps, less punctuation", "Hey are you free for lunch tomorrow? Let's do 12 if that works", ["personal", "work", "email", "other"]),
        ("veryCasual", "very casual", "No caps, less punctuation", "hey are you free for lunch tomorrow? let's do 12 if that works", ["personal"]),
        ("excited", "Excited!", "More exclamation marks", "Hey, are you free for lunch tomorrow? Let's do 12 if that works!", ["work", "email", "other"]),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(Self.categories, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Self.styleOptions.filter { $0.categories.contains(category) }, id: \.id) { option in
                        Card(title: option.name, detail: option.detail, example: option.example, selected: (styles[category] ?? "formal") == option.id) {
                            styles[category] = option.id
                            model.settings.styles = styles
                        }
                    }
                }
            } header: {
                Text("Style by app")
            } footer: {
                Footnote("Murmur picks the category from the app you dictate into, and web apps by their address. AI assistants and terminals count as Other. English only.")
            }
            Section {
                Toggle(isOn: $transforms) {
                    Text("AI edits")
                    Text("Off: Murmur still removes fillers and applies spoken punctuation, your dictionary and snippets, but no AI model edits the text.")
                }
                .onChange(of: transforms) { model.settings.transformsEnabled = transforms }
                HStack(alignment: .top, spacing: 10) {
                    Card(title: "None", example: "um so I think we should uh move the launch to Friday", selected: level == "none") { setLevel("none") }
                    Card(title: "Light", example: "I think we should move the launch to Friday.", selected: level == "light") { setLevel("light") }
                    Card(title: "Medium", example: "Let's move the launch to Friday.", selected: level == "medium") { setLevel("medium") }
                }
                .disabled(!transforms)
                .opacity(transforms ? 1 : 0.5)
            } header: {
                Text("Auto Cleanup")
            } footer: {
                Footnote("Light removes fillers and fixes grammar. Medium also tightens wording. Names, numbers and negations are never changed.")
            }
        }
        .formStyle(.grouped)
    }

    func setLevel(_ value: String) {
        level = value
        model.settings.cleanupLevel = value
    }
}

struct Card: View {
    let title: String
    var detail: String?
    let example: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                if let detail { Text(detail).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                Text(example).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(hovering ? 0.07 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Settings pages

struct GeneralPage: View {
    let model: HubModel
    @State private var engine = AppSettings.shared.engine
    @State private var cleanup = AppSettings.shared.cleanupProvider

    /// Recommended first, then local, then cloud, then no AI.
    static let cleanupOrder = ["mlx:qwen3.5-4b", "mlx:smollm3-3b", "mlx:qwen3-4b-2507", "mlx:qwen3.5-2b", "apple-foundation", "groq", "openrouter", "rules"]

    var body: some View {
        Form {
            Section("Shortcuts") { ShortcutSettings(model: model) }
            Section("Microphone") { MicrophoneSettings(model: model) }
            Section {
                Picker("Speech engine", selection: $engine) {
                    ForEach(EngineCatalog.ids.filter { ModelNames.engines[$0] != nil }, id: \.self) { Text(ModelNames.engines[$0] ?? $0).tag($0) }
                }
                .onChange(of: engine) { model.settings.engine = engine }
                Picker("Cleanup model", selection: $cleanup) {
                    ForEach(Self.cleanupOrder.filter { ModelNames.cleanup[$0] != nil }, id: \.self) { Text(ModelNames.cleanup[$0] ?? $0).tag($0) }
                }
                .onChange(of: cleanup) { model.settings.cleanupProvider = cleanup }
            } header: {
                Text("Models")
            } footer: {
                Footnote("The speech engine turns your voice into words; the cleanup model tidies them. Both run on this Mac unless you pick a cloud option.")
            }
            Section("Languages") { LanguagePicker(settings: model.settings) }
            Section("Permissions") { PermissionsSummary() }
        }
        .formStyle(.grouped)
    }
}

struct SystemPage: View {
    let model: HubModel
    @State private var showFlowBar = AppSettings.shared.showFlowBar
    @State private var smartFormatting = AppSettings.shared.smartFormatting
    @State private var showInDock = AppSettings.shared.showInDock
    @State private var sounds = AppSettings.shared.soundsEnabled
    @State private var debug = AppSettings.shared.debugMenu
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Flow Bar") {
                Toggle(isOn: $showFlowBar) {
                    Text("Show the Flow Bar at all times")
                    Text("Off: it appears only while you dictate or when something needs your attention.")
                }
                .onChange(of: showFlowBar) { model.settings.showFlowBar = showFlowBar }
                Toggle(isOn: $sounds) {
                    Text("Sounds")
                    Text("A soft sound when dictation starts, stops and finishes.")
                }
                .onChange(of: sounds) { model.settings.soundsEnabled = sounds }
            }
            Section("Formatting") {
                Toggle(isOn: $smartFormatting) {
                    Text("Smart Formatting")
                    Text("Turns spoken lists of three or more items into numbered lists, and long dictations into paragraphs. Needs AI edits.")
                }
                .onChange(of: smartFormatting) { model.settings.smartFormatting = smartFormatting }
            }
            Section("App") {
                Toggle("Launch Murmur at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
                Toggle(isOn: $showInDock) {
                    Text("Show in Dock")
                    Text("Murmur always stays in the menu bar.")
                }
                .onChange(of: showInDock) { model.settings.showInDock = showInDock }
            }
            Section("Advanced") {
                Toggle(isOn: $debug) {
                    Text("Debug menu")
                    Text("Adds tools for testing the Flow Bar, sounds and focus to the menu bar menu.")
                }
                .onChange(of: debug) { model.settings.debugMenu = debug }
            }
        }
        .formStyle(.grouped)
    }

    /// A7: register the app as a login item through ServiceManagement.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = SMAppService.mainApp.status == .requiresApproval ? "Approve Murmur in System Settings › General › Login Items." : nil
        } catch {
            loginError = "Could not change the login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct ExperimentalPage: View {
    let model: HubModel
    @State private var commandMode = AppSettings.shared.commandMode
    @State private var pressEnter = AppSettings.shared.pressEnter
    @State private var confirmPressEnter = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $commandMode) {
                    Text("Command Mode")
                    Text("Hold \(HotkeyConfiguration.defaultCommand(appleKeyboard: model.settings.keyboardLayout != "other").displayName) and speak an instruction, like “make this friendlier” or “translate to Spanish”. With text selected, Murmur rewrites it in place, and one ⌘Z brings it back. With nothing selected, it writes a draft at the cursor.")
                }
                .onChange(of: commandMode) { model.settings.commandMode = commandMode }
                Toggle(isOn: Binding(get: { pressEnter }, set: { on in
                    if on { confirmPressEnter = true } else { pressEnter = false; model.settings.pressEnter = false }
                })) {
                    Text("Press Enter after “press enter”")
                    Text("End a dictation with “press enter” and Murmur presses Return after pasting.")
                }
            } footer: {
                Footnote("Command Mode uses the cleanup model chosen in Settings › General › Models, on this Mac unless you picked a cloud model. You can change its shortcut in General › Shortcuts.")
            }
        }
        .formStyle(.grouped)
        .alert("Turn on Press Enter?", isPresented: $confirmPressEnter) {
            Button("Turn On") { pressEnter = true; model.settings.pressEnter = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("When a dictation ends with “press enter”, Murmur presses Return right after pasting. In chat apps that sends the message at once.")
        }
    }
}

struct PrivacyPage: View {
    let model: HubModel
    @State private var keepAudio = AppSettings.shared.keepAudio
    @State private var neverStore = AppSettings.shared.neverStore
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("History") {
                Toggle(isOn: $keepAudio) {
                    Text("Keep audio for 14 days")
                    Text("Lets you replay a dictation and retry it if something went wrong.")
                }
                .onChange(of: keepAudio) { model.settings.keepAudio = keepAudio }
                .disabled(neverStore)
                Toggle(isOn: $neverStore) {
                    Text("Never store anything")
                    Text("No History, no audio, nothing written to disk. Paste last still works until Murmur quits.")
                }
                .onChange(of: neverStore) { model.settings.neverStore = neverStore }
                HStack {
                    Spacer()
                    Button("Delete all History and audio…", role: .destructive) { confirmDelete = true }
                }
            }
            Section {
                CloudKeys()
            } header: {
                Text("Cloud (optional)")
            } footer: {
                Footnote("Audio and text stay on this Mac unless you choose a Groq or OpenRouter option. Murmur has no analytics, and its logs hold timings, never your words.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all History and audio?", isPresented: $confirmDelete) {
            Button("Delete everything", role: .destructive) {
                try? model.store.deleteAll()
                try? FileManager.default.removeItem(at: MurmurPaths.audio)
            }
        } message: { Text("This cannot be undone. Your dictionary and snippets stay.") }
    }
}

/// Groq and OpenRouter keys, stored in the Keychain.
struct CloudKeys: View {
    @State private var groq = ""
    @State private var groqSaved = Keychain.get("groq") != nil
    @State private var openRouter = ""
    @State private var openRouterSaved = Keychain.get("openrouter") != nil

    var body: some View {
        keyRow("Groq API key", text: $groq, saved: $groqSaved, account: "groq")
        keyRow("OpenRouter API key", text: $openRouter, saved: $openRouterSaved, account: "openrouter")
    }

    func keyRow(_ label: String, text: Binding<String>, saved: Binding<Bool>, account: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            SecureField(saved.wrappedValue ? "Saved in Keychain" : "Paste key", text: text)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 240)
            Button("Save") {
                Keychain.set(text.wrappedValue, for: account)
                saved.wrappedValue = !text.wrappedValue.isEmpty
                text.wrappedValue = ""
            }
            .disabled(text.wrappedValue.isEmpty)
            if saved.wrappedValue { Button("Remove") { Keychain.set(nil, for: account); saved.wrappedValue = false } }
        }
    }
}

/// Permission status with Grant buttons that open the right System Settings pane (A3).
struct PermissionsSummary: View {
    @State private var snapshot = PermissionSnapshot.current()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Microphone", snapshot.microphone, pane: "Privacy_Microphone") { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
            row("Accessibility", snapshot.accessibility, pane: "Privacy_Accessibility") { Permissions.promptAccessibility() }
            row("Input Monitoring", snapshot.inputMonitoring, pane: "Privacy_ListenEvent") { Permissions.requestInputMonitoring() }
            if !snapshot.inputMonitoring {
                HStack {
                    Footnote("After you turn on Input Monitoring, macOS may need Murmur to restart.")
                    Spacer()
                    Button("Restart Murmur") { Self.relaunch() }
                }
            }
        }
        .onReceive(timer) { _ in snapshot = .current() }
    }

    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    func row(_ name: String, _ ok: Bool, pane: String, request: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(ok ? .green : .orange)
            Text(name)
            Spacer()
            if !ok {
                Button("Grant") {
                    request()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
        }
    }
}

struct PermissionSnapshot: Equatable {
    var microphone: Bool
    var accessibility: Bool
    var inputMonitoring: Bool

    var allGranted: Bool { microphone && accessibility && inputMonitoring }

    static func current() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibility: Permissions.accessibility,
            inputMonitoring: Permissions.inputMonitoring)
    }
}

// MARK: - Shortcuts (D8)

struct ShortcutSettings: View {
    let model: HubModel
    @State private var config: HotkeyConfiguration = DictationController.shortcutConfiguration(.shared)

    var body: some View {
        ShortcutRow(title: "Push to talk", shortcut: config.pushToTalk, model: model) { new in
            config.pushToTalk = new
            model.controller.setShortcuts(config)
        }
        ShortcutRow(title: "Hands-free", shortcut: config.handsFree, model: model) { new in
            config.handsFree = new
            model.controller.setShortcuts(config)
        }
        if let command = config.command {
            ShortcutRow(title: "Command Mode", shortcut: command, model: model) { new in
                config.command = new
                model.controller.setShortcuts(config)
            }
        }
        HStack {
            Text("Double-tap push-to-talk also starts hands-free. Esc cancels.").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Reset to defaults") {
                model.controller.setShortcuts(nil)
                config = DictationController.shortcutConfiguration(model.settings)
            }
        }
        if config.pushToTalk == .modifiers([.fn]) || config.handsFree == .key(keyCode: 49, modifiers: [.fn]), Permissions.fnUsageType != 0 {
            HStack {
                Image(systemName: "info.circle").foregroundStyle(.blue)
                Text("The Globe key may also open emoji or dictation. Set System Settings › Keyboard › “Press 🌐 key to” to Do Nothing.").font(.caption)
                Button("Open") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
            }
        }
        if Permissions.secureEventInput {
            Label("Another app has Secure Keyboard Entry on, which blocks shortcuts until it is turned off.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

/// Records a new shortcut: modifiers alone save when released, a key combination when its key is
/// released, a mouse button when pressed (D8).
struct ShortcutRow: View {
    let title: String
    let shortcut: Shortcut
    let model: HubModel
    let save: (Shortcut) -> Void
    @State private var recording = false
    @State private var monitor: Any?
    @State private var peak: Set<ModifierKey> = []
    @State private var pendingKey: (Int, Set<ModifierKey>)?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(recording ? "Press the new shortcut…" : shortcut.displayName) { recording ? stop() : start() }
                .buttonStyle(.bordered)
                .tint(recording ? .accentColor : nil)
            if recording { Button("Cancel") { stop() } }
        }
        .onDisappear { stop() }
    }

    func start() {
        recording = true
        peak = []
        pendingKey = nil
        model.controller.shortcutsPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp, .otherMouseDown]) { event in
            handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        model.controller.shortcutsPaused = false
    }

    func modifiers(_ flags: NSEvent.ModifierFlags) -> Set<ModifierKey> {
        var set: Set<ModifierKey> = []
        if flags.contains(.function) { set.insert(.fn) }
        if flags.contains(.control) { set.insert(.control) }
        if flags.contains(.option) { set.insert(.option) }
        if flags.contains(.command) { set.insert(.command) }
        if flags.contains(.shift) { set.insert(.shift) }
        return set
    }

    func handle(_ event: NSEvent) {
        switch event.type {
        case .otherMouseDown:
            finish(.mouse(button: event.buttonNumber))
        case .flagsChanged:
            if event.keyCode == 57 { finish(.capsLock); return }
            let held = modifiers(event.modifierFlags)
            if held.count > peak.count { peak = held }
            if held.isEmpty && !peak.isEmpty && pendingKey == nil { finish(.modifiers(peak)) }
        case .keyDown:
            if event.keyCode == 53 && modifiers(event.modifierFlags).isEmpty { stop(); return }
            pendingKey = (Int(event.keyCode), modifiers(event.modifierFlags))
        case .keyUp:
            if let pendingKey, pendingKey.0 == Int(event.keyCode) { finish(.key(keyCode: pendingKey.0, modifiers: pendingKey.1)) }
        default:
            break
        }
    }

    func finish(_ new: Shortcut) {
        stop()
        save(new)
    }
}

// MARK: - Microphone (D9)

struct MicrophoneSettings: View {
    let model: HubModel
    @State private var devices = AudioDevices.inputs()
    @State private var selected = AppSettings.shared.microphoneUID ?? ""
    @State private var testing = false

    var body: some View {
        Picker("Input", selection: $selected) {
            Text("System default").tag("")
            ForEach(devices) { Text($0.name + ($0.isDefault ? " (default)" : "")).tag($0.uid) }
        }
        .onChange(of: selected) { model.controller.selectMicrophone(uid: selected.isEmpty ? nil : selected) }
        HStack {
            Button(testing ? "Stop test" : "Test microphone") { toggleTest() }
            LevelMeter(level: testing ? model.micLevel : 0)
        }
        .onDisappear { if testing { toggleTest() } }
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected)) { _ in devices = AudioDevices.inputs() }
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureDeviceWasDisconnected)) { _ in devices = AudioDevices.inputs() }
    }

    func toggleTest() {
        if testing { model.controller.stopMicTest(); testing = false } else { testing = model.controller.startMicTest() }
    }
}

struct LevelMeter: View {
    let level: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Double(i) / 16 < level ? (i > 12 ? Color.orange : Color.green) : Color.secondary.opacity(0.2))
                    .frame(width: 6, height: 14)
            }
        }
        .animation(.linear(duration: 0.08), value: level)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}
