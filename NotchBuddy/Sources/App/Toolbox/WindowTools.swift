#if !APPSTORE
import AppKit
import ApplicationServices
import Carbon

// MARK: - Window layout, quit protection, quit on close, Spaces order, window switcher
//
// All of it moves other apps' windows through Accessibility, which Rafiq already asks for (Flow
// pastes with it). Shortcuts are Carbon hot keys, consumed so the front app never sees them;
// the edge snap only listens to mouse down and up while the feature is on.

private nonisolated(unsafe) var gWindowHotKeys: [UInt32: WindowAction] = [:]
private nonisolated(unsafe) var gWindowHandler: EventHandlerRef?
private nonisolated(unsafe) var gWindowRefs: [EventHotKeyRef] = []

private func rafiqWindowHotKeyHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard err == noErr, id.signature == WindowManager.signature, let action = gWindowHotKeys[id.id] else {
        return OSStatus(eventNotHandledErr)
    }
    MainActor.assumeIsolated { WindowManager.shared.perform(action) }
    return noErr
}

enum WindowAction: UInt32, CaseIterable {
    case left = 1000, right, top, bottom, maximize, center, leftThird, middleThird, rightThird, nextDisplay, restore, switcher
    case commandBar, radial, quickPanel

    /// (key code, Carbon modifiers): ⌃⌥ arrows and ↩, ⌃⌥C, ⌃⌥⇧ ← ↓ → for thirds, ⌃⌥⌘→, ⌃⌥⌫, ⌥⇥.
    var key: (UInt32, UInt32) {
        let co = UInt32(controlKey | optionKey)
        switch self {
        case .left: return (UInt32(kVK_LeftArrow), co)
        case .right: return (UInt32(kVK_RightArrow), co)
        case .top: return (UInt32(kVK_UpArrow), co)
        case .bottom: return (UInt32(kVK_DownArrow), co)
        case .maximize: return (UInt32(kVK_Return), co)
        case .center: return (UInt32(kVK_ANSI_C), co)
        case .leftThird: return (UInt32(kVK_LeftArrow), co | UInt32(shiftKey))
        case .middleThird: return (UInt32(kVK_DownArrow), co | UInt32(shiftKey))
        case .rightThird: return (UInt32(kVK_RightArrow), co | UInt32(shiftKey))
        case .nextDisplay: return (UInt32(kVK_RightArrow), co | UInt32(cmdKey))
        case .restore: return (UInt32(kVK_Delete), co)
        case .switcher: return (UInt32(kVK_Tab), UInt32(optionKey))
        case .commandBar: return (UInt32(kVK_ANSI_K), co)
        case .radial: return (UInt32(kVK_ANSI_R), co)
        case .quickPanel: return (UInt32(kVK_ANSI_T), co | UInt32(cmdKey))
        }
    }

    var symbol: String {
        switch self {
        case .left: return "rectangle.lefthalf.filled"
        case .right: return "rectangle.righthalf.filled"
        case .top: return "rectangle.tophalf.filled"
        case .bottom: return "rectangle.bottomhalf.filled"
        case .maximize: return "rectangle.fill"
        case .center: return "rectangle.center.inset.filled"
        case .leftThird: return "rectangle.leftthird.inset.filled"
        case .middleThird: return "rectangle.center.inset.filled"
        case .rightThird: return "rectangle.rightthird.inset.filled"
        case .nextDisplay: return "rectangle.on.rectangle"
        case .restore: return "arrow.uturn.backward"
        case .switcher: return "square.on.square"
        case .commandBar: return "sparkle.magnifyingglass"
        case .radial: return "circle.dashed"
        case .quickPanel: return "square.grid.2x2"
        }
    }

