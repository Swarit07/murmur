import AppKit
import Foundation
import Testing
@testable import UI

/// Contrast (UI_REDESIGN.md v2 §3.2 and §8): every listed pair must reach the stated ratio minus 0.05.
/// Ratios are compared at the design's own precision (two decimals); translucent colors are composited
/// over their background first.
@Suite("Theme contrast")
struct ContrastTests {
    static func ratio(_ a: ColorToken, _ b: ColorToken) -> Double {
        (a.contrast(with: b) * 100).rounded() / 100
    }

    static func check(_ pairs: [(String, ColorToken, ColorToken, Double)]) {
        for (name, fg, bg, target) in pairs {
            #expect(ratio(fg, bg) >= target - 0.05 - 1e-9, "\(name): \(ratio(fg, bg)) < \(target)")
        }
    }

    @Test func lightPairs() {
        let c = ThemeColors.light
        Self.check([
            ("ink on ivory", c.textPrimary, c.bgWindow, 14.5),
            ("ink on panel", c.textPrimary, c.bgPanel, 15.6),
            ("ink on sunken", c.textPrimary, c.bgSunken, 13.1),
            ("text-secondary on ivory", c.textSecondary, c.bgWindow, 6.0),
            ("text-secondary on panel", c.textSecondary, c.bgPanel, 6.4),
            ("text-secondary on sunken", c.textSecondary, c.bgSunken, 5.4),
            ("text-tertiary on ivory", c.textTertiary, c.bgWindow, 4.7),
            ("text-tertiary on panel", c.textTertiary, c.bgPanel, 5.0),
            ("border-control on ivory", c.borderControl, c.bgWindow, 3.2),
            ("border-control on panel", c.borderControl, c.bgPanel, 3.4),
            ("on-clay", c.onClay, c.accentClay, 4.5),
            ("on-ink", c.onInk, c.inkFill, 14.5),
            ("focus ring on ivory", c.focusRing, c.bgWindow, 14.5),
        ])
    }

    @Test func darkPairs() {
        let c = ThemeColors.dark
        Self.check([
            ("ivory on window", c.textPrimary, c.bgWindow, 14.5),
            ("ivory on panel", c.textPrimary, c.bgPanel, 12.5),
            ("text-secondary on window", c.textSecondary, c.bgWindow, 6.3),
            ("text-secondary on panel", c.textSecondary, c.bgPanel, 5.4),
            ("text-tertiary on window", c.textTertiary, c.bgWindow, 5.6),
            ("text-tertiary on panel", c.textTertiary, c.bgPanel, 4.8),
            ("border-control on window", c.borderControl, c.bgWindow, 4.9),
            ("border-control on panel", c.borderControl, c.bgPanel, 4.2),
            ("ink on clay-light", c.onClay, c.accentClay, 5.1),
        ])
    }

    @Test func flowBarPairs() {
        let f = FlowBarColors.light
        Self.check([
            ("flow-text", f.flowText, f.flowFill, 14.5),
            ("flow-text-secondary", f.flowTextSecondary, f.flowFill, 5.3),
            ("flow-live", f.flowLive, f.flowFill, 5.1),
            ("stop glyph on flow-live", f.flowStopGlyph, f.flowLive, 5.1),
            ("X on flow-cancel", f.flowText, f.flowCancel, 11.2),
            ("idle mark (non-text)", f.flowIdleMark, f.flowFill, 4.0),
            ("button text on flow-button", f.flowButtonText, f.flowButton, 14.5),
        ])
    }

    /// Increase Contrast (§6.3): hairlines and dividers become control borders, tertiary text becomes
    /// secondary, the Flow Bar ring gets stronger.
    @Test func increaseContrastStrengthens() {
        for base in [ThemeColors.light, ThemeColors.dark] {
            let c = base.increasedContrast
            #expect(c.borderHairline == base.borderControl)
            #expect(c.borderDivider == base.borderControl)
            #expect(c.textTertiary == base.textSecondary)
        }
        #expect(FlowBarColors.light.increasedContrast.flowRing.a > FlowBarColors.light.flowRing.a)
    }

