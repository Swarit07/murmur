import AppKit
import Foundation
import Testing
@testable import UI

/// Contrast (UI_REDESIGN.md §3.2 and §8): every declared pair must reach the ratio the design states,
/// minus 0.05. Ratios are compared at the design's own precision (two decimals).
@Suite("Theme contrast")
struct ContrastTests {
    static func ratio(_ a: ColorToken, _ b: ColorToken) -> Double {
        (a.contrast(with: b) * 100).rounded() / 100
    }

    static let white = ColorToken("#FFFFFF")
    static let black = ColorToken("#000000")

    @Test func lightPairs() {
        let c = ThemeColors.light
        let pairs: [(String, ColorToken, ColorToken, Double)] = [
            ("text-title on bg-panel", c.textTitle, c.bgPanel, 14.1),
            ("text-primary on bg-panel", c.textPrimary, c.bgPanel, 10.8),
            ("text-primary on bg-window", c.textPrimary, c.bgWindow, 10.3),
            ("text-primary on bg-hover", c.textPrimary, c.bgHover, 9.2),
            ("text-body on bg-card", c.textBody, c.bgCard, 8.9),
            ("text-secondary on bg-panel", c.textSecondary, c.bgPanel, 5.4),
            ("text-secondary on bg-window", c.textSecondary, c.bgWindow, 5.1),
            ("text-secondary on bg-chip", c.textSecondary, c.bgChip, 4.8),
            ("text-secondary on bg-hover", c.textSecondary, c.bgHover, 4.6),
            ("text-secondary on bg-feature", c.textSecondary, c.bgFeature, 5.0),
            ("text-disabled on bg-panel", c.textDisabled, c.bgPanel, 2.4),
            ("white on accent-clay", c.buttonText, c.accentClay, 5.2),
            ("white on accent-clay-hover", c.buttonText, c.accentClayHover, 6.3),
            ("accent-clay on bg-panel", c.accentClay, c.bgPanel, 4.9),
            ("accent-clay on bg-window", c.accentClay, c.bgWindow, 4.7),
            ("accent-clay-text on bg-panel", c.accentClayText, c.bgPanel, 5.8),
            ("accent-clay-text on bg-feature", c.accentClayText, c.bgFeature, 5.3),
            ("accent-clay-text on accent-clay-tint", c.accentClayText, c.accentClayTint, 4.7),
            ("border-control on white", c.borderControl, Self.white, 3.8),
            ("border-control on bg-panel", c.borderControl, c.bgPanel, 3.6),
            ("border-control on bg-chip", c.borderControl, c.bgChip, 3.2),
            ("focus-ring on bg-panel", c.focusRing, c.bgPanel, 7.1),
            ("danger-text on bg-panel", c.dangerText, c.bgPanel, 6.6),
        ]
        for (name, fg, bg, target) in pairs {
            #expect(Self.ratio(fg, bg) >= target - 0.05, "\(name): \(Self.ratio(fg, bg)) < \(target)")
        }
    }

    @Test func darkPairs() {
        let c = ThemeColors.dark
        let pairs: [(String, ColorToken, ColorToken, Double)] = [
            ("text-title on bg-panel", c.textTitle, c.bgPanel, 15.9),
            ("text-primary on bg-panel", c.textPrimary, c.bgPanel, 14.0),
            ("text-primary on bg-hover", c.textPrimary, c.bgHover, 11.4),
            ("text-body on bg-card", c.textBody, c.bgCard, 10.6),
            ("text-secondary on bg-panel", c.textSecondary, c.bgPanel, 6.8),
            ("text-secondary on bg-card", c.textSecondary, c.bgCard, 6.3),
            ("text-secondary on bg-hover", c.textSecondary, c.bgHover, 5.5),
            ("accent-clay-text on bg-panel", c.accentClayText, c.bgPanel, 6.6),
            ("accent-clay-text on bg-card", c.accentClayText, c.bgCard, 6.1),
            ("border-control on bg-panel", c.borderControl, c.bgPanel, 3.4),
            ("border-control on bg-card", c.borderControl, c.bgCard, 3.2),
            ("white on accent-clay", c.buttonText, c.accentClay, 5.2),
        ]
        for (name, fg, bg, target) in pairs {
            #expect(Self.ratio(fg, bg) >= target - 0.05, "\(name): \(Self.ratio(fg, bg)) < \(target)")
        }
    }

    @Test func flowBarPairs() {
        let f = FlowBarColors.standard
        let pairs: [(String, ColorToken, ColorToken, Double)] = [
            ("white on black", f.text, f.fill, 21.0),
            ("flow-dot on black", f.dot, f.fill, 14.4),
            ("x glyph on x circle", f.xGlyph, f.xCircle, 3.9),
            ("x circle on black", f.xCircle, f.fill, 4.5),
            ("stop on black", f.stop, f.fill, 4.7),
            ("white glyph on stop", f.text, f.stop, 4.5),
            ("error icon on black", f.iconError, f.fill, 7.2),
            ("info icon on black", f.iconInfo, f.fill, 13.8),
            ("white on tooltip", f.text, f.tooltip, 14.0),
            ("white on alert button", f.text, f.button, 11.0),
        ]
        for (name, fg, bg, target) in pairs {
            #expect(Self.ratio(fg, bg) >= target - 0.05, "\(name): \(Self.ratio(fg, bg)) < \(target)")
        }
    }

