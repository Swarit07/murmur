import AppKit
import HubUI
import MurmurKit
import SwiftUI
import UI

// murmur-snap [before|after] [--out <dir>] [--large] [--reduce-motion] [--contrast] [--compare]
// Renders every Hub page, onboarding step and Flow Bar state in light and dark at the screen's
// backing scale (2× on Retina) with demo data, into Artifacts/ui/<set>/<appearance>/. `--large`
// renders at text scale 1.15 into <set>-large, `--reduce-motion` with Reduce Motion on into
// <set>-reduced, `--contrast` with Increase Contrast on into <set>-contrast (UI_REDESIGN.md §8). Exits non-zero if any image comes out blank. Windows are drawn offscreen through AppKit's own cacheDisplay rather
// than ImageRenderer, because ImageRenderer cannot draw AppKit-backed controls such as text fields.

let arguments = Array(CommandLine.arguments.dropFirst())
let large = arguments.contains("--large")
let reduceMotion = arguments.contains("--reduce-motion")
let increaseContrast = arguments.contains("--contrast")
/// `--empty` renders with no History, words or snippets; `--stress` with long and odd content (QA).
let emptyData = arguments.contains("--empty")
let stressData = arguments.contains("--stress")
let compare = arguments.contains("--compare")
let outValue = arguments.firstIndex(of: "--out").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
/// `--size 880x560` renders the Hub at that window size (default: the board's 1180 × 740).
let sizeValue = arguments.firstIndex(of: "--size").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
let hubSize: CGSize = {
    let parts = sizeValue?.split(separator: "x").compactMap { Double($0) } ?? []
    return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : HubGeometry.defaultWindow
}()
let setName = (arguments.first { !$0.hasPrefix("-") && $0 != outValue && $0 != sizeValue } ?? "after") + (large ? "-large" : "") + (reduceMotion ? "-reduced" : "") + (increaseContrast ? "-contrast" : "") + (sizeValue.map { "-" + $0 } ?? "") + (emptyData ? "-empty" : "") + (stressData ? "-stress" : "")
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
    /// `--timing`: how long each Hub page takes from `go(page)` until its panel has content (QA).
    static func measurePageTiming(_ window: NSWindow, hub: HubModel) {
        guard let view = window.contentView else { return }
        func panelHasContent() -> Bool {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
            view.cacheDisplay(in: view.bounds, to: rep)
            var values: [CGFloat] = []
            let w = rep.pixelsWide, h = rep.pixelsHigh
            for y in stride(from: h / 5, to: h * 4 / 5, by: 6) {
                for x in stride(from: w * 35 / 100, to: w * 90 / 100, by: 6) {
                    values.append(rep.colorAt(x: x, y: y)?.brightnessComponent ?? 0)
                }
            }
            let mean = values.reduce(0, +) / CGFloat(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / CGFloat(values.count)
            return variance > 0.0005
        }
        for page in HubPage.allCases + [HubPage.home] {
            hub.go(page == .home ? .dictionary : .home)
            pump(0.6)
            let start = Date()
            hub.go(page)
            var ms = -1.0
            while Date().timeIntervalSince(start) < 3 {
                pump(0.01)
                if panelHasContent() { ms = Date().timeIntervalSince(start) * 1000; break }
            }
            print(String(format: "page timing: %@ %@", "\(page)", ms < 0 ? "never (3 s)" : String(format: "%.0f ms", ms)))
        }
    }

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
        if increaseContrast { UIDebug.shared.increaseContrast = true }

        guard let store = try? HistoryStore(url: nil) else { fatalError("in-memory store") }
        if stressData { DemoData.seedStress(store) } else if !emptyData { DemoData.seed(store) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: "com.swaritsheel.Murmur.snapshots") ?? .standard)
        let controller = DictationController(settings: settings, store: store, sounds: nil)
        let hub = HubModel(controller: controller, store: store)
        // The boards show a ready app; the controller is never started here.
        hub.status?.phase = .idle

        for (lookName, look) in looks {
            let dir = outRoot.appendingPathComponent(lookName)

            // Hub: every page at the board's window size (1180 × 740).
            let window = WindowManager.makeWindow(id: "snap-hub", title: "Murmur", size: hubSize, chrome: .unified) { HubView(model: hub) }
            window.appearance = NSAppearance(named: look)
            prepare(window)
            if let i = arguments.firstIndex(of: "--toggle"), i + 1 < arguments.count, let page = HubPage(rawValue: arguments[i + 1]) {
                // Profiling aid: switch to `page` and back ten times, no captures.
                if arguments.contains("--frames") {
                    hub.go(.home); pump(0.8)
                    hub.go(page)
                    for i in 0..<12 {
                        pump(0.15)
                        capture(window.contentView!, to: outRoot.appendingPathComponent(String(format: "frame-%02d.png", i)), mayBeBlank: true)
                    }
                    exit(0)
                }
                for _ in 0..<10 { hub.go(page); pump(1.0); hub.go(.home); pump(0.5) }
                exit(0)
            }
            if arguments.contains("--timing") {
                measurePageTiming(window, hub: hub)
                exit(0)
            }
            for page in HubPage.allCases {
                hub.go(page)
                pump(0.5)
                // At rest: no field holding focus (macOS gives the first text field focus on open).
                window.makeFirstResponder(nil)
                pump(0.2)
                capture(window.contentView?.superview ?? window.contentView!, to: dir.appendingPathComponent("hub-\(page.rawValue).png"))
            }
            // Help & setup, then the Privacy and Acknowledgements dialogs (LEGAL_DOCS.md L5), the latter
            // closed and with Murmur's own license open.
            hub.go(.home)
            hub.helpOpen = true
            pump(0.5)
            capture(window.contentView?.superview ?? window.contentView!, to: dir.appendingPathComponent("hub-help.png"))
            for (name, document, open) in [("privacy", HubDocument.privacy, Set<String>()), ("acknowledgements", .acknowledgements, []),
                                           ("acknowledgements-open", .acknowledgements, ["Murmur/Murmur"])] {
                hub.expandedNotices = open
                hub.open(document, fromHelp: true)
                pump(0.6)
                capture(window.contentView?.superview ?? window.contentView!, to: dir.appendingPathComponent("hub-document-\(name).png"))
            }
            hub.document = nil
            hub.expandedNotices = []
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
            // The data step's "Read the privacy notes".
            onboarding.step = .data
            onboarding.showingPrivacy = true
            pump(0.5)
            capture(ob.contentView?.superview ?? ob.contentView!, to: dir.appendingPathComponent("onboarding-privacy.png"))
            onboarding.showingPrivacy = false
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
            if stressData {
                // Long messages and a long microphone name must truncate or wrap inside the card.
                model.microphoneName = "Scarlett 18i20 USB Audio Interface (3rd Gen), Input 1+2 Stereo"
                let long = "The microphone is unavailable (Scarlett 18i20 USB Audio Interface 3rd Gen). Check it is connected, then Retry."
                let extras: [(String, FlowBarState)] = [
                    ("stress-no-audio", .notice(FlowBarNotice(kind: .noAudio, message: ""))),
                    ("stress-mic-error", .notice(FlowBarNotice(kind: .micError, message: long))),
                    ("stress-info", .notice(FlowBarNotice(kind: .info, message: long + " " + long))),
                    ("stress-paste-error", .notice(FlowBarNotice(kind: .pasteError, message: long))),
                ]
                for (name, state) in extras {
                    model.force(FlowBarGalleryEntry(name, state))
                    pump(0.6)
                    capture(host, to: dir.appendingPathComponent("flowbar-\(name).png"), fine: true)
                }
            }
            model.force(nil)
            bar.close()

            // Menu bar (§5.2, §3.6): the four glyph states on the menu bar's color, then the dropdown's
            // header in each state and its footer, on the menu's color. The native menu itself is captured
            // by the app (Debug › menu hook), since it can't be drawn offscreen.
            let header = MenuHeaderModel()
            header.hotkey = "fn"
            header.microphone = "MacBook Pro Microphone"
            func headerView(_ phase: DictationStatus.Phase, _ message: String? = nil) -> some View {
                let m = MenuHeaderModel()
                m.phase = phase
                m.message = message
                m.hotkey = header.hotkey
                m.microphone = header.microphone
                m.recordingSince = Date().addingTimeInterval(-4)
                return MenuHeaderView(model: m)
            }
            let menuBar = NSHostingView(rootView: ThemeProvider {
                VStack(alignment: .leading, spacing: Spacing.s16) {
                    HStack(spacing: Spacing.s24) {
                        ForEach(MenuBarGlyph.State.allCases, id: \.self) { state in
                            Image(nsImage: MenuBarGlyph.image(state, phase: MotionTokens.dotsPeriod / 4, dark: lookName == "dark"))
                        }
                    }
                    .padding(Spacing.s8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    VStack(alignment: .leading, spacing: 0) {
                        headerView(.idle)
                        headerView(.recording(handsFree: true))
                        headerView(.processing)
                        headerView(.error, "Transcription failed. The audio is saved in History.")
                        headerView(.loading)
                        MenuFooterView("v0.1.0 · on-device engine")
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                }
                .padding(Spacing.s16)
                .background(Color(nsColor: .underPageBackgroundColor))
            })
            menuBar.frame = NSRect(origin: .zero, size: menuBar.fittingSize)
            let mb = NSWindow(contentRect: menuBar.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            mb.contentView = menuBar
            mb.appearance = NSAppearance(named: look)
            prepare(mb)
            pump(0.5)
            capture(menuBar, to: dir.appendingPathComponent("menubar.png"))
            mb.close()
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
