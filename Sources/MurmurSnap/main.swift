import AppKit
import HubUI
import MurmurKit
import SwiftUI
import UI

// murmur-snap [before|after] [--out <dir>]
// Renders every Hub page, onboarding step and Flow Bar state in light and dark at the screen's
// backing scale (2× on Retina) with demo data, into Artifacts/ui/<set>/<appearance>/. Exits non-zero
// if any image comes out blank. Windows are drawn offscreen through AppKit's own cacheDisplay rather
// than ImageRenderer, because ImageRenderer cannot draw AppKit-backed controls such as text fields.

let arguments = Array(CommandLine.arguments.dropFirst())
let setName = arguments.first { !$0.hasPrefix("-") } ?? "after"
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

    static func capture(_ view: NSView, to url: URL, mayBeBlank: Bool = false) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { blank.append(url.lastPathComponent); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if !mayBeBlank, isBlank(rep) { blank.append(url.path) }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        written += 1
    }

    /// Blank means fewer than three distinct colors on a 16 × 16 sample grid.
    static func isBlank(_ rep: NSBitmapImageRep) -> Bool {
        var colors = Set<String>()
        for x in stride(from: 0, to: rep.pixelsWide, by: max(1, rep.pixelsWide / 16)) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: max(1, rep.pixelsHigh / 16)) {
                if let c = rep.colorAt(x: x, y: y) { colors.insert(String(format: "%.2f%.2f%.2f%.2f", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)) }
            }
        }
        return colors.count < 3
    }

    static let looks: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        if !FontRegistry.registerBundledFonts() { print("murmur-snap: bundled fonts did not register; using system fonts") }

        guard let store = try? HistoryStore(url: nil) else { fatalError("in-memory store") }
        DemoData.seed(store)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "com.swaritsheel.Murmur.snapshots") ?? .standard)
        let controller = DictationController(settings: settings, store: store, sounds: nil)
        let hub = HubModel(controller: controller, store: store)

        for (lookName, look) in looks {
            let dir = outRoot.appendingPathComponent(lookName)

            // Hub: every page at the reference window size.
            let window = WindowManager.makeWindow(id: "snap-hub", title: "Murmur", size: NSSize(width: 1280, height: 700), chrome: .unified) { HubView(model: hub) }
            window.appearance = NSAppearance(named: look)
            prepare(window)
            for page in HubPage.allCases {
                hub.go(page)
                pump(0.5)
                capture(window.contentView?.superview ?? window.contentView!, to: dir.appendingPathComponent("hub-\(page.rawValue).png"))
            }
            window.close()

            // Onboarding: every step, in preview (nothing saved, no microphone).
            let onboarding = OnboardingModel(hub: hub, preview: true)
            let ob = WindowManager.makeWindow(id: "snap-onboarding", title: "Set up Murmur", size: NSSize(width: 640, height: 540), chrome: .transparent) { OnboardingView(model: onboarding) }
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
            let backdrop = lookName == "light" ? Color(white: 0.86) : Color(white: 0.18)
            let host = NSHostingView(rootView: ZStack { backdrop; FlowBarView(model: model) }.frame(width: canvas.width, height: canvas.height))
            let bar = NSWindow(contentRect: NSRect(origin: .zero, size: canvas), styleMask: [.borderless], backing: .buffered, defer: false)
            bar.contentView = host
            bar.appearance = NSAppearance(named: look)
            prepare(bar)
            for (name, state) in FlowBarState.gallery {
                model.forced = state
                pump(0.6)
                capture(host, to: dir.appendingPathComponent("flowbar-\(name).png"), mayBeBlank: state == .hidden)
            }
            model.forced = nil
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
        if !blank.isEmpty {
            print("blank images:\n" + blank.joined(separator: "\n"))
            exit(1)
        }
        exit(0)
    }
}

MainActor.assumeIsolated { Snap.run() }