    /// Increase Contrast swaps hairlines and secondary text for stronger tokens (§6.2).
    @Test func increaseContrastStrengthens() {
        let c = ThemeColors.light.increasedContrast
        #expect(c.borderPanel == ThemeColors.light.borderControl)
        #expect(c.textSecondary == ThemeColors.light.textBody)
        #expect(Self.ratio(c.textSecondary, c.bgPanel) > Self.ratio(ThemeColors.light.textSecondary, c.bgPanel))
    }

    /// One accent (rule 11): no token other than the clay family is saturated.
    @Test func clayIsTheOnlyAccent() {
        for colors in [ThemeColors.light, ThemeColors.dark] {
            let mirror = Mirror(reflecting: colors)
            for child in mirror.children {
                guard let token = child.value as? ColorToken, let name = child.label, !name.lowercased().contains("clay"),
                      !["focusRing", "dangerText"].contains(name) else { continue }
                let c = token.components
                // Chroma: neutrals (warm paper and ink) stay under 0.15; the clay is about 0.47.
                let chroma = max(c.r, c.g, c.b) - min(c.r, c.g, c.b)
                #expect(chroma < 0.15, "\(name) is too colorful for a neutral (\(token.hex))")
            }
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
        let tokens: [TextStyleToken] = [
            TypeTokens.pageTitle, TypeTokens.pageTitle.italicized, TypeTokens.featureTitle, TypeTokens.heading,
            TypeTokens.body, TypeTokens.body.weight(500), TypeTokens.nav, TypeTokens.row, TypeTokens.meta,
            TypeTokens.section, TypeTokens.button, TypeTokens.chip, TypeTokens.badge, TypeTokens.keycap,
            TypeTokens.flowText, TypeTokens.flowAlert,
        ]
        for token in tokens {
            let font = TypeTokens.nsFont(token)
            let expected = TypeTokens.postScriptName(token.family, weight: token.weight, italic: token.italic)
            #expect(font.fontName == expected, "\(token) resolved to \(font.fontName)")
        }
    }

    @Test func textScaleNeverGoesBelowTheMinimum() {
        FontRegistry.registerBundledFonts()
        let small = TypeTokens.nsFont(TypeTokens.keycap, scale: 0.5).pointSize
        let large = TypeTokens.nsFont(TypeTokens.body, scale: TypeTokens.scaleLarge).pointSize
        #expect(abs(small - TypeTokens.minimumSize) < 0.01, "keycap at 0.5: \(small)")
        #expect(abs(large - TypeTokens.body.size * TypeTokens.scaleLarge) < 0.01, "body at 1.15: \(large)")
    }
}

/// Source checks (§8): the token lint passes, and `text-disabled` appears only on disabled controls and
/// silent History rows.
@Suite("Source checks")
struct SourceCheckTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

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

    /// Files allowed to use `textDisabled`: token definitions, and the components whose disabled or
    /// silent state it is for.
    static let disabledAllowed: Set<String> = ["Tokens+Color.swift", "Theme.swift", "MButton.swift", "MToggle.swift", "MTextField.swift",
                                                "MTabs.swift", "MListRow.swift", "MSidebarItem.swift", "MCard.swift", "MCheckbox.swift",
                                                "MSelect.swift", "MKeycap.swift", "DesignGallery.swift"]

    @Test func textDisabledOnlyWhereAllowed() throws {
        let enumerator = FileManager.default.enumerator(at: Self.repo.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)
        var offenders: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift", !Self.disabledAllowed.contains(url.lastPathComponent) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("textDisabled") { offenders.append(url.lastPathComponent) }
        }
        #expect(offenders.isEmpty, "text-disabled used in \(offenders)")
    }
}

/// Reduce Motion (§6.2): springs become short fades, scale and offset changes disappear.
@Suite("Motion")
struct MotionTests {
    @Test func reduceMotionDropsScaleAndOffset() {
        let reduced = Motion(reduce: true)
        #expect(reduced.scale(HubGeometry.pressScale) == 1)
        #expect(reduced.offset(HubGeometry.pageRise) == 0)
        let normal = Motion(reduce: false)
        #expect(normal.scale(HubGeometry.pressScale) == HubGeometry.pressScale)
        #expect(normal.offset(HubGeometry.pageRise) == HubGeometry.pageRise)
    }

    @Test func timeScaleSlowsEverything() {
        #expect(Motion(reduce: false, timeScale: 0.2).seconds(MotionTokens.pageSwitch) == MotionTokens.pageSwitch / 0.2)
    }
}
