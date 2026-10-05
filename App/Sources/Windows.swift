import AppKit
import AVFoundation
import Combine
import MurmurKit
import SwiftUI

/// Plays Murmur's own generated sounds (Scripts/make-sounds.swift).
final class Sounds: SoundPlaying {
    @MainActor private static var cache: [UISound: NSSound] = [:]

    @MainActor func play(_ sound: UISound) {
        if Self.cache[sound] == nil, let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") {
            Self.cache[sound] = NSSound(contentsOf: url, byReference: true)
        }
        Self.cache[sound]?.stop()
        Self.cache[sound]?.play()
    }
}

/// Opens one window per kind and brings it forward when asked again.
@MainActor
final class WindowManager {
    private var windows: [String: NSWindow] = [:]

    func show<V: View>(_ id: String, title: String, size: NSSize, @ViewBuilder content: () -> V) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content())
        window.setContentSize(size)
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func showHistory(store: HistoryStore) {
        show("history", title: "Murmur History", size: NSSize(width: 760, height: 480)) { HistoryView(store: store) }
    }

    func showSettings(settings: AppSettings) {
        show("settings", title: "Murmur Settings", size: NSSize(width: 520, height: 520)) { SettingsView(settings: settings) }
    }

    func showPermissions(onChange: @escaping () -> Void) {
        show("permissions", title: "Murmur Permissions", size: NSSize(width: 560, height: 430)) { PermissionsView(onChange: onChange) }
    }
}

// MARK: - History (a plain list until the Hub in Milestone 4)

struct HistoryView: View {
    let store: HistoryStore
    @State private var records: [DictationRecord] = []
    @State private var search = ""
    @State private var selection: DictationRecord.ID?

    var body: some View {
        VStack(spacing: 0) {
            Table(records, selection: $selection) {
                TableColumn("Time") { r in Text(r.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(.secondary) }
                    .width(min: 110, ideal: 120, max: 140)
                TableColumn("App") { r in Text(r.appName ?? r.appBundleId ?? "—") }
                    .width(min: 80, ideal: 110, max: 160)
                TableColumn("Text") { r in
                    Text(r.bestText ?? "(no text)").lineLimit(2).foregroundStyle(r.bestText == nil ? .secondary : .primary)
                }
                TableColumn("Status") { r in Text(label(r.status)).foregroundStyle(r.status == .inserted ? Color.secondary : Color.orange) }
                    .width(min: 80, ideal: 100, max: 130)
            }
            .contextMenu(forSelectionType: DictationRecord.ID.self) { ids in
                Button("Copy") { copy(ids.first) }
            } primaryAction: { ids in
                copy(ids.first)
            }
            HStack {
                Text("\(records.count) dictations · double-click or press Return to copy").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(8)
        }
        .searchable(text: $search)
        .onChange(of: search) { reload() }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.didChange).receive(on: RunLoop.main)) { _ in reload() }
    }

    func reload() { records = (try? store.recent(limit: 500, search: search)) ?? [] }

