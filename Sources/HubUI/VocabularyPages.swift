import AppKit
import MurmurKit
import SwiftUI
import UI

// MARK: - Dictionary (S1)

/// The Dictionary page (UI_REDESIGN.md v2 §5.3): words Murmur should always spell right, with what the
/// engine tends to hear instead ("sounds like"). One bordered list; the add and edit row works in
/// place; a paper toast confirms a new word with Undo. Behaves as before: add, edit, delete, search.
struct DictionaryPage: View {
    let store: HistoryStore
    @Environment(\.theme) private var theme
    @State private var entries: [DictionaryRecord] = []
    @State private var uses: [String: Int] = [:]
    @State private var search = ""
    @State private var filter = "all"
    @State private var editing: String?
    @State private var adding = false
    @State private var word = ""
    @State private var sounds = ""
    @State private var toast: PaperToastState?
    @State private var lastAdded: DictionaryRecord?

    var shown: [DictionaryRecord] {
        entries.filter { e in
            (filter == "all" || (filter == "added") == (e.source == .manual))
                && (search.isEmpty || e.replacement.localizedCaseInsensitiveContains(search) || e.term.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        let c = theme.colors
        HubPageScroll {
            HubPageHeader("Dictionary", subtitle: "Names and words Murmur should always spell right. They’re also passed to the speech engine as hints.") {
                MButton("Add word", icon: .plus, kind: .ink) { startAdding() }
            }
            HStack(spacing: Spacing.s16) {
                MSearchField(entries.isEmpty ? "Search words" : "Search \(entries.count) \(entries.count == 1 ? "word" : "words")", text: $search)
                    .frame(minWidth: HubGeometry.searchFieldMin, idealWidth: HubGeometry.searchFieldWidth, maxWidth: HubGeometry.searchFieldWidth)
                Spacer(minLength: 0)
                MSegmented("Filter", selection: $filter, items: [("all", "All"), ("added", "Added by you"), ("learned", "Learned")])
            }
            if entries.isEmpty && !adding {
                MEmptyState("Add names, product names and jargon Murmur gets wrong. If it keeps hearing a word one way (“Chivan” for Siobhan), put that under Sounds like.",
                            buttonTitle: nil)
            } else {
                MListContainer {
                    if adding {
                        editRow { save(nil) }
                    }
                    ForEach(shown) { e in
                        if adding || e.id != shown.first?.id { Hairline() }
                        if editing == e.id {
                            editRow { save(e) }
                        } else {
                            row(e)
                        }
                    }
                    if shown.isEmpty && !adding {
                        Text("No words match.").textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
                            .padding(HubGeometry.historyRowPadding.width)
                    }
                }
            }
            Text("Dictionary words guide the speech engine, fix spellings after transcription, and are given to the cleanup model.")
                .textStyle(TypeTokens.hint)
                .foregroundStyle(c.textTertiary.color)
        }
        .paperToast($toast) {
            if let lastAdded { try? store.deleteDictionaryEntry(id: lastAdded.id) }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.vocabularyDidChange).receive(on: RunLoop.main)) { _ in reload() }
    }

    func row(_ e: DictionaryRecord) -> some View {
        let c = theme.colors
        let heard = e.term == e.replacement ? nil : e.term
        return MListRow(actions: [RowAction(.edit, "Edit") { startEditing(e) }, RowAction(.trash, "Remove") { try? store.deleteDictionaryEntry(id: e.id) }],
                        padding: CGSize(width: HubGeometry.historyRowPadding.width, height: 0), minHeight: HubGeometry.dictionaryRowHeight) {
            HStack(spacing: HubGeometry.dictionaryColumnGap) {
                Text(e.replacement).textStyle(TypeTokens.button).foregroundStyle(c.textPrimary.color).lineLimit(1)
                    .frame(width: HubGeometry.dictionaryWordColumn, alignment: .leading)
                Text(heard ?? "—").textStyle(TypeTokens.quote).foregroundStyle(heard == nil ? c.textTertiary.color : c.textSecondary.color).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MTag(e.source == .suggested ? "learned" : "added", kind: e.source == .suggested ? .filled : .outline)
                    .frame(width: HubGeometry.dictionaryTagColumn, alignment: .leading)
                Text("\(uses[e.id] ?? 0) uses").textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color)
                    .frame(width: HubGeometry.dictionaryUsesColumn, alignment: .trailing)
            }
        }
        .contextMenu {
            Button("Edit") { startEditing(e) }
            Button("Delete") { try? store.deleteDictionaryEntry(id: e.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(e.replacement)\(heard.map { ", sounds like \($0)" } ?? ""), \(e.source == .suggested ? "learned" : "added")")
    }

    /// The add and edit row: the word, what it sounds like, Cancel and Save.
    func editRow(save: @escaping () -> Void) -> some View {
        let c = theme.colors
        return HStack(spacing: Spacing.s10) {
            MTextField("Word or phrase", text: $word, autofocus: true, onSubmit: save, onCancel: cancel)
                .frame(width: HubGeometry.dictionaryWordField)
            MTextField("Sounds like (optional)", text: $sounds, quote: true, onSubmit: save, onCancel: cancel)
                .frame(width: HubGeometry.dictionarySoundsField)
            Spacer()
            Button("Cancel", action: cancel)
                .buttonStyle(.plain)
                .textStyle(TypeTokens.label.weight(400))
                .foregroundStyle(c.textSecondary.color)
                .padding(.horizontal, Spacing.s10)
            MButton("Save", kind: .ink, size: .small, action: save)
                .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, HubGeometry.editRowPadding.width)
        .padding(.vertical, HubGeometry.editRowPadding.height)
        .background(c.fillHover.color)
    }

    func reload() {
        let all = (try? store.dictionary()) ?? []
        let texts = UsageCounts.texts(store)
        uses = Dictionary(uniqueKeysWithValues: all.map { ($0.id, UsageCounts.count($0.replacement, in: texts)) })
        // Most used first, as the board orders them; ties alphabetically.
        entries = all.sorted { (uses[$0.id] ?? 0, $1.replacement.lowercased()) > (uses[$1.id] ?? 0, $0.replacement.lowercased()) }
    }

    func startAdding() {
        editing = nil
        word = ""
        sounds = ""
        adding = true
    }

    func startEditing(_ e: DictionaryRecord) {
        adding = false
        word = e.replacement
        sounds = e.term == e.replacement ? "" : e.term
        editing = e.id
    }

    func cancel() {
        adding = false
        editing = nil
    }

    /// Saves the row: a new entry, or the edited one (a plain word keeps `term` equal to the spelling).
    func save(_ existing: DictionaryRecord?) {
        let w = word.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return }
        let heard = sounds.trimmingCharacters(in: .whitespaces)
        if var e = existing {
            e.replacement = w
            e.term = heard.isEmpty ? w : heard
            try? store.save(e)
        } else {
            let record = DictionaryRecord(term: heard.isEmpty ? w : heard, replacement: w)
            try? store.save(record)
            lastAdded = record
            toast = PaperToastState(text: "Added to Dictionary", detail: "“\(w)”")
        }
        cancel()
    }
}

// MARK: - Snippets (S3)

/// The Snippets page (§5.3): say the trigger on its own and Murmur types the text in its place. Two
/// columns of cards; the expansion sits in a dashed box because it's what gets typed. Behaves as before:
/// add, edit, delete; expansions keep their line breaks.
struct SnippetsPage: View {
    let store: HistoryStore
    @Environment(\.theme) private var theme
    @State private var snippets: [SnippetRecord] = []
    @State private var uses: [String: Int] = [:]
    @State private var editing: String?
    @State private var adding = false
    @State private var cue = ""
    @State private var expansion = ""

    var body: some View {
        let c = theme.colors
        HubPageScroll(spacing: HubGeometry.snippetsSectionGap) {
            HubPageHeader("Snippets", subtitle: "Say a trigger on its own and Murmur types the full text in its place.") {
                MButton("New snippet", icon: .plus, kind: .ink) { startAdding() }
            }
            if snippets.isEmpty && !adding {
                MEmptyState("Save text you type often, like an email sign-off or your address. Say the trigger and Murmur inserts the text exactly as written.")
            } else {
                // Two columns; the cards in a row share its height, as the board's grid rows do.
                let items: [SnippetRecord?] = (adding ? [nil] : []) + snippets.map { Optional($0) }
                VStack(spacing: HubGeometry.cardGap) {
                    ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                        HStack(alignment: .top, spacing: HubGeometry.cardGap) {
                            cell(items[i])
                            if i + 1 < items.count { cell(items[i + 1]) } else { Color.clear.frame(maxWidth: .infinity) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("Snippets are inserted exactly as written; cleanup never changes them.")
                .textStyle(TypeTokens.hint)
                .foregroundStyle(c.textTertiary.color)
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.vocabularyDidChange).receive(on: RunLoop.main)) { _ in reload() }
    }

    /// One grid cell: a card, or the edit card when adding (nil) or editing it.
    @ViewBuilder func cell(_ s: SnippetRecord?) -> some View {
        if let s, editing != s.id {
            SnippetCard(snippet: s, uses: uses[s.id] ?? 0, edit: { startEditing(s) }, delete: { try? store.deleteSnippet(id: s.id) })
        } else {
            editCard { save(s) }.frame(maxHeight: .infinity, alignment: .top)
        }
    }

    func editCard(save: @escaping () -> Void) -> some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return VStack(alignment: .leading, spacing: Spacing.s10) {
            MTextField("Trigger, e.g. sign off", text: $cue, quote: true, autofocus: true, onCancel: cancel)
            MTextField("Text to type", text: $expansion, multiline: true, onCancel: cancel)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.plain)
                    .textStyle(TypeTokens.label.weight(400))
                    .foregroundStyle(c.textSecondary.color)
                    .padding(.horizontal, Spacing.s10)
                MButton("Save", kind: .ink, size: .small, action: save)
                    .disabled(cue.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
            }
        }
        .padding(HubGeometry.snippetPadding)
        .background(shape.fill(c.bgPanel.color))
        .overlay(shape.strokeBorder(c.inkFill.color, lineWidth: theme.increaseContrast ? Stroke.selectedIncreased : Stroke.selected))
    }

    func reload() {
        let all = (try? store.snippets()) ?? []
        let texts = UsageCounts.texts(store)
        uses = Dictionary(uniqueKeysWithValues: all.map { ($0.id, UsageCounts.count($0.expansion, in: texts)) })
        // Most used first, as the board orders them; ties by trigger.
        snippets = all.sorted { (uses[$0.id] ?? 0, $1.cue.lowercased()) > (uses[$1.id] ?? 0, $0.cue.lowercased()) }
    }

    func startAdding() {
        editing = nil
        cue = ""
        expansion = ""
        adding = true
    }

    func startEditing(_ s: SnippetRecord) {
        adding = false
        cue = s.cue
        expansion = s.expansion
        editing = s.id
    }

    func cancel() {
        adding = false
        editing = nil
    }

    func save(_ existing: SnippetRecord?) {
        let trigger = cue.trimmingCharacters(in: .whitespaces)
        guard !trigger.isEmpty, !expansion.isEmpty else { return }
        if var s = existing {
            s.cue = trigger
            s.expansion = expansion
            try? store.save(s)
        } else {
            try? store.save(SnippetRecord(cue: trigger, expansion: expansion))
        }
        cancel()
    }
}

/// One snippet card: the spoken trigger in italic quotes, an arrow, the use count (Edit and Delete on
/// hover), and the expansion in a dashed box.
struct SnippetCard: View {
    let snippet: SnippetRecord
    let uses: Int
    let edit: () -> Void
    let delete: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.forcedInteraction) private var forced
    @State private var hovering = false

    var body: some View {
        let c = theme.colors
        let active = hovering || forced == .hover
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let box = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.s10) {
            HStack(spacing: HubGeometry.snippetHeaderGap) {
                Text("“\(snippet.cue)”").textStyle(TypeTokens.trigger).foregroundStyle(c.textPrimary.color).lineLimit(1)
                IconView(.arrowRight, size: HubGeometry.arrowIcon, color: c.textTertiary.color)
                Spacer(minLength: Spacing.s8)
                ZStack(alignment: .trailing) {
                    Text("\(uses) uses").textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color).opacity(active ? 0 : 1)
                    HStack(spacing: HubGeometry.snippetActionsGap) {
                        MIconButton(.edit, label: "Edit snippet", size: .small, action: edit)
                        MIconButton(.trash, label: "Delete snippet", size: .small, action: delete)
                    }
                    .opacity(active ? 1 : 0)
                    .allowsHitTesting(active)
                }
                .frame(height: HubGeometry.iconButtonSmall)
            }
            // A preview: long expansions stop after a few lines (Edit shows all of it).
            Text(snippet.expansion)
                .textStyle(TypeTokens.expansion)
                .foregroundStyle(c.textPrimary.color)
                .lineLimit(HubGeometry.snippetPreviewLines)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(snippet.expansion)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HubGeometry.expansionPadding.width)
                .padding(.vertical, HubGeometry.expansionPadding.height)
                .overlay(box.strokeBorder(c.edgeKey.color, style: StrokeStyle(lineWidth: Stroke.hairline, dash: [Stroke.dash, Stroke.dash / 2])))
        }
        .padding(HubGeometry.snippetPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(c.bgPanel.color))
        .overlay(shape.strokeBorder(active ? c.inkFill.color : c.borderHairline.color,
                                    lineWidth: active ? (theme.increaseContrast ? Stroke.selectedIncreased : Stroke.selected) : Stroke.hairline))
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(theme.motion.easeOut(MotionTokens.rowActionsFade), value: active)
        .contextMenu {
            Button("Edit", action: edit)
            Button("Delete", action: delete)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Snippet \(snippet.cue)")
    }
}
