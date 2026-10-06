import AppKit
import SwiftUI
import UI

/// The documents a Hub dialog can show (LEGAL_DOCS.md L5): the bundled privacy notes and the
/// Acknowledgements. Both read files inside the app; nothing is fetched.
public enum HubDocument: String, Sendable, CaseIterable {
    case acknowledgements, privacy

    var title: String {
        switch self {
        case .acknowledgements: "Acknowledgements"
        case .privacy: "Privacy"
        }
    }
}

/// One block of the bundled PRIVACY.md, for `DocumentText`. A small subset of Markdown: headings,
/// paragraphs, bullets (one nesting level), numbered items and pipe tables. HTML comments and the
/// top-level title are left out (the dialog shows its own title).
enum DocumentBlock: Equatable {
    case heading(String)
    case paragraph(String)
    case bullet(String, nested: Bool)
    case numbered(String, String)
    case table(header: [String], rows: [[String]])
}

enum DocumentParser {
    static func blocks(_ markdown: String) -> [DocumentBlock] {
        var blocks: [DocumentBlock] = []
        var paragraph: [String] = []
        var table: [[String]] = []

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        func flushTable() {
            // The second row is the |---| separator.
            if let header = table.first { blocks.append(.table(header: header, rows: Array(table.dropFirst(2)))) }
            table = []
        }

        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indented = raw.prefix { $0 == " " }.count > 0
            if line.hasPrefix("|") {
                flushParagraph()
                table.append(line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) })
                continue
            }
            flushTable()
            if line.isEmpty || (line.hasPrefix("<!--") && line.hasSuffix("-->")) || line.hasPrefix("# ") {
                flushParagraph()
            } else if line.hasPrefix("#") {
                flushParagraph()
                blocks.append(.heading(String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2)), nested: indented))
            } else if let dot = line.firstIndex(of: "."), dot > line.startIndex, line[..<dot].allSatisfy(\.isNumber),
                      line[line.index(after: dot)...].hasPrefix(" ") {
                flushParagraph()
                blocks.append(.numbered(String(line[..<dot]), String(line[line.index(dot, offsetBy: 2)...])))
            } else {
                paragraph.append(line)
            }
        }
        flushTable()
        flushParagraph()
        return blocks
    }

    /// Inline Markdown (bold, italics, code). Links to web pages stay links; links to files in the
    /// repo (`SECURITY.md`) become plain text, since the app can't open them.
    static func inline(_ text: String) -> AttributedString {
        var out = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        for run in out.runs where run.link.map({ $0.scheme != "https" }) ?? false {
            out[run.range].link = nil
        }
        return out
    }
}

/// The privacy notes, rendered from the bundled PRIVACY.md.
struct DocumentText: View {
    let markdown: String?
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        if let markdown {
            VStack(alignment: .leading, spacing: Spacing.s12) {
                ForEach(Array(DocumentParser.blocks(markdown).enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .heading(let text):
                        Text(DocumentParser.inline(text)).textStyle(TypeTokens.cardTitle).foregroundStyle(c.textPrimary.color)
                            .padding(.top, Spacing.s12)
                            .accessibilityAddTraits(.isHeader)
                    case .paragraph(let text):
                        Text(DocumentParser.inline(text)).textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
                    case .bullet(let text, let nested):
                        item("•", text).padding(.leading, nested ? Spacing.s20 : 0)
                    case .numbered(let number, let text):
                        item("\(number).", text)
                    case .table(let header, let rows):
                        DocumentTable(header: header, rows: rows)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        } else {
            Text("The privacy notes are missing from this copy of Murmur. They're in PRIVACY.md in its source.")
                .textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
        }
    }

    func item(_ marker: String, _ text: String) -> some View {
        let c = theme.colors
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
            Text(marker).textStyle(TypeTokens.body).foregroundStyle(c.textTertiary.color)
            Text(DocumentParser.inline(text)).textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
        }
    }
}

/// A Markdown table as a list: the first cell as the row's label, the others as "Header: value" hints.
struct DocumentTable: View {
    let header: [String]
    let rows: [[String]]
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        MListContainer {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text(DocumentParser.inline(row.first ?? "")).textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                    ForEach(Array(row.dropFirst().enumerated()), id: \.offset) { j, cell in
                        let name = j + 1 < header.count ? header[j + 1] : ""
                        Text(DocumentParser.inline(name.isEmpty ? cell : "\(name): \(cell)"))
                            .textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HubGeometry.settingsRowPadding.width)
                .padding(.vertical, HubGeometry.settingsRowPadding.height)
                if i < rows.count - 1 { Hairline() }
            }
        }
    }
}

