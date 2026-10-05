import AppKit
import CoreText
import os
import SwiftUI

// Type tokens (UI_REDESIGN.md v2 §3.3). Three open families (SIL OFL), bundled in Resources/Fonts:
// Newsreader speaks (titles, quotes, samples), Geist works (labels, buttons, body), Geist Mono reports
// data (keys, times, counts, captions). A browser picks Newsreader's optical size from the font size, so
// two static cuts are bundled: "Newsreader" (opsz 16) for text sizes and "Newsreader Display" (opsz 36)
// for titles of 26 pt and up. No app geometry here (§11).

public enum TypeFamily: Sendable {
    case sans, mono, serif
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

    /// The same style at another weight (for example `nav` selected, or `hint` at 500 in toast buttons).
    public func weight(_ w: Int) -> TextStyleToken {
        var t = self
        t.weight = w
        return t
    }

    /// The same style at another size, keeping the line height's leading (key caps, small controls).
    public func sized(_ s: Double) -> TextStyleToken {
        var t = self
        t.lineHeight += s - size
        t.size = s
        return t
    }
}

public enum TypeTokens {
    // Display (Newsreader)
    public static let pageTitle = TextStyleToken(.serif, 400, size: 40, lineHeight: 42, tracking: -0.015) // source: board
    public static let welcomeTitle = TextStyleToken(.serif, 400, size: 34, lineHeight: 37, tracking: -0.01) // source: board
    public static let featureTitle = TextStyleToken(.serif, 400, size: 30, lineHeight: 33, tracking: -0.01) // source: board
    public static let stepTitle = TextStyleToken(.serif, 400, size: 28, lineHeight: 32) // source: board
    public static let cardTitle = TextStyleToken(.serif, 400, size: 22, lineHeight: 22) // source: board
    public static let trigger = TextStyleToken(.serif, 400, size: 18, lineHeight: 24, italic: true) // source: board
    public static let quote = TextStyleToken(.serif, 400, size: 16, lineHeight: 22, italic: true) // source: board
    public static let sample = TextStyleToken(.serif, 400, size: 15, lineHeight: 21) // source: board

    // Interface (Geist)
    public static let body = TextStyleToken(.sans, 400, size: 14, lineHeight: 22) // source: board
    public static let nav = TextStyleToken(.sans, 400, size: 14, lineHeight: 20) // source: board (500 selected)
    public static let button = TextStyleToken(.sans, 500, size: 14, lineHeight: 20) // source: board
    public static let label = TextStyleToken(.sans, 500, size: 13, lineHeight: 18) // source: board
    public static let control = TextStyleToken(.sans, 500, size: 13, lineHeight: 18) // source: board
    public static let controlSmall = TextStyleToken(.sans, 500, size: 12, lineHeight: 16) // source: board
    public static let hint = TextStyleToken(.sans, 400, size: 12, lineHeight: 17) // source: board
    public static let flowSub = TextStyleToken(.sans, 400, size: 11, lineHeight: 14) // source: board

    // Mono (Geist Mono)
    public static let caption = TextStyleToken(.mono, 500, size: 11, lineHeight: 14, uppercase: true, tracking: 0.08) // source: board
    public static let meta = TextStyleToken(.mono, 400, size: 11, lineHeight: 22) // source: board
    public static let keycap = TextStyleToken(.mono, 500, size: 12, lineHeight: 16) // source: board (10-13 by size)
    public static let keycapInline = TextStyleToken(.mono, 500, size: 10, lineHeight: 14) // source: board
    public static let keycapLarge = TextStyleToken(.mono, 500, size: 13, lineHeight: 16) // source: board
    public static let stat = TextStyleToken(.mono, 500, size: 12, lineHeight: 16) // source: board
    public static let tag = TextStyleToken(.mono, 400, size: 10, lineHeight: 14) // source: board
    /// The countdown ring's digit: a numeral inside a 22 pt ring, the one size below the 10 pt floor (§3.5).
    public static let ringDigit = TextStyleToken(.mono, 500, size: 9, lineHeight: 10) // source: board

