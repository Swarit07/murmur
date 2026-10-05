import MurmurKit
import SwiftUI
import UI

/// The Style page (UI_REDESIGN.md v2 §5.3): how Murmur writes in each kind of app, then Auto cleanup.
/// Behaves as before (S4): one style per category, the cleanup level, and the AI edits switch.
struct StylePage: View {
    let model: HubModel
    @Environment(\.theme) private var theme
    @State private var level = AppSettings.shared.cleanupLevel
    @State private var category = "personal"
    @State private var styles = AppSettings.shared.styles
    @State private var transforms = AppSettings.shared.transformsEnabled

    static let categories = [("personal", "Personal messages"), ("work", "Work messages"), ("email", "Email"), ("other", "Other")]
    static let apps = [
        "personal": "Messages, WhatsApp, Telegram, Signal, Discord, Messenger and LINE, in the app or on the web.",
        "work": "Slack, Microsoft Teams, Zoom, Google Chat, Mattermost and Webex.",
        "email": "Mail, Outlook, Spark, Superhuman, Mimestream, and Gmail, Outlook, Yahoo, Fastmail, Proton and HEY on the web.",
        "other": "Everything else, including AI assistants like ChatGPT and Claude, terminals and code editors.",
    ]

    /// Names are written in their own style (S4); the examples are the app's own.
    static let styleOptions: [(id: String, name: String, detail: String, example: String, categories: Set<String>)] = [
        ("formal", "Formal.", "Caps · full punctuation", "Hey, are you free for lunch tomorrow? Let's do 12 if that works.", ["personal", "work", "email", "other"]),
        ("casual", "Casual", "Caps · lighter punctuation", "Hey are you free for lunch tomorrow? Let's do 12 if that works", ["personal", "work", "email", "other"]),
        ("veryCasual", "very casual", "lowercase · minimal punctuation", "hey are you free for lunch tomorrow? let's do 12 if that works", ["personal"]),
        ("excited", "Excited!", "Caps · more exclamation", "Hey, are you free for lunch tomorrow? Let's do 12 if that works!", ["work", "email", "other"]),
    ]

    static let spoken = "um so I think we should uh move the launch to Friday"
    static let cleanupLevels: [(id: String, name: String, detail: String, result: String)] = [
        ("none", "None", "Exactly what you said, word for word.", spoken),
        ("light", "Light", "Removes filler words and fixes grammar.", "I think we should move the launch to Friday."),
        ("medium", "Medium", "Also tightens the wording.", "Let's move the launch to Friday."),
    ]

    var body: some View {
        let c = theme.colors
        let options = Self.styleOptions.filter { $0.categories.contains(category) }
        HubPageScroll {
            HubPageHeader("Style", subtitle: "How Murmur writes in each kind of app. It looks at the app you’re typing in and uses the matching style.",
                          subtitleWidth: HubGeometry.styleSubtitleMaxWidth)
            MSegmented("App type", selection: $category, items: Self.categories)
            VStack(alignment: .leading, spacing: Spacing.s10) {
                HStack(alignment: .top, spacing: HubGeometry.cardGap) {
                    ForEach(options, id: \.id) { option in
                        MSelectableCard(selected: (styles[category] ?? "formal") == option.id, label: option.name) {
                            styles[category] = option.id
                            model.settings.styles = styles
                        } content: {
                            VStack(alignment: .leading, spacing: HubGeometry.styleCardGap) {
                                Text(option.name).textStyle(TypeTokens.cardTitle).foregroundStyle(c.textPrimary.color)
                                Text(option.detail).textStyle(TypeTokens.tagTight).foregroundStyle(c.textTertiary.color)
                                MWell { Text(option.example).textStyle(TypeTokens.sample).foregroundStyle(c.textPrimary.color).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                    }
                }
                Text(Self.apps[category] ?? "").textStyle(TypeTokens.hint).foregroundStyle(c.textTertiary.color)
            }
            Hairline().padding(.vertical, HubGeometry.styleDividerMargin)
            HStack(alignment: .bottom, spacing: Spacing.s24) {
                VStack(alignment: .leading, spacing: Spacing.s4 + Spacing.s4 / 2) {
                    MCaption("Auto cleanup")
                    Text("How much Murmur tidies what you said before it types. Applies to every style.")
                        .textStyle(TypeTokens.lead).foregroundStyle(c.textSecondary.color).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.s16)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s10) {
                    Text("You said").textStyle(TypeTokens.tagTight).foregroundStyle(c.textTertiary.color)
                    Text("“\(Self.spoken)”").textStyle(TypeTokens.quote).foregroundStyle(c.textPrimary.color)
                }
            }
            HStack(alignment: .top, spacing: HubGeometry.cardGap) {
                ForEach(Self.cleanupLevels, id: \.id) { option in
                    MSelectableCard(selected: level == option.id, label: "\(option.name) cleanup", padding: HubGeometry.cleanupCardPadding.height) {
                        setLevel(option.id)
                    } content: {
                        VStack(alignment: .leading, spacing: Spacing.s8) {
                            Text(option.name).textStyle(TypeTokens.label).foregroundStyle(c.textPrimary.color)
                            Text(option.detail).textStyle(TypeTokens.hint).foregroundStyle(c.textSecondary.color).fixedSize(horizontal: false, vertical: true)
                            Text(option.result).textStyle(TypeTokens.sample).foregroundStyle(c.textPrimary.color).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, HubGeometry.cleanupCardPadding.width - HubGeometry.cleanupCardPadding.height)
                    }
                }
            }
            .disabled(!transforms)
            .opacity(transforms ? 1 : OpacityTokens.disabledGroup)
            MSettingsGroup(footer: "Names, numbers and negations are never changed. With AI edits off, Murmur still removes fillers and applies spoken punctuation, your dictionary and snippets.") {
                MToggleRow("AI edits", detail: "Let the cleanup model edit what you said.", isOn: $transforms)
            }
        }
        .onChange(of: transforms) { model.settings.transformsEnabled = transforms }
    }

    func setLevel(_ value: String) {
        level = value
        model.settings.cleanupLevel = value
    }
}