/// The Acknowledgements: Murmur's license, then every bundled component with its license, each row
/// opening to its full text on a sunken well. Rows start closed.
struct AcknowledgementsList: View {
    let notices: LegalDocuments.Notices?
    @Binding var expanded: Set<String>
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        if let notices {
            LazyVStack(alignment: .leading, spacing: Spacing.s20) {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text("Murmur is released under the MIT License.").textStyle(TypeTokens.body).foregroundStyle(c.textPrimary.color)
                    Text(notices.copyright).textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color)
                    Text("It's built on the open-source work below. Each part keeps its own license.")
                        .textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(notices.sections) { section in
                    VStack(alignment: .leading, spacing: HubGeometry.settingsCaptionGap) {
                        MCaption(section.title)
                        MListContainer {
                            ForEach(Array(section.entries.enumerated()), id: \.element.id) { i, entry in
                                NoticeRow(entry: entry, isOpen: expanded.contains(rowKey(section, entry)), last: i == section.entries.count - 1) {
                                    let key = rowKey(section, entry)
                                    if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            Text("The notices are missing from this copy of Murmur. They're in THIRD_PARTY_NOTICES.md in its source.")
                .textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
        }
    }

    func rowKey(_ section: LegalDocuments.Section, _ entry: LegalDocuments.Entry) -> String { "\(section.title)/\(entry.name)" }
}

struct NoticeRow: View {
    let entry: LegalDocuments.Entry
    let isOpen: Bool
    let last: Bool
    let toggle: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .center, spacing: Spacing.s12) {
                    VStack(alignment: .leading, spacing: Spacing.s4 / 2) {
                        Text(entry.name).textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                        if !entry.detail.isEmpty {
                            Text(entry.detail).textStyle(TypeTokens.hint).foregroundStyle(c.textTertiary.color)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(entry.license).textStyle(TypeTokens.meta).foregroundStyle(c.textSecondary.color)
                    IconView(isOpen ? .chevronDown : .chevronRight, size: HubGeometry.arrowIcon, color: c.textTertiary.color)
                }
                .padding(.horizontal, HubGeometry.settingsRowPadding.width)
                .padding(.vertical, HubGeometry.settingsRowPadding.height)
                .background(hovering ? c.fillHover.color : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel("\(entry.name), \(entry.license)")
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows the full license text")
            if isOpen {
                Text(LegalDocuments.reflow(entry.text))
                    .textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s12)
                    .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(c.bgSunken.color))
                    .padding(.horizontal, HubGeometry.settingsRowPadding.width)
                    .padding(.bottom, HubGeometry.settingsRowPadding.height)
            }
            if !last { Hairline() }
        }
    }
}

/// The content of a document, scrolling.
struct DocumentScroll: View {
    let document: HubDocument
    @Binding var expanded: Set<String>

    var body: some View {
        ScrollView {
            Group {
                switch document {
                case .privacy: DocumentText(markdown: LegalDocuments.privacy)
                case .acknowledgements: AcknowledgementsList(notices: LegalDocuments.notices, expanded: $expanded)
                }
            }
            .padding(.trailing, Spacing.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The Hub's document dialog: the Help & setup sheet's look, wider, with the document scrolling
/// between the title and the buttons. "Back" returns to Help & setup when it was opened from there.
struct DocumentDialog: View {
    @Bindable var model: HubModel
    let document: HubDocument

    var body: some View {
        MDialog(document.title, width: HubGeometry.documentDialogWidth) {
            DocumentScroll(document: document, expanded: $model.expandedNotices)
                .frame(maxHeight: .infinity)
            HStack(spacing: Spacing.s12) {
                if model.documentFromHelp {
                    MButton("Back", kind: .link, size: .small) {
                        model.document = nil
                        model.helpOpen = true
                    }
                }
                Spacer()
                MButton("Done", kind: .ink, size: .small) { model.document = nil }
            }
        }
        .padding(Spacing.s28)
    }
}

/// Onboarding's privacy notes: the whole 400 × 560 step, with a way back to the step.
struct OnboardingPrivacyPanel: View {
    let onClose: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: OnboardingGeometry.gap) {
            Text(HubDocument.privacy.title).textStyle(TypeTokens.stepTitle).foregroundStyle(c.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            DocumentScroll(document: .privacy, expanded: .constant([]))
            HStack {
                Spacer()
                MButton("Back to setup", kind: .ink, size: .small, action: onClose)
            }
        }
        .padding(OnboardingGeometry.padding)
        .frame(width: OnboardingGeometry.step.width, height: OnboardingGeometry.step.height, alignment: .topLeading)
        .background(c.bgWindow.color)
    }
}
