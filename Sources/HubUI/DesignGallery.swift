import AppKit
import MurmurKit
import SwiftUI
import UI

/// Debug-only window listing every component in every state, light and dark side by side (U2).
/// Rendered by `murmur-snap` into `Artifacts/ui/<set>/gallery.png`.
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
    @State private var sounds = "sur-sha"
    @State private var notes = "Thanks,\nSwarit"
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var tab = "work"
    @State private var level = "medium"
    @State private var engine = "parakeet"

    static let states = InteractionState.allCases

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 28) {
            Text(title).textStyle(TypeTokens.stepTitle).foregroundStyle(c.textPrimary.color)

            GallerySection("Brand") {
                HStack(alignment: .center, spacing: 24) {
                    BrandMark(height: HubGeometry.brandMarkHeight)
                    BrandMark(height: 44)
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    FlowIdlePill()
                }
                HStack(spacing: 16) {
                    ForEach(MenuBarGlyph.State.allCases, id: \.self) { state in
                        VStack(spacing: 6) {
                            let image = MenuBarGlyph.image(state, phase: 0.3, dark: theme.scheme == .dark)
                            Image(nsImage: image)
                                .renderingMode(image.isTemplate ? .template : .original)
                                .foregroundStyle(c.textPrimary.color)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(RoundedRectangle(cornerRadius: 5).fill(c.bgPanel.color))
                            Text(state.rawValue).textStyle(TypeTokens.tag).foregroundStyle(c.textTertiary.color)
                        }
                    }
                }
            }

            GallerySection("Icons") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), alignment: .center), count: 8), spacing: 12) {
                    ForEach(Icon.allCases, id: \.self) { icon in
                        VStack(spacing: 6) {
                            IconView(icon, size: 18, color: c.textPrimary.color)
                            Text(icon.rawValue).textStyle(TypeTokens.tag).foregroundStyle(c.textTertiary.color).lineLimit(1)
                        }
                    }
                }
            }

            GallerySection("Type") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(TypeTokens.all, id: \.0) { name, style in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(name).textStyle(TypeTokens.tag).foregroundStyle(c.textTertiary.color).frame(width: 90, alignment: .leading)
                            Text(style.family == .serif ? "Say it once. “no wait, let’s ship Friday”" : "Paste last transcript ⌥ Space 0:07 · 24 w")
                                .textStyle(style).foregroundStyle(c.textPrimary.color).lineLimit(1)
                        }
                    }
                    SerifTitle("Welcome back, ", italic: "Swarit")
                }
            }

            GallerySection("Colors") {
                let swatches: [(String, ColorToken)] = [
                    ("bg-window", c.bgWindow), ("bg-panel", c.bgPanel), ("bg-sunken", c.bgSunken), ("fill-hover", c.fillHover),
                    ("fill-selected", c.fillSelected), ("fill-chip", c.fillChip), ("text-primary", c.textPrimary), ("text-secondary", c.textSecondary),
                    ("text-tertiary", c.textTertiary), ("stone", c.stone), ("border-hairline", c.borderHairline), ("border-divider", c.borderDivider),
                    ("border-control", c.borderControl), ("accent-clay", c.accentClay), ("clay-pressed", c.accentClayPressed), ("ink-fill", c.inkFill),
                    ("focus-ring", c.focusRing), ("flow-fill", theme.flow.flowFill), ("flow-live", theme.flow.flowLive), ("flow-cancel", theme.flow.flowCancel),
                ]
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(118), alignment: .leading), count: 5), spacing: 10) {
                    ForEach(swatches, id: \.0) { name, token in
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 8).fill(token.color).frame(height: 36)
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(c.borderHairline.color, lineWidth: 1))
                            Text(name).textStyle(TypeTokens.tag).foregroundStyle(c.textSecondary.color)
                            Text(token.hex).textStyle(TypeTokens.tag).foregroundStyle(c.textTertiary.color)
                        }
                    }
                }
            }

            GallerySection("Buttons (normal, hover, pressed, focused, disabled)") {
                ForEach([MButton.Kind.primary, .ink, .outline, .link], id: \.self) { kind in
                    HStack(spacing: 12) {
                        ForEach(Self.states, id: \.self) { state in
                            MButton("Set up styles", icon: kind == .ink ? .plus : nil, kind: kind) {}
                                .environment(\.forcedInteraction, state)
                                .disabled(state == .disabled)
                        }
                    }
                }
                HStack(spacing: 12) {
                    MButton("Primary S", kind: .primary, size: .small) {}
                    MButton("Ink S", kind: .ink, size: .small) {}
                    MButton("Change", kind: .outline, size: .small) {}
                    MButton("Undo", kind: .link, size: .small) {}
                    MButton("Disabled", kind: .outline, size: .small) {}.disabled(true)
                    ForEach(Self.states, id: \.self) { state in
                        MIconButton(.copy, label: "Copy", size: .small) {}.environment(\.forcedInteraction, state).disabled(state == .disabled)
                    }
                    MIconButton(.bell, label: "Notifications") {}
                }
            }

            GallerySection("Toggles, radios, chips") {
                HStack(spacing: 16) {
                    MToggle(isOn: $toggleOn, label: "On")
                    MToggle(isOn: $toggleOff, label: "Off")
                    MToggle(isOn: $toggleOn, label: "Small", size: .small)
                    MToggle(isOn: $toggleOff, label: "Disabled").disabled(true)
                    MToggle(isOn: $toggleOn, label: "Disabled on").disabled(true)
                    MToggle(isOn: $toggleOn, label: "Focused").environment(\.forcedInteraction, .focused)
                    MRadio(selected: false)
                    MRadio(selected: true)
                }
                HStack(spacing: 8) {
                    MChip("English (US)", selected: true) {}
                    MChip("Français", selected: false) {}
                    MChip("Deutsch", selected: false) {}.environment(\.forcedInteraction, .hover)
                    MChip("日本語", selected: false) {}.environment(\.forcedInteraction, .focused)
                }
            }

            GallerySection("Segmented and select") {
                MSegmented(selection: $tab, items: [("personal", "Personal messages"), ("work", "Work messages"), ("email", "Email"), ("other", "Other")])
                HStack(spacing: 12) {
                    MSegmented(selection: $level, items: [("none", "None"), ("light", "Light"), ("medium", "Medium")], size: .small)
                    MSegmented(selection: $level, items: [("none", "None"), ("light", "Light"), ("medium", "Medium")], size: .small)
                        .environment(\.forcedInteraction, .focused)
                    MSegmented(selection: $level, items: [("none", "None"), ("light", "Light")], size: .small).disabled(true)
                }
                HStack(spacing: 12) {
                    MSelect("Microphone", selection: $engine, options: [("parakeet", "Studio USB Mic"), ("built", "MacBook Pro Microphone")])
                    MSelect("Engine", selection: $engine, options: [("parakeet", "parakeet-v3"), ("built", "whisper")], mono: true)
                    MSelect("Hover", selection: $engine, options: [("parakeet", "Hover")]).environment(\.forcedInteraction, .hover)
                    MSelect("Focused", selection: $engine, options: [("parakeet", "Focused")]).environment(\.forcedInteraction, .focused)
                    MNavigateSelect("Languages", value: "English (US), Español") {}
                }
            }

            GallerySection("Fields") {
                HStack(spacing: 12) {
                    MTextField("Word or phrase", text: $text)
                    MTextField("Word", text: $filled)
                    MTextField("Focused", text: $filled).environment(\.forcedInteraction, .focused)
                }
                HStack(spacing: 12) {
                    MTextField("Sounds like (optional)", text: $sounds, quote: true)
                    MSearchField("Search 8 words", text: $text).frame(width: 260)
                    MTextField("Disabled", text: $text).disabled(true)
                }
                MTextField("Expansion", text: $notes, multiline: true)
            }

            GallerySection("Key caps, tags, stats, app tiles") {
                HStack(spacing: 8) {
                    MKeycap("fn")
                    MShortcut(["⌥", "Space"])
                    MKeycap("[HOTKEY]", pressed: true)
                    MShortcut(["⌃", "⌘", "V"], size: .inline)
                    MKeycap("esc", size: .inline, onWindow: true)
                }
                HStack(spacing: 8) {
                    MTag("added")
                    MTag("learned", kind: .filled)
                    MStatStrip(["7-day streak", "6,343 words", nil, "112 wpm"])
                    MAppTile(.mail)
                    MAppTile(.chat)
                    MAppTile(.code)
                    MAppTile(.mic, faint: true)
                }
            }

            GallerySection("Cards") {
                HStack(alignment: .top, spacing: 12) {
                    let cards: [(Bool, InteractionState?)] = [(false, nil), (true, nil), (false, .hover), (false, .focused)]
                    ForEach(cards.indices, id: \.self) { i in
                        let (selected, state) = cards[i]
                        MSelectableCard(selected: selected, label: "Casual", action: {}) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Casual").textStyle(TypeTokens.cardTitle).foregroundStyle(c.textPrimary.color)
                                Text("Caps · lighter punctuation").textStyle(TypeTokens.tag).foregroundStyle(c.textTertiary.color)
                                MWell { Text("Hey team, build’s ready for review.").textStyle(TypeTokens.sample).foregroundStyle(c.textPrimary.color) }
                            }
                        }
                        .environment(\.forcedInteraction, state)
                    }
                }
                .frame(height: 170)
                MFeatureCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SerifTitle("Make Murmur sound like ", italic: "you", style: TypeTokens.featureTitle)
                        Text("Pick a style for messages, work chats and email.").textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
                        HStack(spacing: 18) {
                            MButton("Set up styles", kind: .primary) {}
                            MButton("Not now", kind: .link) {}
                        }
                    }
                } visual: {
                    MCard(padding: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            MAppTile(.chat)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Messages · very casual").textStyle(TypeTokens.tag).foregroundStyle(c.textTertiary.color)
                                Text("running 10 min late, save me a seat?").textStyle(TypeTokens.sample).foregroundStyle(c.textPrimary.color)
                            }
                        }
                    }
                    .frame(width: 240)
                }
            }

            GallerySection("Sidebar and status") {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 2) {
                        MSidebarItem("Home", icon: .home, selected: true) {}
                        MSidebarItem("Dictionary", icon: .dictionary, selected: false) {}
                        MSidebarItem("Snippets", icon: .snippet, selected: false) {}.environment(\.forcedInteraction, .hover)
                        MSidebarItem("Style", icon: .style, selected: false) {}.environment(\.forcedInteraction, .focused)
                    }
                    .frame(width: 208)
                    MStatusCard(title: "Ready", hotkey: "fn", microphone: "Studio USB Mic").frame(width: 208)
                    MStatusCard(title: "Listening…", hotkey: "fn", microphone: "Studio USB Mic", live: true).frame(width: 208)
                }
            }

            GallerySection("List") {
                MList(Array(0..<3), id: \.self) { i in
                    MListRow(actions: [RowAction(.copy, "Copy") {}, RowAction(.clipboard, "Paste again") {}]) {
                        HStack(spacing: 14) {
                            Text(["9:41", "9:32", "9:05"][i]).textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color).frame(width: 52, alignment: .leading)
                            MAppTile([Icon.mail, .chat, .mic][i], faint: i == 2)
                            Text(["Hi Priya, thanks for the notes.", "running 10 min late, save me a seat?", "Audio was silent"][i])
                                .textStyle(TypeTokens.body).foregroundStyle(i == 2 ? c.textTertiary.color : c.textPrimary.color)
                        }
                    } trailing: {
                        Text(["Mail · 15 w", "Messages · 7 w", "0 w"][i]).textStyle(TypeTokens.meta).foregroundStyle(c.textTertiary.color)
                    }
                    .environment(\.forcedInteraction, i == 1 ? .hover : nil)
                }
            }

            GallerySection("Settings") {
                MSettingsGroup("Output") {
                    MToggleRow("Sounds", detail: "Start, stop and error cues.", isOn: $toggleOn)
                    MSettingsRow("Auto cleanup", detail: "See examples on the Style page.") {
                        MSegmented(selection: $level, items: [("none", "None"), ("light", "Light"), ("medium", "Medium")], size: .small)
                    }
                    MSettingsRow("Push-to-talk", detail: "Hold to speak, release to type.") {
                        HStack(spacing: 6) { MKeycap("fn", onWindow: true); MButton("Change", kind: .outline, size: .small) {} }
                    }
                }
                MInfoCard("On this Mac by default", detail: "With the built-in models, your audio and transcripts stay on this Mac. Retention and cloud keys live under Data & privacy.")
            }

            GallerySection("Toast, tooltip, dialog") {
                HStack(spacing: 16) {
                    MPaperToast("Added to Dictionary", detail: "“Saoirse”", actionTitle: "Undo")
                    TooltipPill(text: "Audio was silent: nothing was typed")
                }
                MDialog("Help & setup") {
                    Text("Shortcuts, permissions and the setup guide.").textStyle(TypeTokens.body).foregroundStyle(c.textSecondary.color)
                    HStack { Spacer(); MButton("Done", kind: .ink) {} }
                }
            }

            GallerySection("Empty state, level meter") {
                HStack(alignment: .center, spacing: 16) {
                    MEmptyState("Hold fn and speak. Your dictations will appear here.", buttonTitle: "Try it").frame(width: 320)
                    MLevelMeter(level: 0.35)
                    MLevelMeter(level: 0.85)
                }
            }

            GallerySection("Flow Bar") {
                LazyVGrid(columns: [GridItem(.fixed(300), alignment: .topLeading), GridItem(.fixed(300), alignment: .topLeading)], spacing: 12) {
                    ForEach(Array(Self.flowModels.enumerated()), id: \.offset) { index, model in
                        FlowGalleryCell(name: FlowBarState.gallery[index].name, model: model)
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 760, alignment: .leading)
        .background(c.bgWindow.color)
    }

    /// One forced model per Flow Bar gallery state.
    static let flowModels: [FlowBarModel] = FlowBarState.gallery.map { entry in
        let model = FlowBarModel()
        model.force(entry)
        return model
    }
}

/// One Flow Bar state at 60% on the window background, named.
struct FlowGalleryCell: View {
    @Environment(\.theme) private var theme
    let name: String
    let model: FlowBarModel
    static let scale: CGFloat = 0.6

    var body: some View {
        let canvas = FlowBarController.canvas
        VStack(alignment: .leading, spacing: 4) {
            Text(name).textStyle(TypeTokens.tag).foregroundStyle(theme.colors.textTertiary.color)
            FlowBarView(model: model)
                .frame(width: canvas.width, height: canvas.height)
                .scaleEffect(Self.scale, anchor: .topLeading)
                .frame(width: canvas.width * Self.scale, height: canvas.height * Self.scale, alignment: .topLeading)
                .background(theme.colors.bgSunken.color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
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
            MCaption(title)
            content
        }
    }
}
