import AppKit

/// The menu bar glyph (§3.6): the M with one short wave, from `Design/brand/menubar-template.svg`
/// rendered at 18 pt (1×, 2×, 3×) by `Tools/make_icons.py`. The four states are composed here from
/// the template and the `MenuBarGeometry` tokens:
/// - idle: the template, tinted by the system;
/// - recording: a clay copy (not a template) with a 5 pt clay dot 4 pt to its right;
/// - processing: the template at 45% with five 2.5 pt dots rippling (pass the animation phase);
/// - error: the template with a 9 pt badge at the bottom right, a "!" cut out of it and a 1.5 pt ring
///   cut out of the glyph around it, so the badge reads ink with a light "!" (never red).
@MainActor
public enum MenuBarGlyph {
    public enum State: String, CaseIterable, Sendable { case idle, recording, processing, error }

    /// The template, with its 1×, 2× and 3× representations.
    public static let template: NSImage = {
        let size = NSSize(width: MenuBarGeometry.glyph, height: MenuBarGeometry.glyph)
        let image = NSImage(size: size)
        for suffix in ["", "@2x", "@3x"] {
            if let url = Bundle.module.url(forResource: "menubar-template" + suffix, withExtension: "png", subdirectory: "MenuBar"),
               let rep = NSImageRep(contentsOf: url) {
                rep.size = size
                image.addRepresentation(rep)
            }
        }
        image.isTemplate = true
        return image
    }()

    /// The image for a state. `phase` (seconds) drives the processing ripple; `dark` picks the clay for a
    /// dark menu bar.
    public static func image(_ state: State, phase: Double = 0, dark: Bool = false) -> NSImage {
        let g = MenuBarGeometry.self
        let glyphRect = NSRect(x: 0, y: 0, width: g.glyph, height: g.glyph)
        switch state {
        case .idle:
            return template
        case .recording:
            let clay = (dark ? ThemeColors.dark : ThemeColors.light).accentClay.nsColor
            let size = NSSize(width: g.glyph + g.recordingGap + g.recordingDot, height: g.glyph)
            let image = NSImage(size: size, flipped: false) { _ in
                template.draw(in: glyphRect)
                clay.set()
                glyphRect.fill(using: .sourceAtop)
                NSBezierPath(ovalIn: NSRect(x: g.glyph + g.recordingGap, y: (g.glyph - g.recordingDot) / 2,
                                            width: g.recordingDot, height: g.recordingDot)).fill()
                return true
            }
            image.isTemplate = false
            image.accessibilityDescription = "Murmur is recording"
            return image
        case .processing:
            let count = g.processingDots
            let width = g.glyph + g.processingGap + CGFloat(count) * g.processingDot + CGFloat(count - 1) * g.processingDotGap
            let image = NSImage(size: NSSize(width: width, height: g.glyph), flipped: false) { _ in
                template.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: OpacityTokens.processingGlyph)
                for i in 0..<count {
                    // MurmurDots: a sine ripple, left to right, lifting each dot and raising its opacity.
                    let ripple = max(0, sin(phase / MotionTokens.dotsPeriod * 2 * .pi - Double(i) * MotionTokens.dotsPhaseStep))
                    let lift = CGFloat(ripple * MotionTokens.dotsLift) * g.processingDot
                    let x = g.glyph + g.processingGap + CGFloat(i) * (g.processingDot + g.processingDotGap)
                    NSColor.black.withAlphaComponent(MotionTokens.dotsOpacityLow + (1 - MotionTokens.dotsOpacityLow) * ripple).set()
                    NSBezierPath(ovalIn: NSRect(x: x, y: (g.glyph - g.processingDot) / 2 + lift, width: g.processingDot, height: g.processingDot)).fill()
                }
                return true
            }
            image.isTemplate = true
            image.accessibilityDescription = "Murmur is working"
            return image
        case .error:
            let image = NSImage(size: glyphRect.size, flipped: false) { _ in
                template.draw(in: glyphRect)
                guard let context = NSGraphicsContext.current?.cgContext else { return true }
                let badge = NSRect(x: g.glyph - g.badge, y: 0, width: g.badge, height: g.badge)
                context.setBlendMode(.destinationOut)
                context.fillEllipse(in: badge.insetBy(dx: -g.badgeCutout, dy: -g.badgeCutout))
                context.setBlendMode(.normal)
                NSColor.black.set()
                NSBezierPath(ovalIn: badge).fill()
                context.setBlendMode(.destinationOut)
                let mark = NSAttributedString(string: "!", attributes: [.font: NSFont.systemFont(ofSize: g.badgeMarkSize, weight: .bold),
                                                                        .foregroundColor: NSColor.black])
                let markSize = mark.size()
                mark.draw(at: NSPoint(x: badge.midX - markSize.width / 2, y: badge.midY - markSize.height / 2))
                context.setBlendMode(.normal)
                return true
            }
            image.isTemplate = true
            image.accessibilityDescription = "Murmur needs attention"
            return image
        }
    }
}

/// The app icon as an image (rendered from `Design/brand/app-icon.svg` by `Tools/make_icons.py`), for
/// onboarding's welcome step and the Accessibility illustration.
@MainActor
public enum BrandImages {
    public static let appIcon: NSImage = {
        let size = NSSize(width: OnboardingGeometry.appIcon, height: OnboardingGeometry.appIcon)
        let image = NSImage(size: size)
        for suffix in ["", "@2x"] {
            if let url = Bundle.module.url(forResource: "app-icon" + suffix, withExtension: "png", subdirectory: "Brand"),
               let rep = NSImageRep(contentsOf: url) {
                rep.size = size
                image.addRepresentation(rep)
            }
        }
        return image
    }()
}