    func copy(_ id: DictationRecord.ID?) {
        guard let text = records.first(where: { $0.id == id })?.bestText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func label(_ status: DictationRecord.Status) -> String {
        switch status {
        case .recorded: "Interrupted"
        case .transcribed: "Not cleaned"
        case .inserted: "Inserted"
        case .cancelled: "Cancelled"
        case .transcriptionFailed: "Failed"
        case .pasteFailed: "Not pasted"
        case .noTextBox: "No text box"
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    let settings: AppSettings
    @State private var engine = AppSettings.shared.engine
    @State private var cleanup = AppSettings.shared.cleanupProvider
    @State private var level = AppSettings.shared.cleanupLevel
    @State private var sounds = AppSettings.shared.soundsEnabled
    @State private var showInDock = AppSettings.shared.showInDock
    @State private var keepAudio = AppSettings.shared.keepAudio
    @State private var groqKey = ""
    @State private var groqSaved = Keychain.get("groq") != nil

    static let engineNames: [String: String] = [
        "parakeet-ultra": "Parakeet ultra (recommended)", "parakeet-v3": "Parakeet v3", "parakeet-v2": "Parakeet v2 (English)",
        "parakeet-phonon2": "Parakeet phonon2", "whisper-turbo": "Whisper Large v3 Turbo", "apple-speech": "Apple on-device",
        "groq-whisper": "Groq Whisper (cloud, needs key)",
    ]

    static let cleanupNames: [String: String] = [
        "mlx:qwen3.5-4b": "Qwen3.5 4B (recommended)", "mlx:smollm3-3b": "SmolLM3 3B (less memory)", "mlx:qwen3-4b-2507": "Qwen3 4B 2507",
        "mlx:qwen3.5-2b": "Qwen3.5 2B", "apple-foundation": "Apple on-device", "groq": "Groq (cloud, needs key)", "rules": "Rules only (no AI)",
    ]

    var body: some View {
        Form {
            Section("Speech") {
                Picker("Engine", selection: $engine) {
                    ForEach(EngineCatalog.ids.filter { Self.engineNames[$0] != nil }, id: \.self) { Text(Self.engineNames[$0] ?? $0).tag($0) }
                }
                .onChange(of: engine) { settings.engine = engine }
            }
            Section("Cleanup") {
                Picker("Model", selection: $cleanup) {
                    ForEach(Self.cleanupNames.keys.sorted(), id: \.self) { Text(Self.cleanupNames[$0] ?? $0).tag($0) }
                }
                .onChange(of: cleanup) { settings.cleanupProvider = cleanup }
                Picker("Auto Cleanup", selection: $level) {
                    Text("None").tag("none")
                    Text("Light").tag("light")
                    Text("Medium").tag("medium")
                }
                .pickerStyle(.segmented)
                .onChange(of: level) { settings.cleanupLevel = level }
            }
            Section("App") {
                Toggle("Sounds", isOn: $sounds).onChange(of: sounds) { settings.soundsEnabled = sounds }
                Toggle("Show in Dock", isOn: $showInDock).onChange(of: showInDock) { settings.showInDock = showInDock }
                Toggle("Keep audio for 14 days (for Retry)", isOn: $keepAudio).onChange(of: keepAudio) { settings.keepAudio = keepAudio }
            }
            Section("Cloud (optional)") {
                HStack {
                    SecureField(groqSaved ? "Groq API key saved in Keychain" : "Groq API key", text: $groqKey)
                    Button("Save") {
                        Keychain.set(groqKey, for: "groq")
                        groqSaved = !groqKey.isEmpty
                        groqKey = ""
                    }
                    if groqSaved {
                        Button("Remove") { Keychain.set(nil, for: "groq"); groqSaved = false }
                    }
                }
                Text("Audio and text leave this Mac only when you pick a Groq option above.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

struct PermissionsView: View {
    let onChange: () -> Void
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var accessibility = Permissions.accessibility
    @State private var inputMonitoring = Permissions.inputMonitoring
    @State private var secureInput = Permissions.secureEventInput
    @State private var fnUsage = Permissions.fnUsageType
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Murmur needs three permissions. macOS remembers them across updates because every build is signed the same way.")
                .fixedSize(horizontal: false, vertical: true)
            row("Microphone", ok: mic, why: "to hear you while the shortcut is held", pane: "Privacy_Microphone") {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            }
            row("Accessibility", ok: accessibility, why: "to check the text field and paste into it", pane: "Privacy_Accessibility") {
                Permissions.promptAccessibility()
            }
            row("Input Monitoring", ok: inputMonitoring, why: "to notice when the shortcut key is held", pane: "Privacy_ListenEvent") {
                Permissions.requestInputMonitoring()
            }
            if fnUsage != 0 {
                hint("The Globe (🌐) key may open emoji or dictation. In System Settings › Keyboard, set “Press 🌐 key to” to Do Nothing.",
                     button: "Open Keyboard Settings", url: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
            }
            if secureInput {
                hint("Another app has Secure Keyboard Entry on (often a password field or a terminal setting). Shortcuts are blocked until it is off.", button: nil, url: nil)
            }
            Spacer()
            HStack {
                Text("After granting Input Monitoring, macOS may need Murmur to restart.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restart Murmur") { relaunch() }
            }
        }
        .padding(20)
        .onReceive(timer) { _ in refresh() }
    }

    func refresh() {
        let before = inputMonitoring
        mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibility = Permissions.accessibility
        inputMonitoring = Permissions.inputMonitoring
        secureInput = Permissions.secureEventInput
        fnUsage = Permissions.fnUsageType
        if inputMonitoring && !before { onChange() }
    }

    func row(_ name: String, ok: Bool, why: String, pane: String, request: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading) {
                Text(name).bold()
                Text("Needed \(why).").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok {
                Button("Grant") {
                    request()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
        }
    }

    func hint(_ text: String, button: String?, url: String?) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "info.circle").foregroundStyle(.blue)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let button, let url {
                Button(button) { NSWorkspace.shared.open(URL(string: url)!) }
            }
        }
    }

    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