    var keyLabel: String {
        switch self {
        case .left: return "⌃⌥←"
        case .right: return "⌃⌥→"
        case .top: return "⌃⌥↑"
        case .bottom: return "⌃⌥↓"
        case .maximize: return "⌃⌥↩"
        case .center: return "⌃⌥C"
        case .leftThird: return "⌃⌥⇧←"
        case .middleThird: return "⌃⌥⇧↓"
        case .rightThird: return "⌃⌥⇧→"
        case .nextDisplay: return "⌃⌥⌘→"
        case .restore: return "⌃⌥⌫"
        case .switcher: return "⌥⇥"
        case .commandBar: return "⌃⌥K"
        case .radial: return "⌃⌥R"
        case .quickPanel: return "⌃⌥⌘T"
        }
    }
}

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    nonisolated static let signature: OSType = 0x5246_574D   // "RFWM"

    private var previous: [pid_t: CGRect] = [:]
    private var mouseMonitors: [Any] = []
    private var dragStart: (window: AXUIElement, frame: CGRect)?

    /// Called at launch and when a window feature changes.
    func featureChanged() {
        unregister()
        let hub = FeatureHub.shared
        var actions: [WindowAction] = []
        if hub.isOn(.windowLayout) { actions += WindowAction.allCases.filter { $0.rawValue <= WindowAction.restore.rawValue } }
        if hub.isOn(.windowSwitcher) { actions.append(.switcher) }
        if hub.isOn(.commandBar) { actions.append(.commandBar) }
        if hub.isOn(.radialMenu) { actions.append(.radial) }
        if hub.isOn(.quickPanel) { actions.append(.quickPanel) }
        if !actions.isEmpty { register(actions) }
        if hub.isOn(.windowLayout) { startEdgeSnap() } else { stopEdgeSnap() }
    }

    private func register(_ actions: [WindowAction]) {
        if gWindowHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), rafiqWindowHotKeyHandler, 1, &spec, nil, &gWindowHandler)
        }
        for action in actions {
            var ref: EventHotKeyRef?
            let (code, mods) = action.key
            if RegisterEventHotKey(code, mods, EventHotKeyID(signature: Self.signature, id: action.rawValue),
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                gWindowRefs.append(ref)
                gWindowHotKeys[action.rawValue] = action
            }
        }
    }

    private func unregister() {
        gWindowRefs.forEach { UnregisterEventHotKey($0) }
        gWindowRefs = []
        gWindowHotKeys = [:]
    }

    func perform(_ action: WindowAction) {
        if action == .switcher { WindowSwitcher.shared.show(); return }
        if action == .commandBar { CommandBar.shared.toggle(); return }
        if action == .radial { RadialMenu.shared.show(); return }
        if action == .quickPanel {
            UserDefaults.standard.set("tools", forKey: "tools.page")
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.tools)
            return
        }
        guard AXIsProcessTrusted() else { Self.askAccessibility(); return }
        guard let app = NSWorkspace.shared.frontmostApplication, let window = Self.focusedWindow(of: app.processIdentifier),
              let frame = Self.frame(of: window), let screen = Self.screen(containing: frame) else { return }
        if action == .restore {
            if let old = previous[app.processIdentifier] { Self.set(window, old) }
            return
        }
        previous[app.processIdentifier] = frame
        let target: CGRect
        let area = Self.axRect(screen.visibleFrame)
        switch action {
        case .left: target = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        case .right: target = CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height)
        case .top: target = CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height / 2)
        case .bottom: target = CGRect(x: area.minX, y: area.midY, width: area.width, height: area.height / 2)
        case .maximize: target = area
        case .center:
            target = CGRect(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2, width: frame.width, height: frame.height)
        case .leftThird: target = CGRect(x: area.minX, y: area.minY, width: area.width / 3, height: area.height)
        case .middleThird: target = CGRect(x: area.minX + area.width / 3, y: area.minY, width: area.width / 3, height: area.height)
        case .rightThird: target = CGRect(x: area.minX + area.width * 2 / 3, y: area.minY, width: area.width / 3, height: area.height)
        case .nextDisplay:
            let screens = NSScreen.screens
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return }
            let next = Self.axRect(screens[(index + 1) % screens.count].visibleFrame)
            let w = min(frame.width, next.width), h = min(frame.height, next.height)
            target = CGRect(x: next.midX - w / 2, y: next.midY - h / 2, width: w, height: h)
        case .restore, .switcher, .commandBar, .radial, .quickPanel: return
        }
        Self.set(window, target)
    }

    // MARK: Edge snap: drag a window to an edge, it fills that half (the top: the whole screen)

    private func startEdgeSnap() {
        guard mouseMonitors.isEmpty else { return }
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { _ in
            MainActor.assumeIsolated { WindowManager.shared.mouseDown() }
        }) { mouseMonitors.append(down) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in
            MainActor.assumeIsolated { WindowManager.shared.mouseUp() }
        }) { mouseMonitors.append(up) }
    }

    private func stopEdgeSnap() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
    }

    private func mouseDown() {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              let window = Self.focusedWindow(of: app.processIdentifier), let frame = Self.frame(of: window) else { dragStart = nil; return }
        dragStart = (window, frame)
    }

    private func mouseUp() {
        guard let start = dragStart else { return }
        dragStart = nil
        guard let now = Self.frame(of: start.window), now.size == start.frame.size, now.origin != start.frame.origin else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }
        let f = screen.frame, area = Self.axRect(screen.visibleFrame), edge: CGFloat = 4
        var target: CGRect?
        if mouse.x <= f.minX + edge { target = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height) }
        else if mouse.x >= f.maxX - edge { target = CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height) }
        else if mouse.y >= f.maxY - edge - 24 { target = area }
        guard let target else { return }
        if let app = NSWorkspace.shared.frontmostApplication { previous[app.processIdentifier] = start.frame }
        Self.set(start.window, target)
    }

    // MARK: Accessibility helpers

    static func askAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue, let sizeValue else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    static func set(_ window: AXUIElement, _ rect: CGRect) {
        var point = rect.origin, size = rect.size
        if let p = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p) }
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s) }
        // Some apps clamp the first move to the old screen: once more lands it.
        if let p = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p) }
    }

    /// AppKit's bottom-left rectangles to Accessibility's top-left ones.
    static func axRect(_ r: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? r.maxY
        return CGRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height)
    }

    static func screen(containing axFrame: CGRect) -> NSScreen? {
        let center = CGPoint(x: axFrame.midX, y: axFrame.midY)
        return NSScreen.screens.first { axRect($0.frame).contains(center) } ?? NSScreen.main
    }
}