    /// One accent (§2.8): every token outside the clay family and the Flow Bar's live clay is a neutral.
    @Test func clayIsTheOnlyAccent() {
        func neutrals(_ value: Any, skip: Set<String>) -> [(String, ColorToken)] {
            Mirror(reflecting: value).children.compactMap { child in
                guard let name = child.label, let token = child.value as? ColorToken, !skip.contains(name) else { return nil }
                return (name, token)
            }
        }
        let themeSkip: Set<String> = ["accentClay", "accentClayHover", "accentClayPressed"]
        let flowSkip: Set<String> = ["flowLive"]
        let all = [ThemeColors.light, ThemeColors.dark].flatMap { neutrals($0, skip: themeSkip) }
            + [FlowBarColors.light, FlowBarColors.dark].flatMap { neutrals($0, skip: flowSkip) }
        for (name, token) in all {
            // Chroma: warm paper and ink stay under 0.1; the clay is about 0.47.
            let chroma = max(token.r, token.g, token.b) - min(token.r, token.g, token.b)
            #expect(chroma < 0.1, "\(name) is too colorful for a neutral (\(token.hex))")
        }
    }
}

/// `Design/tokens.json` is the source of truth for colors, type, spacing and radii (§0, U1).
@Suite("Design tokens")
struct DesignTokenTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func json() throws -> [String: Any] {
        let data = try Data(contentsOf: repo.appendingPathComponent("Design/tokens.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// "#RRGGBB" or "rgba(r,g,b,a)".
    static func parse(_ s: String) -> ColorToken? {
        if s.hasPrefix("#") { return ColorToken(s) }
        let parts = s.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        return ColorToken(r: parts[0] / 255, g: parts[1] / 255, b: parts[2] / 255, a: parts[3])
    }

    static func camel(_ kebab: String) -> String {
        let words = kebab.split(separator: "-")
        return words.enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.prefix(1).uppercased() + $0.element.dropFirst() }.joined()
    }

    static func tokens(_ value: Any) -> [String: ColorToken] {
        Mirror(reflecting: value).children.reduce(into: [:]) { result, child in
            if let name = child.label, let token = child.value as? ColorToken { result[name] = token }
        }
    }

    @Test func everyColorMatches() throws {
        let color = try #require(try Self.json()["color"] as? [String: Any])
        let list = try #require(color["tokens"] as? [[String: Any]])
        let swift: [String: [String: ColorToken]] = [
            "light": Self.tokens(ThemeColors.light).merging(Self.tokens(FlowBarColors.light)) { a, _ in a },
            "dark": Self.tokens(ThemeColors.dark).merging(Self.tokens(FlowBarColors.dark)) { a, _ in a },
        ]
        #expect(list.count >= 30)
        for entry in list {
            let name = try #require(entry["name"] as? String)
            let values = try #require(entry["value"] as? [String: String])
            for scheme in ["light", "dark"] {
                let expected = try #require(values[scheme].flatMap(Self.parse), "\(name) \(scheme) unreadable")
                let actual = try #require(swift[scheme]?[Self.camel(name)], "\(name) has no Swift token \(Self.camel(name))")
                let close = abs(actual.r - expected.r) < 0.6 / 255 && abs(actual.g - expected.g) < 0.6 / 255
                    && abs(actual.b - expected.b) < 0.6 / 255 && abs(actual.a - expected.a) < 0.001
                #expect(close, "\(name) \(scheme): \(actual.hex) ≠ \(values[scheme] ?? "")")
            }
        }
    }

    @Test func everyTypeStyleMatches() throws {
        let type = try #require(try Self.json()["type"] as? [String: Any])
        let groups = try #require(type["groups"] as? [[String: Any]])
        let swift = Dictionary(TypeTokens.all, uniquingKeysWith: { a, _ in a })
        for group in groups {
            for style in try #require(group["styles"] as? [[String: Any]]) {
                let name = try #require(style["name"] as? String)
                let token = try #require(swift[name], "no Swift style \(name)")
                func px(_ key: String) -> Double? { (style[key] as? String).flatMap { Double($0.replacingOccurrences(of: "px", with: "")) } }
                #expect(token.size == px("fontSize"), "\(name) size")
                #expect(token.lineHeight == px("lineHeight"), "\(name) line height")
                #expect(token.weight == style["fontWeight"] as? Int, "\(name) weight")
                #expect(token.italic == ((style["fontStyle"] as? String) == "italic"), "\(name) italic")
                if let spacing = px("letterSpacing") {
                    #expect(abs(token.tracking * token.size - spacing) < 0.01, "\(name) tracking")
                }
            }
        }
    }