    /// Every style, for tests and the gallery.
    public static let all: [(String, TextStyleToken)] = [
        ("page-title", pageTitle), ("welcome-title", welcomeTitle), ("feature-title", featureTitle), ("step-title", stepTitle),
        ("card-title", cardTitle), ("trigger", trigger), ("quote", quote), ("sample", sample), ("body", body), ("nav", nav),
        ("button", button), ("label", label), ("control", control), ("control-sm", controlSmall), ("hint", hint), ("flow-sub", flowSub),
        ("caption", caption), ("meta", meta), ("keycap", keycap), ("keycap-inline", keycapInline), ("keycap-lg", keycapLarge),
        ("stat", stat), ("tag", tag), ("ring-digit", ringDigit),
    ]

    /// Nothing renders smaller than this (tags only; everything else is 11 or larger) except the
    /// countdown ring's digit.
    public static let minimumSize: Double = 10 // source: board
    /// Newsreader sizes from here up use the display cut (optical size 36).
    public static let displayCutFrom: Double = 26 // source: derived (between card-title 22 and step-title 28)
    /// Text size setting: Default and Large (Hub only).
    public static let scaleDefault: Double = 1.0 // source: board
    public static let scaleLarge: Double = 1.15 // source: board

    /// PostScript name of the bundled face for a family, weight, style and size.
    public static func postScriptName(_ family: TypeFamily, weight: Int, italic: Bool, size: Double = 14) -> String {
        switch family {
        case .sans:
            return "Geist-" + (weight < 450 ? "Regular" : weight < 550 ? "Medium" : "SemiBold")
        case .mono:
            return "GeistMono-" + (weight < 450 ? "Regular" : "Medium")
        case .serif:
            if size >= displayCutFrom && weight < 450 { return "NewsreaderDisplay-" + (italic ? "Italic" : "Regular") }
            if weight >= 450 { return "Newsreader-Medium" }
            return "Newsreader-" + (italic ? "Italic" : "Regular")
        }
    }

    public static let allPostScriptNames = [
        "Geist-Regular", "Geist-Medium", "Geist-SemiBold", "GeistMono-Regular", "GeistMono-Medium",
        "Newsreader-Regular", "Newsreader-Italic", "Newsreader-Medium", "NewsreaderDisplay-Regular", "NewsreaderDisplay-Italic",
    ]

    /// The font for a style at a text scale. Falls back to the system face when a bundled face is
    /// missing (rule 12).
    public static func nsFont(_ style: TextStyleToken, scale: Double = 1) -> NSFont {
        let floor = style.size < minimumSize ? style.size : minimumSize
        let size = max(floor, style.size * scale)
        if FontRegistry.isRegistered, let font = NSFont(name: postScriptName(style.family, weight: style.weight, italic: style.italic, size: size), size: size) {
            return font
        }
        let weight: NSFont.Weight = style.weight < 450 ? .regular : style.weight < 550 ? .medium : .semibold
        var font = style.family == .mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        if style.family == .serif, let serif = font.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: serif, size: size) { font = f }
        if style.italic, let f = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: size) { font = f }
        return font
    }

    public static func font(_ style: TextStyleToken, scale: Double = 1) -> Font {
        Font(nsFont(style, scale: scale))
    }
}

/// Registers the bundled fonts once per process. If registration fails the app keeps working with
/// system fonts and logs it once (rule 12).
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
        let missing = TypeTokens.allPostScriptNames.filter { NSFont(name: $0, size: 12) == nil }
        if !missing.isEmpty { log.error("bundled faces missing: \(missing.joined(separator: ", "), privacy: .public); using system fonts") }
        return missing.isEmpty
    }()

    /// Registers the fonts (idempotent) and says whether every bundled face is available.
    @discardableResult
    public static func registerBundledFonts() -> Bool { registration }

    public static var isRegistered: Bool { registration }
}