// MARK: - Quit protection: hold ⌘Q (and ⌘W in chosen apps) to quit

@MainActor
final class QuitGuard: ObservableObject {
    static let shared = QuitGuard()
    static let holdSeconds: TimeInterval = 0.7

    @Published private(set) var holding: (app: String, progress: Double)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pressStart: Date?
    private var timer: Timer?
    private var hud: NSPanel?

    func featureChanged() {
        if FeatureHub.shared.isOn(.quitProtection) { start() } else { stop() }
    }

    private func start() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                callback: { _, type, event, _ in
            let keep = MainActor.assumeIsolated { QuitGuard.shared.handle(type, event) }
            return keep ? Unmanaged.passUnretained(event) : nil
        }, userInfo: nil)
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// true lets the event through.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        guard code == Int64(kVK_ANSI_Q), flags.contains(.maskCommand),
              !flags.contains(.maskShift), !flags.contains(.maskAlternate), !flags.contains(.maskControl),
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.bundleIdentifier != "com.apple.finder" else { return true }
        if type == .keyDown {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { begin(app) }
            return false
        }
        cancel()
        return false
    }

    private func begin(_ app: NSRunningApplication) {
        pressStart = Date()
        holding = (app.localizedName ?? "", 0)
        showHUD()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            MainActor.assumeIsolated { QuitGuard.shared.tick(app) }
        }
    }

    private func tick(_ app: NSRunningApplication) {
        guard let start = pressStart else { return }
        let progress = Date().timeIntervalSince(start) / Self.holdSeconds
        holding = (app.localizedName ?? "", min(1, progress))
        if progress >= 1 {
            cancel()
            app.terminate()
        }
    }

    private func cancel() {
        timer?.invalidate()
        timer = nil
        pressStart = nil
        holding = nil
        hud?.orderOut(nil)
    }

    private func showHUD() {
        if hud == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 74), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .statusBar
            panel.ignoresMouseEvents = true
            panel.contentView = NSHostingView(rootView: QuitHUD())
            hud = panel
        }
        if let screen = NSScreen.main {
            hud?.setFrameOrigin(NSPoint(x: screen.frame.midX - 150, y: screen.frame.minY + screen.frame.height * 0.22))
        }
        hud?.orderFrontRegardless()
    }
}

import SwiftUI

private struct QuitHUD: View {
    @ObservedObject private var guardian = QuitGuard.shared
    var body: some View {
        VStack(spacing: 8) {
            Text(String(format: String(localized: "quit.hold %@", defaultValue: "Hold ⌘Q to quit %@"), guardian.holding?.app ?? ""))
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(RafiqLook.gold).frame(width: g.size.width * (guardian.holding?.progress ?? 0))
                }
            }
            .frame(height: 5)
        }
        .padding(16)
        .frame(width: 300, height: 74)
        .background(Color.black.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Quit on close: chosen apps quit when their last window closes

@MainActor
final class QuitOnClose: ObservableObject {
    static let shared = QuitOnClose()
    static let appsKey = "quitOnClose.apps"
    @Published var bundles: [String] = UserDefaults.standard.stringArray(forKey: QuitOnClose.appsKey) ?? ["com.apple.Preview", "com.apple.TextEdit"] {
        didSet { UserDefaults.standard.set(bundles, forKey: Self.appsKey) }
    }
    private var timer: Timer?
    private var hadWindows: Set<pid_t> = []

    func featureChanged() {
        timer?.invalidate()
        timer = nil
        guard FeatureHub.shared.isOn(.quitOnClose) else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated { QuitOnClose.shared.check() }
        }
    }

    private func check() {
        let apps = NSWorkspace.shared.runningApplications.filter { bundles.contains($0.bundleIdentifier ?? "") }
        guard !apps.isEmpty else { hadWindows = []; return }
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let withWindows = Set(info.filter { ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }
            .compactMap { $0[kCGWindowOwnerPID as String] as? pid_t })
        for app in apps {
            let pid = app.processIdentifier
            if withWindows.contains(pid) { hadWindows.insert(pid) }
            else if hadWindows.contains(pid) {
                hadWindows.remove(pid)
                app.terminate()
            }
        }
    }
}

