import AppKit
import HubUI
import MurmurKit
import SwiftUI
import UI

// murmur-snap [before|after] [--out <dir>] [--large] [--reduce-motion] [--compare]
// Renders every Hub page, onboarding step and Flow Bar state in light and dark at the screen's
// backing scale (2× on Retina) with demo data, into Artifacts/ui/<set>/<appearance>/. `--large`
// renders at text scale 1.15 into <set>-large, `--reduce-motion` with Reduce Motion on into
// <set>-reduced (UI_REDESIGN.md §8). Exits non-zero if any image comes out blank. Windows are drawn offscreen through AppKit's own cacheDisplay rather
// than ImageRenderer, because ImageRenderer cannot draw AppKit-backed controls such as text fields.

let arguments = Array(CommandLine.arguments.dropFirst())
let large = arguments.contains("--large")
let reduceMotion = arguments.contains("--reduce-motion")
let compare = arguments.contains("--compare")
let outValue = arguments.firstIndex(of: "--out").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
let setName = (arguments.first { !$0.hasPrefix("-") && $0 != outValue } ?? "after") + (large ? "-large" : "") + (reduceMotion ? "-reduced" : "")
let outRoot: URL = {
    if let i = arguments.firstIndex(of: "--out"), i + 1 < arguments.count { return URL(fileURLWithPath: arguments[i + 1]) }
    return URL(fileURLWithPath: "Artifacts/ui")
}().appendingPathComponent(setName)

@MainActor
enum Snap {
    static var written = 0
    static var blank: [String] = []

    static func pump(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Puts the window on screen but invisible, so SwiftUI lays out and renders normally.
    static func prepare(_ window: NSWindow) {
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSScreen.main?.visibleFrame.origin ?? .zero)
        window.orderFrontRegardless()
    }

    /// `fine` scans every other pixel: the idle Flow Bar is a 36 × 6 pill that a coarse grid misses.
    static func capture(_ view: NSView, to url: URL, mayBeBlank: Bool = false, fine: Bool = false) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { blank.append(url.lastPathComponent); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if !mayBeBlank, isBlank(rep, fine: fine) { blank.append(url.path) }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        written += 1
    }

    /// Blank means fewer than three distinct colors on a 16 × 16 sample grid (or every other pixel).
    static func isBlank(_ rep: NSBitmapImageRep, fine: Bool = false) -> Bool {
        var colors = Set<String>()
        for x in stride(from: 0, to: rep.pixelsWide, by: fine ? 2 : max(1, rep.pixelsWide / 16)) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: fine ? 2 : max(1, rep.pixelsHigh / 16)) {
                if let c = rep.colorAt(x: x, y: y) { colors.insert(String(format: "%.2f%.2f%.2f%.2f", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)) }
            }
        }
        return colors.count < 3
    }

    static let looks: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

    /// `--compare`: crops each board in Design/reference to the matching region and writes side-by-side
    /// sheets to Artifacts/ui/compare (Tools/compare.py does the image work).
    static func runCompare() {
        let process = Process()
        let venv = URL(fileURLWithPath: "Tools/.venv/bin/python")
        let useVenv = FileManager.default.isExecutableFile(atPath: venv.path)
        process.executableURL = useVenv ? venv : URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = (useVenv ? [] : ["python3"]) + ["Tools/compare.py", outRoot.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("murmur-snap: could not run Tools/compare.py: \(error)")
        }
    }

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        if !FontRegistry.registerBundledFonts() { print("murmur-snap: bundled fonts did not register; using system fonts") }
        if large { UIDebug.shared.textScale = TypeTokens.scaleLarge }
        if reduceMotion { UIDebug.shared.reduceMotion = true }

        guard let store = try? HistoryStore(url: nil) else { fatalError("in-memory store") }
        DemoData.seed(store)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "com.swaritsheel.Murmur.snapshots") ?? .standard)
        let controller = DictationController(settings: settings, store: store, sounds: nil)
        let hub = HubModel(controller: controller, store: store)
        // The boards show a ready app; the controller is never started here.
        hub.status?.phase = .idle

        for (lookName, look) in looks {
            let dir = outRoot.appendingPathComponent(lookName)

            // Hub: every page at the board's window size (1180 × 740).
            let window = WindowManager.makeWindow(id: "snap-hub", title: "Murmur", size: HubGeometry.defaultWindow, chrome: .unified) { HubView(model: hub) }
            window.appearance = NSAppearance(named: look)
            prepare(window)
            for page in HubPage.allCases {
                hub.go(page)
                pump(0.5)
                // At rest: no field holding focus (macOS gives the first text field focus on open).
                window.makeFirstResponder(nil)
                pump(0.2)
                capture(window.contentView?.superview ?? window.contentView!, to: dir.appendingPathComponent("hub-\(page.rawValue).png"))
            }
            window.close()

            // Onboarding: every step, in preview (nothing saved, no microphone).
            let onboarding = OnboardingModel(hub: hub, preview: true)
            let ob = WindowManager.makeWindow(id: "snap-onboarding", title: "Set up Murmur", size: OnboardingGeometry.step, chrome: .transparent) { OnboardingView(model: onboarding) }
            ob.appearance = NSAppearance(named: look)
            prepare(ob)
            for step in OnboardingStep.allCases {
                onboarding.step = step
                pump(0.4)
                capture(ob.contentView?.superview ?? ob.contentView!, to: dir.appendingPathComponent(String(format: "onboarding-%02d-%@.png", step.rawValue + 1, "\(step)")))
            }
            ob.close()

            // Flow Bar: every state on a neutral backdrop (it floats over other apps).
            let model = FlowBarModel()
            model.showAtAllTimes = true
            let canvas = FlowBarController.canvas
            // The boards' stage colors: the sunken paper desk in light, a dark desktop in dark.
            let backdrop = lookName == "light" ? ThemeColors.light.bgSunken.color : ThemeColors.dark.bgWindow.color
            let host = NSHostingView(rootView: ZStack { backdrop; FlowBarView(model: model) }.frame(width: canvas.width, height: canvas.height))
            let bar = NSWindow(contentRect: NSRect(origin: .zero, size: canvas), styleMask: [.borderless], backing: .buffered, defer: false)
            bar.contentView = host
            bar.appearance = NSAppearance(named: look)
            prepare(bar)
            for entry in FlowBarState.gallery {
                model.force(entry)
                pump(0.6)
                capture(host, to: dir.appendingPathComponent("flowbar-\(entry.name).png"), mayBeBlank: entry.state == .hidden, fine: true)
            }
            model.force(nil)
            bar.close()
        }
        // Design Gallery: every component in every state, light and dark side by side, at full height.
        let galleryHost = NSHostingView(rootView: DesignGallery(scrolls: false))
        let gallerySize = galleryHost.fittingSize
        let gallery = NSWindow(contentRect: NSRect(origin: .zero, size: gallerySize), styleMask: [.borderless], backing: .buffered, defer: false)
        gallery.contentView = galleryHost
        prepare(gallery)
        pump(1.0)
        capture(galleryHost, to: outRoot.appendingPathComponent("gallery.png"))
        gallery.close()

        print("murmur-snap: wrote \(written) images to \(outRoot.path)")
        if compare { runCompare() }
        if !blank.isEmpty {
            print("blank images:\n" + blank.joined(separator: "\n"))
            exit(1)
        }
        exit(0)
    }
}

MainActor.assumeIsolated { Snap.run() }
