import AppKit
import MurmurKit
import SwiftUI
import UI

/// Debug-only window listing every component in every state, light and dark side by side (U2).
/// Rendered by `murmur-snap` into `Artifacts/ui/<set>/<look>/gallery.png`.
public struct DesignGallery: View {
    let scrolls: Bool

    /// `scrolls: false` lays everything out at full height (the snapshot tool renders it that way).
    public init(scrolls: Bool = true) {
        self.scrolls = scrolls
    }

    public var body: some View {
        if scrolls {
            ScrollView { columns }.frame(minWidth: 1100, minHeight: 600)
        } else {
            columns.fixedSize()
        }
    }

    var columns: some View {
        HStack(alignment: .top, spacing: 0) {
            GalleryColumn(title: "Light").environment(\.theme, Theme.light)
            GalleryColumn(title: "Dark").environment(\.theme, Theme.dark)
        }
    }
}

/// Every component under one theme.
struct GalleryColumn: View {
    @Environment(\.theme) private var theme
    let title: String
    @State private var text = ""
    @State private var filled = "Kubernetes"
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var tab = "personal"
    @State private var choice = "parakeet-ultra"
    @State private var checked = true

    static let states = InteractionState.allCases

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 28) {
            Text(title).textStyle(TypeTokens.heading).foregroundStyle(c.textTitle.color)

            GallerySection("Brand mark") {
                HStack(alignment: .bottom, spacing: 24) {
                    BrandMark(height: HubGeometry.brandMarkSidebar)
                    BrandMark(height: HubGeometry.brandMarkLarge)
                    MBadge("Personal", kind: .plan)
                }
            }

            GallerySection("Icons") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(72), alignment: .center), count: 7), spacing: 12) {
                    ForEach(Icon.allCases, id: \.self) { icon in
                        VStack(spacing: 4) {
                            IconView(icon, size: 16, color: c.textPrimary.color)
                            IconView(icon, size: 24, color: c.textPrimary.color)
                            Text(icon.rawValue).textStyle(TypeTokens.meta).foregroundStyle(c.textSecondary.color).lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                }
            }

            GallerySection("Type") {
                VStack(alignment: .leading, spacing: 6) {
                    SerifTitle("Welcome back, ", italic: "Swarit")
                    SerifTitle("Make Murmur sound like ", italic: "you", style: TypeTokens.featureTitle)
                    Text("Formal.").textStyle(TypeTokens.heading).foregroundStyle(c.textTitle.color)
                    Text("Body: Murmur adapts to messages, work chats, emails, and other apps.").textStyle(TypeTokens.body).foregroundStyle(c.textBody.color)
                    Text("Row: Can you send me the slides before the 3 pm sync?").textStyle(TypeTokens.row).foregroundStyle(c.textBody.color)
                    Text("Meta: 11:42 AM").textStyle(TypeTokens.meta).foregroundStyle(c.textSecondary.color)
                    MSectionCaption("Today")
                }
            }

            GallerySection("Colors") {
                let swatches: [(String, ColorToken)] = [
                    ("bg-window", c.bgWindow), ("bg-panel", c.bgPanel), ("bg-card", c.bgCard), ("bg-hover", c.bgHover), ("bg-chip", c.bgChip),
                    ("bg-feature", c.bgFeature), ("border-panel", c.borderPanel), ("border-control", c.borderControl), ("text-title", c.textTitle),
                    ("text-primary", c.textPrimary), ("text-body", c.textBody), ("text-secondary", c.textSecondary), ("text-disabled", c.textDisabled),
                    ("accent-clay", c.accentClay), ("accent-clay-text", c.accentClayText), ("accent-clay-tint", c.accentClayTint), ("focus-ring", c.focusRing),
                ]
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(90), alignment: .leading), count: 6), alignment: .leading, spacing: 8) {
                    ForEach(swatches, id: \.0) { name, token in
                        VStack(alignment: .leading, spacing: 2) {
                            RoundedRectangle(cornerRadius: 6).fill(token.color).frame(width: 80, height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(c.borderPanel.color))
                            Text(name).textStyle(TypeTokens.meta).foregroundStyle(c.textSecondary.color).lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                }
            }

            GallerySection("Buttons (normal, hover, pressed, focused, disabled)") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach([MButton.Kind.primary, .secondary, .ghost, .destructive], id: \.self) { kind in
                        HStack(spacing: 12) {
                            ForEach(Self.states, id: \.self) { state in
                                MButton(state.rawValue.capitalized, kind: kind) {}
                                    .environment(\.forcedInteraction, state)
                                    .disabled(state == .disabled)
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        MButton("Small", kind: .secondary, size: .sm) {}
                        MButton("Large", icon: .plus, kind: .primary, size: .lg) {}
                        ForEach(Self.states, id: \.self) { state in
                            MIconButton(.copy, label: "Copy") {}.environment(\.forcedInteraction, state).disabled(state == .disabled)
                        }
                    }
                }
            }

            GallerySection("Toggles and checkboxes") {
                HStack(spacing: 16) {
                    MToggle(isOn: $toggleOn, label: "On")
                    MToggle(isOn: $toggleOff, label: "Off")
                    MToggle(isOn: $toggleOn, label: "Focused").environment(\.forcedInteraction, .focused)
                    MToggle(isOn: $toggleOff, label: "Disabled").disabled(true)
                    MCheckbox("English", isOn: $checked)
                    MCheckbox("Spanish", isOn: .constant(false))
                    MCheckbox("Focused", isOn: .constant(false)).environment(\.forcedInteraction, .focused)
                }
            }

            GallerySection("Fields") {
                VStack(alignment: .leading, spacing: 10) {
                    MTextField("Word or phrase", text: $text)
                    MTextField("Word or phrase", text: $filled).environment(\.forcedInteraction, .focused)
                    MSearchField("Search History", text: $filled)
                    MTextField("Paste key", text: .constant("gsk_secret"), secure: true)
                    MTextField("Disabled", text: .constant("")).disabled(true)
                }
                .frame(width: 420)
            }

            GallerySection("Tabs and select") {
                VStack(alignment: .leading, spacing: 10) {
                    MTabs(selection: $tab, items: [("personal", "Personal"), ("work", "Work"), ("email", "Email"), ("other", "Other")]).frame(width: 420)
                    MTabs(selection: $tab, items: [("personal", "Personal"), ("work", "Work")]).frame(width: 260).environment(\.forcedInteraction, .focused)
                    MSelect("Speech engine", selection: $choice, options: [("parakeet-ultra", "Parakeet ultra"), ("whisper", "Whisper Turbo")])
                }
            }

            GallerySection("Cards") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        MSelectableCard(selected: true, label: "Formal.") {} content: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Formal.").textStyle(TypeTokens.heading).foregroundStyle(c.textTitle.color)
                                Text("Hey, are you free for lunch tomorrow?").textStyle(TypeTokens.body).foregroundStyle(c.textBody.color)
                            }
                        }
                        MSelectableCard(selected: false, label: "Casual") {} content: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Casual").textStyle(TypeTokens.heading).foregroundStyle(c.textTitle.color)
                                Text("Hey are you free for lunch tomorrow").textStyle(TypeTokens.body).foregroundStyle(c.textBody.color)
                            }
                        }
                        .environment(\.forcedInteraction, .hover)
                        MSelectableCard(selected: false, label: "very casual") {} content: {
                            Text("very casual").textStyle(TypeTokens.heading).foregroundStyle(c.textTitle.color)
                        }
                        .environment(\.forcedInteraction, .focused)
                    }
                    .frame(height: 120)
                    MFeatureCard(title: SerifTitle("Make Murmur sound like ", italic: "you", style: TypeTokens.featureTitle),
                                 buttonTitle: "Start now", onDismiss: {}) {
                        Text("Murmur adapts to how you write in ") + Text("messages, work chats, emails, and other apps").fontWeight(.medium) + Text(".")
                    }
                    MCard { Text("A plain card.").textStyle(TypeTokens.body).foregroundStyle(c.textBody.color) }
                }
            }

            GallerySection("Chips, badges, keycaps") {
                VStack(alignment: .leading, spacing: 12) {
                    MStatChip([("🔥", "3 days"), ("🚀", "1,204 words"), ("👋", "143 wpm")])
                    HStack(spacing: 12) {
                    MBadge("Personal", kind: .plan)
                    MBadge("Waiting", kind: .neutral)
                    MBadge("Suggested", kind: .soft)
                    MShortcut(["fn", "Space"])
                    MShortcut(["⌃", "⌘", "V"])
                    }
                }
            }

            GallerySection("Sidebar items") {
                VStack(alignment: .leading, spacing: 6) {
                    MSidebarItem("Home", icon: .home, selected: true) {}
                    ForEach([InteractionState.normal, .hover, .focused, .disabled], id: \.self) { state in
                        MSidebarItem(state.rawValue.capitalized, icon: .dictionary, selected: false) {}
                            .environment(\.forcedInteraction, state).disabled(state == .disabled)
                    }
                }
                .frame(width: HubGeometry.sidebarItemWidth)
            }

            GallerySection("List rows") {
                MList {
                    MListRow(time: "11:42 AM", text: "Can you send me the slides before the 3 pm sync?")
                    Hairline()
                    MListRow(time: "11:12 AM", text: "Thanks for the quick turnaround, this looks great. Let's ship it on Friday.",
                             actions: [RowAction(.copy, "Copy") {}, RowAction(.paste, "Paste") {}, RowAction(.trash, "Delete") {}]) {
                        Text("Mail").textStyle(TypeTokens.meta).foregroundStyle(c.textSecondary.color)
                    }
                    .environment(\.forcedInteraction, .hover)
                    Hairline()
                    MListRow(time: "10:58 AM", text: "Audio is silent", silent: true)
                }
            }

            GallerySection("Settings group") {
                MSettingsGroup("Flow Bar", footer: "Off: it appears only while you dictate.") {
                    MToggleRow("Show the Flow Bar at all times", detail: "Off: it appears only while you dictate.", isOn: $toggleOn)
                    MSettingsRow("Speech engine", detail: "Runs on this Mac.") {
                        MSelect("Speech engine", selection: $choice, options: [("parakeet-ultra", "Parakeet ultra"), ("whisper", "Whisper Turbo")])
                    }
                }
            }

            GallerySection("Dialog, toast, tooltip") {
                VStack(alignment: .leading, spacing: 12) {
                    MDialog(title: "Delete all History?", confirmTitle: "Delete", destructive: true, onCancel: {}, onConfirm: {}) {
                        Text("This cannot be undone. Your dictionary and snippets stay.").textStyle(TypeTokens.body).foregroundStyle(c.textBody.color)
                    }
                    .frame(height: 230)
                    MToast("Copied.", icon: .check)
                    TooltipPill(text: "Click or hold ⌃ Ctrl to start dictating")
                }
            }

            GallerySection("Empty state") {
                MEmptyState("Hold fn and speak. Your dictations will appear here.", buttonTitle: "Try it")
            }
        }
        .padding(28)
        .frame(width: 640, alignment: .leading)
        .background(c.bgPanel.color)
    }
}

/// A titled block in the gallery.
struct GallerySection<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MSectionCaption(title)
            content
        }
    }
}