// MARK: - Spaces in a fixed order

enum SpacesOrder {
    static var fixed: Bool {
        UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "mru-spaces") as? Bool == false
    }

    static func set(fixed: Bool) {
        _ = JarvisMac.run("/usr/bin/defaults", ["write", "com.apple.dock", "mru-spaces", "-bool", fixed ? "false" : "true"])
        _ = JarvisMac.run("/usr/bin/killall", ["Dock"])
    }
}

// MARK: - Window switcher (⌥⇥): every window, searchable

struct SwitchWindow: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let app: String
    let title: String
    let icon: NSImage?
}

@MainActor
final class WindowSwitcher: ObservableObject {
    static let shared = WindowSwitcher()
    @Published private(set) var windows: [SwitchWindow] = []
    @Published var query = ""
    @Published var selection = 0
    private var panel: NSPanel?

    var shown: [SwitchWindow] {
        let q = query.lowercased()
        return q.isEmpty ? windows : windows.filter { $0.app.lowercased().contains(q) || $0.title.lowercased().contains(q) }
    }

    func show() {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        windows = info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0, let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  pid != getpid(), let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = w[kCGWindowBounds as String] as? [String: CGFloat], (bounds["Width"] ?? 0) > 80 else { return nil }
            let app = NSRunningApplication(processIdentifier: pid)
            return SwitchWindow(id: id, pid: pid, app: app?.localizedName ?? (w[kCGWindowOwnerName as String] as? String ?? ""),
                                title: w[kCGWindowName as String] as? String ?? "", icon: app?.icon)
        }
        query = ""
        selection = windows.count > 1 ? 1 : 0
        if panel == nil {
            let p = SwitcherPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420), styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .modalPanel
            p.contentView = NSHostingView(rootView: SwitcherView())
            panel = p
        }
        if let screen = NSScreen.main {
            panel?.setFrameOrigin(NSPoint(x: screen.frame.midX - 280, y: screen.frame.midY - 210))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }

    func choose(_ w: SwitchWindow) {
        hide()
        guard let app = NSRunningApplication(processIdentifier: w.pid) else { return }
        app.activate()
        // Raise that window, not just the app.
        let axApp = AXUIElementCreateApplication(w.pid)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success, let list = value as? [AXUIElement] {
            for window in list {
                var title: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                if (title as? String ?? "") == w.title { AXUIElementPerformAction(window, kAXRaiseAction as CFString); break }
            }
        }
    }
}

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct SwitcherView: View {
    @ObservedObject private var switcher = WindowSwitcher.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "switcher.search", defaultValue: "Search a window"), text: $switcher.query)
                .textFieldStyle(.plain).font(.system(size: 15)).foregroundColor(.white)
                .focused($focused)
                .onSubmit { if switcher.shown.indices.contains(switcher.selection) { switcher.choose(switcher.shown[switcher.selection]) } }
                .onKeyPress(.escape) { switcher.hide(); return .handled }
                .onKeyPress(.downArrow) { switcher.selection = min(switcher.selection + 1, max(0, switcher.shown.count - 1)); return .handled }
                .onKeyPress(.upArrow) { switcher.selection = max(switcher.selection - 1, 0); return .handled }
                .onKeyPress(.tab) { switcher.selection = (switcher.selection + 1) % max(1, switcher.shown.count); return .handled }
                .padding(10).background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 10))
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(switcher.shown.enumerated()), id: \.element.id) { index, w in
                        HStack(spacing: 10) {
                            if let icon = w.icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: w.app).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                if !w.title.isEmpty { Text(verbatim: w.title).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1) }
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(index == switcher.selection ? RafiqLook.gold.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture { switcher.choose(w) }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 560, height: 420)
        .background(Color.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onAppear { focused = true }
    }
}
#endif
