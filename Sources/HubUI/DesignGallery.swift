import AppKit
import MurmurKit
import SwiftUI
import UI

/// Debug-only window listing every component in every state (U0 scaffold; U2 fills it with the
/// redesign's components). Rendered by `murmur-snap` into `Artifacts/ui/<set>/<look>/gallery.png`.
public struct DesignGallery: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Design Gallery").font(.largeTitle.bold())
                GallerySection("Brand") {
                    HStack(spacing: 16) { BrandMark(size: 22); BrandMark(size: 44) }
                }
                GallerySection("Stat tiles") {
                    HStack(spacing: 10) {
                        StatTile(symbol: "sun.max", label: "Words today", value: "1,204")
                        StatTile(symbol: "speedometer", label: "Speaking pace", value: "143 wpm")
                    }
                }
                GallerySection("Search field") {
                    VStack(alignment: .leading, spacing: 8) {
                        SearchField(prompt: "Search History", text: .constant(""))
                        SearchField(prompt: "Search History", text: .constant("launch"))
                    }
                }
                GallerySection("Cards") {
                    HStack(alignment: .top, spacing: 10) {
                        Card(title: "Formal.", detail: "Caps and punctuation", example: "Hey, are you free for lunch?", selected: true) {}
                        Card(title: "Casual", detail: "Caps, less punctuation", example: "Hey are you free for lunch", selected: false) {}
                    }
                }
                GallerySection("Empty state") {
                    EmptyState(symbol: "character.book.closed", title: "No words yet", text: "Add names and jargon Murmur gets wrong.")
                        .frame(height: 160)
                }
                GallerySection("Flow Bar states") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), alignment: .leading)], alignment: .leading, spacing: 12) {
                        ForEach(FlowBarState.gallery.filter { $0.state != .hidden }, id: \.name) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.caption).foregroundStyle(.secondary)
                                GalleryFlowBar(state: item.state)
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A titled block in the gallery.
struct GallerySection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
    }
}

/// One Flow Bar forced into a state, at its panel size.
struct GalleryFlowBar: View {
    @State private var model = FlowBarModel()
    let state: FlowBarState

    var body: some View {
        FlowBarView(model: model)
            .frame(width: FlowBarController.canvas.width, height: FlowBarController.canvas.height)
            .background(Color.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            .onAppear {
                model.showAtAllTimes = true
                model.forced = state
            }
    }
}
