import AppKit
import MurmurKit
import SwiftUI

// Plain windows until the Hub in Milestone 4 gathers them into pages.

/// S1: words and phrases Murmur should get right. "Write" is the spelling to insert; "Heard as" lists
/// what the engine tends to hear instead (optional), separated by commas.
struct DictionaryView: View {
    let store: HistoryStore
    @State private var entries: [DictionaryRecord] = []
    @State private var selection: DictionaryRecord.ID?
    @State private var newWord = ""
    @State private var newHeard = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Word or phrase, e.g. Siobhan", text: $newWord)
                TextField("Heard as (optional), e.g. Chivan, Shivon", text: $newHeard)
                Button("Add", action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.return, modifiers: [])
            }
            .textFieldStyle(.roundedBorder)
            .padding(10)
            Table(entries, selection: $selection) {
                TableColumn("Write") { e in
                    EditableCell(text: e.replacement) { value in
                        var updated = e
                        updated.replacement = value
                        if e.term == e.replacement { updated.term = value }
                        try? store.save(updated)
                    }
                }
                TableColumn("Heard as") { e in
                    EditableCell(text: e.term == e.replacement ? "" : e.term, placeholder: "—") { value in
                        var updated = e
                        updated.term = value.isEmpty ? e.replacement : value
                        try? store.save(updated)
                    }
                }
                TableColumn("Added") { e in Text(e.source == .suggested ? "Suggested" : e.createdAt.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary) }
                    .width(min: 80, ideal: 100, max: 120)
            }
            .contextMenu(forSelectionType: DictionaryRecord.ID.self) { ids in
                Button("Delete") { ids.forEach { try? store.deleteDictionaryEntry(id: $0) } }
            }
            .onDeleteCommand { if let selection { try? store.deleteDictionaryEntry(id: selection) } }
            Text("Dictionary words guide the speech engine, fix spellings after transcription, and are given to the cleanup model.")
                .font(.caption).foregroundStyle(.secondary).padding(8)
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.vocabularyDidChange).receive(on: RunLoop.main)) { _ in reload() }
    }

    func reload() { entries = (try? store.dictionary()) ?? [] }

    func add() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        let heard = newHeard.trimmingCharacters(in: .whitespaces)
        try? store.save(DictionaryRecord(term: heard.isEmpty ? word : heard, replacement: word))
        newWord = ""
        newHeard = ""
    }
}

/// S3: say the cue, get the expansion, untouched by cleanup.
struct SnippetsView: View {
    let store: HistoryStore
    @State private var snippets: [SnippetRecord] = []
    @State private var selection: SnippetRecord.ID?
    @State private var cue = ""
    @State private var expansion = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Say this, e.g. my email", text: $cue)
                    Button("Add", action: add).disabled(cue.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
                }
                TextField("Insert this", text: $expansion, axis: .vertical).lineLimit(1...4)
            }
            .textFieldStyle(.roundedBorder)
            .padding(10)
            Table(snippets, selection: $selection) {
                TableColumn("Say") { s in
                    EditableCell(text: s.cue) { value in
                        var updated = s
                        updated.cue = value
                        try? store.save(updated)
                    }
                }
                .width(min: 120, ideal: 160, max: 220)
                TableColumn("Insert") { s in
                    EditableCell(text: s.expansion) { value in
                        var updated = s
                        updated.expansion = value
                        try? store.save(updated)
                    }
                }
            }
            .contextMenu(forSelectionType: SnippetRecord.ID.self) { ids in
                Button("Delete") { ids.forEach { try? store.deleteSnippet(id: $0) } }
            }
            .onDeleteCommand { if let selection { try? store.deleteSnippet(id: selection) } }
            Text("Snippets are inserted exactly as written; cleanup never changes them.")
                .font(.caption).foregroundStyle(.secondary).padding(8)
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.vocabularyDidChange).receive(on: RunLoop.main)) { _ in reload() }
    }

    func reload() { snippets = (try? store.snippets()) ?? [] }

    func add() {
        try? store.save(SnippetRecord(cue: cue.trimmingCharacters(in: .whitespaces), expansion: expansion))
        cue = ""
        expansion = ""
    }
}

/// A table cell that edits in place and saves on Return or when focus leaves.
struct EditableCell: View {
    let text: String
    var placeholder = ""
    let save: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { draft = text }
            .onChange(of: text) { draft = text }
            .onSubmit { commit() }
            .onChange(of: focused) { if !focused { commit() } }
    }

    func commit() {
        let value = draft.trimmingCharacters(in: .whitespaces)
        if value != text { save(value) }
    }
}

/// T3: automatic detection, or the languages you speak.
struct LanguagePicker: View {
    let settings: AppSettings
    @State private var chosen: Set<String> = Set(AppSettings.shared.languages)

    static let common: [(String, String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"),
        ("nl", "Dutch"), ("pl", "Polish"), ("sv", "Swedish"), ("da", "Danish"), ("fi", "Finnish"), ("ro", "Romanian"),
        ("cs", "Czech"), ("hu", "Hungarian"), ("el", "Greek"), ("uk", "Ukrainian"), ("ru", "Russian"),
    ]

    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Detect automatically", isOn: Binding(get: { chosen.isEmpty }, set: { if $0 { chosen = []; save() } }))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading) {
                ForEach(Self.common, id: \.0) { code, name in
                    Toggle(name, isOn: Binding(get: { chosen.contains(code) }, set: { on in
                        if on { chosen.insert(code) } else { chosen.remove(code) }
                        save()
                    }))
                }
            }
            Text(chosen.count == 1 ? "Transcribed as \(Self.common.first { $0.0 == chosen.first }?.1 ?? "") only." : "Murmur detects the language of each dictation. Choosing one language helps it avoid stray words from other languages.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    func save() { settings.languages = chosen.sorted() }
}