    @Test func spacingAndRadiiMatch() throws {
        let json = try Self.json()
        let spacing = try #require((json["spacing"] as? [String: Any])?["tokens"] as? [[String: Any]])
        let scale: [CGFloat] = [Spacing.s4, Spacing.s8, Spacing.s10, Spacing.s12, Spacing.s14, Spacing.s16, Spacing.s20,
                                Spacing.s24, Spacing.s28, Spacing.s32, Spacing.s44, Spacing.s56]
        #expect(spacing.compactMap { ($0["value"] as? String).flatMap { Double($0.replacingOccurrences(of: "px", with: "")) } }.map { CGFloat($0) } == scale)
        let radius = try #require((json["radius"] as? [String: Any])?["tokens"] as? [[String: Any]])
        let radii: [String: CGFloat] = ["radius-keycap-sm": Radius.keycapSmall, "radius-keycap": Radius.keycap, "radius-control": Radius.control,
                                        "radius-button": Radius.button, "radius-card": Radius.card, "radius-card-lg": Radius.cardLarge,
                                        "radius-feature": Radius.feature]
        for entry in radius {
            guard let name = entry["name"] as? String, let expected = radii[name], let value = entry["value"] as? String else { continue }
            #expect(CGFloat(Double(value.replacingOccurrences(of: "px", with: "")) ?? -1) == expected, "\(name)")
        }
    }
}

/// Every type token resolves to the bundled face, not a fallback (§3.3).
@Suite("Fonts")
struct FontTests {
    @Test func bundledFacesRegisterAndResolve() {
        #expect(FontRegistry.registerBundledFonts())
        for name in TypeTokens.allPostScriptNames {
            let font = NSFont(name: name, size: 14)
            #expect(font?.fontName == name, "\(name) did not resolve")
        }
    }

    @Test func everyTokenUsesItsFace() {
        FontRegistry.registerBundledFonts()
        let tokens = TypeTokens.all.map(\.1) + [TypeTokens.pageTitle.italicized, TypeTokens.featureTitle.italicized, TypeTokens.nav.weight(500), TypeTokens.hint.weight(500)]
        for token in tokens {
            let font = TypeTokens.nsFont(token)
            let expected = TypeTokens.postScriptName(token.family, weight: token.weight, italic: token.italic, size: token.size)
            #expect(font.fontName == expected, "\(token) resolved to \(font.fontName)")
        }
        // Titles use the display cut; text sizes the text cut.
        #expect(TypeTokens.nsFont(TypeTokens.pageTitle).fontName == "NewsreaderDisplay-Regular")
        #expect(TypeTokens.nsFont(TypeTokens.sample).fontName == "Newsreader-Regular")
        #expect(TypeTokens.nsFont(TypeTokens.meta).fontName == "GeistMono-Regular")
    }

    @Test func textScaleNeverGoesBelowTheMinimum() {
        FontRegistry.registerBundledFonts()
        let small = TypeTokens.nsFont(TypeTokens.tag, scale: 0.5).pointSize
        let large = TypeTokens.nsFont(TypeTokens.body, scale: TypeTokens.scaleLarge).pointSize
        #expect(abs(small - TypeTokens.minimumSize) < 0.01, "tag at 0.5: \(small)")
        #expect(abs(large - TypeTokens.body.size * TypeTokens.scaleLarge) < 0.01, "body at 1.15: \(large)")
    }
}

