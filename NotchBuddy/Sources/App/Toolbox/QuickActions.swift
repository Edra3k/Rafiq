#if !APPSTORE
import AppKit
import Combine
import IOKit.pwr_mgt
import Vision

// MARK: - Keep awake
//
// Manual (an hour, until turned off) or automatic: while an agent's turn runs, the Mac doesn't
// sleep. One IOPM assertion, released as soon as nothing needs it.

@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()
    static let whileAgentsKey = "keepAwake.whileAgents"

    @Published private(set) var manualUntil: Date?
    @Published private(set) var manualForever = false
    @Published private(set) var active = false
    @Published var whileAgents: Bool = UserDefaults.standard.object(forKey: KeepAwake.whileAgentsKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(whileAgents, forKey: Self.whileAgentsKey); update() }
    }

    private var assertion: IOPMAssertionID = 0
    private var held = false
    private var subscription: AnyCancellable?
    private var expiry: Timer?

    private init() {}

    /// Called once at launch and when the feature is turned on or off.
    func featureChanged() {
        if FeatureHub.shared.isOn(.keepAwake) {
            if subscription == nil {
                subscription = TurnHistory.shared.$turns.receive(on: DispatchQueue.main).sink { [weak self] _ in
                    Task { @MainActor in self?.update() }
                }
            }
        } else {
            subscription = nil
            manualUntil = nil
            manualForever = false
        }
        update()
    }

    var agentsWorking: Bool {
        TurnHistory.shared.turns.values.contains { $0.last?.endedAt == nil && $0.last != nil }
    }

    func keepFor(minutes: Double?) {
        expiry?.invalidate()
        if let minutes {
            manualForever = false
            manualUntil = Date().addingTimeInterval(minutes * 60)
            expiry = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.manualUntil = nil; self?.update() }
            }
        } else {
            manualForever = true
            manualUntil = nil
        }
        update()
    }

    func stopManual() {
        expiry?.invalidate()
        manualUntil = nil
        manualForever = false
        update()
    }

    var manualOn: Bool { manualForever || (manualUntil.map { $0 > Date() } ?? false) }

    private func update() {
        let want = FeatureHub.shared.isOn(.keepAwake) && (manualOn || (whileAgents && agentsWorking))
        active = want
        if want && !held {
            let reason = "Rafiq keeps the Mac awake" as CFString
            held = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion) == kIOReturnSuccess
        } else if !want && held {
            IOPMAssertionRelease(assertion)
            held = false
        }
    }
}

// MARK: - Quick actions

@MainActor
enum QuickActions {
    static func toggleDarkMode() {
        runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
    }

    static var desktopIconsHidden: Bool {
        UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool == false
    }

    static func toggleDesktopIcons() {
        let hide = !desktopIconsHidden
        _ = JarvisMac.run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hide ? "false" : "true"])
        _ = JarvisMac.run("/usr/bin/killall", ["Finder"])
    }

    /// Removable and network volumes; returns how many were ejected.
    @discardableResult
    static func ejectAll() -> Int {
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey, .volumeIsInternalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var count = 0
        for url in volumes where url.path != "/" {
            let v = try? url.resourceValues(forKeys: Set(keys))
            let external = (v?.volumeIsEjectable ?? false) || (v?.volumeIsRemovable ?? false) || !(v?.volumeIsLocal ?? true)
            guard external, v?.volumeIsInternal != true else { continue }
            if (try? NSWorkspace.shared.unmountAndEjectDevice(at: url)) != nil { count += 1 }
        }
        return count
    }

    static func emptyTrash() {
        runAppleScript("tell application \"Finder\" to empty trash")
    }

    static var trashCount: Int {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        return (try? FileManager.default.contentsOfDirectory(atPath: trash.path))?.filter { $0 != ".DS_Store" }.count ?? 0
    }

    static func lockScreen() {
        typealias Lock = @convention(c) () -> Int32
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(symbol, to: Lock.self)()
        } else {
            _ = JarvisMac.run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    // MARK: Color picker

    static func pickColor(_ done: @escaping (String?) -> Void) {
        NSColorSampler().show { color in
            guard let rgb = color?.usingColorSpace(.sRGB) else { done(nil); return }
            let hex = String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            done(hex)
        }
    }

    // MARK: Text from screen

    /// The user selects an area; its text goes to the clipboard. nil when cancelled.
    static func textFromScreen() async -> String? {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("rafiq-ocr-\(UUID().uuidString).png").path
        let text: String? = await Task.detached {
            _ = JarvisMac.run("/usr/sbin/screencapture", ["-i", "-x", path], timeout: 120)
            defer { try? FileManager.default.removeItem(atPath: path) }
            guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return JarvisMac.recognize(image)
        }.value
        guard let text, !text.isEmpty else { return nil }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }

    // MARK: Apps

    static var openApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && $0.bundleIdentifier != "com.apple.finder"
        }
    }

    static func quitAll(except front: Bool) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        for app in openApps where !(front && app == frontmost) { app.terminate() }
    }

    // MARK: Helpers

    @discardableResult
    static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}

// MARK: - Open ports

struct ListeningPort: Identifiable, Equatable {
    let port: Int
    let pid: pid_t
    let process: String
    var id: String { "\(port)-\(pid)" }
}

@MainActor
final class PortWatch: ObservableObject {
    static let shared = PortWatch()
    @Published private(set) var ports: [ListeningPort] = []

    func refresh() {
        Task {
            let out = await Task.detached { JarvisMac.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"], timeout: 8) ?? "" }.value
            ports = Self.parse(out)
        }
    }

    nonisolated static func parse(_ out: String) -> [ListeningPort] {
        var result: [ListeningPort] = []
        var pid: pid_t = 0
        var command = ""
        for line in out.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = pid_t(value) ?? 0
            case "c": command = value
            case "n":
                if let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]),
                   !result.contains(where: { $0.port == port && $0.pid == pid }) {
                    result.append(ListeningPort(port: port, pid: pid, process: command))
                }
            default: break
            }
        }
        return result.sorted { $0.port < $1.port }
    }

    func stop(_ port: ListeningPort) {
        kill(port.pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refresh() }
    }
}

// MARK: - Speed test (macOS's own networkQuality)

@MainActor
final class SpeedTest: ObservableObject {
    static let shared = SpeedTest()
    @Published private(set) var running = false
    @Published private(set) var down: Double?
    @Published private(set) var up: Double?
    @Published private(set) var failed = false

    func run() {
        guard !running else { return }
        running = true
        failed = false
        Task {
            let out = await Task.detached { JarvisMac.run("/usr/bin/networkQuality", ["-c", "-s"], timeout: 90) ?? "" }.value
            running = false
            guard let data = out.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dl = json["dl_throughput"] as? Double else { failed = true; return }
            down = dl
            up = json["ul_throughput"] as? Double
        }
    }

    static func mbps(_ bits: Double) -> String { String(format: "%.0f Mb/s", bits / 1_000_000) }
}
#endif
