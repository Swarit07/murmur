import AppKit
import MurmurKit
import SwiftUI

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
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Detect automatically", isOn: Binding(get: { chosen.isEmpty }, set: { if $0 { chosen = []; save() } }))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), alignment: .leading, spacing: 6) {
                ForEach(Self.common, id: \.0) { code, name in
                    Toggle(name, isOn: Binding(get: { chosen.contains(code) }, set: { on in
                        if on { chosen.insert(code) } else { chosen.remove(code) }
                        save()
                    }))
                    .toggleStyle(.checkbox)
                }
            }
            Text(chosen.count == 1 ? "Transcribed as \(Self.common.first { $0.0 == chosen.first }?.1 ?? "") only." : "Murmur detects the language of each dictation. Choosing one language helps it avoid stray words from other languages.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    func save() { settings.languages = chosen.sorted() }
}

/// What an empty page shows instead of an empty table.
struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
