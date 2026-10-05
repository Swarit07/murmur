import MurmurKit
import SwiftUI
import UI

/// A Hub page's header (§5.3): the Newsreader title with a one-line description under it, and an
/// optional action aligned to its bottom on the right.
struct HubPageHeader<Action: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String
    let subtitleWidth: CGFloat
    let action: Action

    init(_ title: String, subtitle: String, subtitleWidth: CGFloat = HubGeometry.subtitleMaxWidth, @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleWidth = subtitleWidth
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.s24) {
            VStack(alignment: .leading, spacing: HubGeometry.titleToSubtitle) {
                SerifTitle(title)
                Text(subtitle)
                    .textStyle(TypeTokens.lead)
                    .foregroundStyle(theme.colors.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: subtitleWidth, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
    }
}

/// A page's scrolling body with the board's padding (44 top, 56 sides) and a drag strip at the top.
struct HubPageScroll<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = HubGeometry.sectionGap, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(.top, HubGeometry.pagePaddingTop)
                .padding(.horizontal, HubGeometry.pagePaddingSide)
                .padding(.bottom, HubGeometry.pagePaddingTop)
                .frame(maxWidth: HubGeometry.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .top) { WindowDragArea().frame(height: HubGeometry.pagePaddingTop / 2) }
    }
}

/// A paper toast at the bottom center of the panel, 22 pt above its edge, that leaves on its own.
struct PaperToastState: Equatable {
    var text: String
    var detail: String?
    var id = UUID()
}

struct PaperToastHost: ViewModifier {
    @Environment(\.theme) private var theme
    @Binding var toast: PaperToastState?
    let undo: (() -> Void)?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                MPaperToast(toast.text, detail: toast.detail, actionTitle: undo == nil ? nil : "Undo") {
                    undo?()
                    self.toast = nil
                }
                .padding(.bottom, HubGeometry.paperToastBottom)
                .transition(.opacity.combined(with: .offset(y: theme.motion.offset(MotionTokens.toastRise))))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(theme.motion.seconds(MotionTokens.paperToast)))
                    if self.toast?.id == toast.id { self.toast = nil }
                }
            }
        }
        .animation(theme.motion.easeOut(MotionTokens.toastIn), value: toast)
    }
}

extension View {
    func paperToast(_ toast: Binding<PaperToastState?>, undo: (() -> Void)? = nil) -> some View {
        modifier(PaperToastHost(toast: toast, undo: undo))
    }
}

/// How often a word or a snippet's text appears in recent History (the "N uses" counts).
enum UsageCounts {
    static func texts(_ store: HistoryStore) -> [String] {
        ((try? store.recent(limit: 1000)) ?? []).compactMap { $0.bestText?.lowercased() }
    }

    static func count(_ needle: String, in texts: [String]) -> Int {
        let n = needle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return 0 }
        return texts.reduce(0) { $0 + ($1.contains(n) ? 1 : 0) }
    }
}
