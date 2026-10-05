import AppKit
import MurmurKit
import SwiftUI
import UI

// MARK: - Token panel

/// Shows every token live and lets numbers and colors be edited while watching the bar. "Copy as
/// Swift" puts the current values on the clipboard for pasting into Tokens.swift.
public struct TokenPanel: View {
    /// Forces a Flow Bar state (nil clears it); the app passes the live bar's model.
    let forceState: ((FlowBarState?) -> Void)?
    @State private var debug = UIDebug.shared
    @State private var forcedName = "none"

    public init(forceState: ((FlowBarState?) -> Void)? = nil) {
        self.forceState = forceState
    }

    @State private var rows: [(key: String, value: String)] = TokenPanel.rows()
    @State private var filter = ""

    static func rows() -> [(key: String, value: String)] {
        guard let data = try? JSONEncoder().encode(LiveTokens.shared.value),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let order = Mirror(reflecting: LiveTokens.shared.value).children.compactMap(\.label)
        return order.compactMap { key in dict[key].map { (key, "\($0)") } }
    }

    /// Appearance, motion, text size and Flow Bar state overrides for design checks.
    var overrides: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Appearance")
                Picker("", selection: $debug.appearance) {
                    ForEach(UIDebug.AppearanceOverride.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .labelsHidden()
            }
            GridRow {
                Text("Reduce Motion")
                Picker("", selection: Binding(get: { debug.reduceMotion.map { $0 ? "on" : "off" } ?? "system" },
                                              set: { debug.reduceMotion = $0 == "system" ? nil : $0 == "on" })) {
                    Text("System").tag("system")
                    Text("On").tag("on")
                    Text("Off").tag("off")
                }
                .labelsHidden()
            }
            GridRow {
                Text("Time scale")
                HStack {
                    Slider(value: $debug.timeScale, in: 0.1...2)
                    Text(String(format: "%.1f×", debug.timeScale)).monospacedDigit()
                }
            }
            GridRow {
                Text("Text size")
                Picker("", selection: Binding(get: { debug.textScale ?? 0 }, set: { debug.textScale = $0 == 0 ? nil : $0 })) {
                    Text("Setting").tag(0.0)
                    Text("1.0").tag(1.0)
                    Text("1.15").tag(1.15)
                }
                .labelsHidden()
            }
            if let forceState {
                GridRow {
                    Text("Flow Bar state")
                    Picker("", selection: $forcedName) {
                        Text("Live").tag("none")
                        ForEach(FlowBarState.gallery, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                    .onChange(of: forcedName) {
                        forceState(FlowBarState.gallery.first { $0.name == forcedName }?.state)
                    }
                }
            }
        }
        .padding(10)
    }

    public var body: some View {
        VStack(spacing: 0) {
            overrides
            Divider()
            HStack {
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder)
                Button("Copy as Swift") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(LiveTokens.shared.swiftSource, forType: .string)
                }
                Button("Reset") {
                    LiveTokens.shared.reset()
                    rows = Self.rows()
                }
            }
            .padding(10)
            List {
                ForEach(rows.indices.filter { filter.isEmpty || rows[$0].key.localizedCaseInsensitiveContains(filter) }, id: \.self) { i in
                    HStack {
                        Text(rows[i].key).font(.system(.body, design: .monospaced))
                        Spacer()
                        TextField("", text: Binding(get: { rows[i].value }, set: { rows[i].value = $0 }))
                            .frame(width: 140)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { apply(i) }
                    }
                }
            }
        }
    }

    /// Writes one edited value back through JSON, so types follow the Tokens struct.
    func apply(_ i: Int) {
        guard let data = try? JSONEncoder().encode(LiveTokens.shared.value),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let key = rows[i].key, text = rows[i].value
        switch dict[key] {
        case is Bool: dict[key] = text.lowercased() == "true"
        case is NSNumber: dict[key] = Double(text) ?? dict[key]
        default: dict[key] = text
        }
        if let updated = try? JSONSerialization.data(withJSONObject: dict), let tokens = try? JSONDecoder().decode(Tokens.self, from: updated) {
            LiveTokens.shared.value = tokens
        }
        rows = Self.rows()
    }
}
