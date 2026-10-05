import AppKit
import CoreText
import os
import SwiftUI

// Type tokens (UI_REDESIGN.md §3.3). Two open families (SIL OFL), bundled in Resources/Fonts:
// Source Sans 3 for everything operational (the open fallback the Anthropic theme names for its own
// licensed face) and Newsreader, cut at a 24 pt optical size, for titles. Source Sans runs one point
// larger than the reference's measured sans because its x-height is smaller. No app geometry here (§11).

public enum TypeFamily: Sendable {
    case sans, serif
}

/// One text style: family, weight, italic, size and line height in points, case and tracking.
public struct TextStyleToken: Sendable, Hashable {
    public var family: TypeFamily
    public var weight: Int
    public var italic: Bool
    public var size: Double
    public var lineHeight: Double
    public var uppercase: Bool
    /// Letter spacing in em.
    public var tracking: Double

    public init(_ family: TypeFamily, _ weight: Int, size: Double, lineHeight: Double, italic: Bool = false, uppercase: Bool = false, tracking: Double = 0) {
        self.family = family
        self.weight = weight
        self.italic = italic
        self.size = size
        self.lineHeight = lineHeight
        self.uppercase = uppercase
        self.tracking = tracking
    }

    /// The same style in italic (the serif's one emphasized word).
    public var italicized: TextStyleToken {
        var t = self
        t.italic = true
        return t
    }

    /// The same style at another weight (medium-weight emphasis inside body text).
    public func weight(_ w: Int) -> TextStyleToken {
        var t = self
        t.weight = w
        return t
    }
}

public enum TypeTokens {
    /// Points to the system font instead of Source Sans 3 when false (one switch, §3.3).
    nonisolated(unsafe) public static var useBundledSans = true

    public static let pageTitle = TextStyleToken(.serif, 500, size: 34, lineHeight: 40) // source: assumed // MEASURE
    public static let featureTitle = TextStyleToken(.serif, 500, size: 30, lineHeight: 36) // source: assumed // MEASURE
    public static let heading = TextStyleToken(.serif, 500, size: 22, lineHeight: 28) // source: assumed // MEASURE
    public static let body = TextStyleToken(.sans, 400, size: 16, lineHeight: 24) // source: wis (+1)
    public static let nav = TextStyleToken(.sans, 500, size: 16, lineHeight: 20) // source: wis (+1)
    public static let row = TextStyleToken(.sans, 400, size: 17, lineHeight: 24) // source: wis (+1)
    public static let meta = TextStyleToken(.sans, 400, size: 15, lineHeight: 20) // source: wis (+1)
    public static let section = TextStyleToken(.sans, 600, size: 12, lineHeight: 16, uppercase: true, tracking: 0.06) // source: assumed // MEASURE
    public static let button = TextStyleToken(.sans, 500, size: 16, lineHeight: 20) // source: wis (+1)
    public static let chip = TextStyleToken(.sans, 500, size: 16, lineHeight: 20) // source: wis (+1)
    public static let badge = TextStyleToken(.sans, 600, size: 14, lineHeight: 18) // source: assumed // MEASURE
    public static let keycap = TextStyleToken(.sans, 600, size: 13, lineHeight: 16) // source: assumed // MEASURE
    public static let flowText = TextStyleToken(.sans, 500, size: 13, lineHeight: 16) // source: assumed (scale) // MEASURE
    public static let flowAlert = TextStyleToken(.sans, 500, size: 14, lineHeight: 18) // source: assumed (scale) // MEASURE

    /// Nothing renders smaller than this, whatever the scale.
    public static let minimumSize: Double = 11 // source: assumed // MEASURE
    /// Text size setting: Default and Large.
    public static let scaleDefault: Double = 1.0
    public static let scaleLarge: Double = 1.15 // source: assumed // MEASURE

    /// PostScript names of the bundled faces.
    public static func postScriptName(_ family: TypeFamily, weight: Int, italic: Bool) -> String {
        switch family {
        case .sans:
            let w = switch weight {
            case ..<450: "Regular"
            case ..<550: "Medium"
            case ..<650: "Semibold"
            default: "Bold"
            }
            return "SourceSans3-" + w
        case .serif:
            let w = weight >= 450 ? "Medium" : ""
            let style = italic ? (w.isEmpty ? "Italic" : "Italic") : (w.isEmpty ? "Regular" : "")
            return "Newsreader-" + (w + style)
        }
    }

    public static let allPostScriptNames = [
        "SourceSans3-Regular", "SourceSans3-Medium", "SourceSans3-Semibold", "SourceSans3-Bold",
        "Newsreader-Regular", "Newsreader-Italic", "Newsreader-Medium", "Newsreader-MediumItalic",
    ]

    /// The font for a style at a text scale. Falls back to the system font when a bundled face is
    /// missing (rule 9).
    public static func nsFont(_ style: TextStyleToken, scale: Double = 1) -> NSFont {
        let size = max(minimumSize, style.size * scale)
        if style.family == .serif || useBundledSans, FontRegistry.isRegistered,
           let font = NSFont(name: postScriptName(style.family, weight: style.weight, italic: style.italic), size: size) {
            return font
        }
        let weight: NSFont.Weight = switch style.weight {
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        default: .bold
        }
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if style.family == .serif, let serif = font.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: serif, size: size) { font = f }
        if style.italic, let f = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: size) { font = f }
        return font
    }

    public static func font(_ style: TextStyleToken, scale: Double = 1) -> Font {
        Font(nsFont(style, scale: scale))
    }
}

/// Registers the bundled fonts once per process. If registration fails the app keeps working with
/// system fonts and logs it once (rule 9).
public enum FontRegistry {
    static let log = Logger(subsystem: "com.swaritsheel.Murmur", category: "fonts")

    private static let registration: Bool = {
        guard let folder = Bundle.module.url(forResource: "Fonts", withExtension: nil),
              let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
              .filter({ $0.pathExtension == "ttf" }), !urls.isEmpty else {
            log.error("bundled fonts not found; using system fonts")
            return false
        }
        var errors: Unmanaged<CFArray>?
        let ok = CTFontManagerRegisterFontsForURLs(urls as CFArray, .process, &errors)
        if !ok {
            // Already registered (a second call in the same process) counts as success.
            let failures = (errors?.takeRetainedValue() as? [CFError]) ?? []
            let real = failures.filter { CFErrorGetCode($0) != CTFontManagerError.alreadyRegistered.rawValue }
            if !real.isEmpty {
                log.error("font registration failed for \(real.count, privacy: .public) files; using system fonts")
                return false
            }
        }
        return TypeTokens.allPostScriptNames.allSatisfy { NSFont(name: $0, size: 12) != nil }
    }()

    /// Registers the fonts (idempotent) and says whether every bundled face is available.
    @discardableResult
    public static func registerBundledFonts() -> Bool { registration }

    public static var isRegistered: Bool { registration }
}