/// Source checks (§8): the token lint passes; stone is never text; clay appears only on primary
/// buttons, the live mic, the recording menu bar icon, the brand mark and the mic-test meter; no view
/// uses a red. Files still on the lint's legacy list or the temporary v1 tokens are exempt until their
/// milestone rewrites them.
@Suite("Source checks")
struct SourceCheckTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static var legacy: Set<String> {
        let text = (try? String(contentsOf: repo.appendingPathComponent("Scripts/token-lint-legacy.txt"), encoding: .utf8)) ?? ""
        return Set(text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.isEmpty }.map { ($0 as NSString).lastPathComponent })
    }

    /// Every view source file outside the token definitions and the legacy list.
    static func viewFiles() throws -> [(String, String)] {
        var files: [(String, String)] = []
        for folder in ["Sources/UI", "Sources/HubUI", "App/Sources"] {
            let enumerator = FileManager.default.enumerator(at: repo.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                let name = url.lastPathComponent
                guard url.pathExtension == "swift", !name.hasPrefix("Tokens"), !legacy.contains(name) else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                // v1 components and the v1 Flow Bar still on the temporary V1 tokens (rebuilt in U2 and U3).
                if text.contains("theme.v1") || text.contains("V1Hub.") || text.contains("V1Flow.") { continue }
                files.append((name, text))
            }
        }
        return files
    }

    @Test func tokenLintPasses() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [Self.repo.appendingPathComponent("Scripts/check-tokens.sh").path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0, "\(output)")
    }

    @Test func stoneIsNeverText() throws {
        for (name, text) in try Self.viewFiles() {
            for line in text.split(separator: "\n") where line.contains("stone") {
                let asText = line.contains("foregroundStyle") || line.contains("foregroundColor") || line.contains(".textStyle")
                #expect(!asText, "\(name): stone used as text: \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    /// Files allowed to use `accentClay`: primary buttons, the brand mark, the recording menu bar icon,
    /// the mic-test meter, the theme and the gallery's swatches. The Flow Bar's live clay is `flowLive`.
    static let clayAllowed: Set<String> = ["MButton.swift", "BrandMark.swift", "StatusItem.swift", "MLevelMeter.swift",
                                           "Theme.swift", "DesignGallery.swift", "TokenPanel.swift"]

    @Test func clayOnlyWhereAllowed() throws {
        for (name, text) in try Self.viewFiles() where !Self.clayAllowed.contains(name) {
            #expect(!text.contains("accentClay"), "\(name) uses accent-clay")
        }
    }

    @Test func noRed() throws {
        let reds = ["Color.red", ".foregroundStyle(.red", ".fill(.red", "NSColor.red", "systemRed", ".tint(.red", "Color(.systemRed"]
        for (name, text) in try Self.viewFiles() {
            for red in reds { #expect(!text.contains(red), "\(name) uses red (\(red))") }
        }
    }
}

/// Reduce Motion (§6.3): springs become short fades, scale and offset changes disappear.
@Suite("Motion")
struct MotionTests {
    @Test func reduceMotionDropsScaleAndOffset() {
        let reduced = Motion(reduce: true)
        #expect(reduced.scale(MotionTokens.barNudgeScale) == 1)
        #expect(reduced.offset(MotionTokens.pageRise) == 0)
        let normal = Motion(reduce: false)
        #expect(normal.scale(MotionTokens.barNudgeScale) == MotionTokens.barNudgeScale)
        #expect(normal.offset(MotionTokens.pageRise) == MotionTokens.pageRise)
    }

    @Test func timeScaleSlowsEverything() {
        #expect(Motion(reduce: false, timeScale: 0.2).seconds(MotionTokens.pageSwitch) == MotionTokens.pageSwitch / 0.2)
    }

    /// The board's per-frame smoothing (0.30 and 0.09 at 60 fps) and the time constants agree.
    @Test func waveSmoothingMatchesTheReference() {
        let frame = 1.0 / 60
        #expect(abs((1 - exp(-frame / MotionTokens.waveAttack)) - 0.30) < 0.02)
        #expect(abs((1 - exp(-frame / MotionTokens.waveRelease)) - 0.09) < 0.01)
    }
}
