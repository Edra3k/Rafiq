#if !APPSTORE
import AppKit
import ApplicationServices
import ScreenCaptureKit
import SwiftUI

// MARK: - The Dock: a click on the app in front hides it; hovering an icon shows its windows
//
// Both read what is under the pointer through Accessibility (the Dock's own items) with passive
// monitors: nothing is intercepted, and nothing runs while both features are off.

@MainActor
final class DockTools: ObservableObject {
    static let shared = DockTools()

    struct Preview: Identifiable {
        let id: CGWindowID
        let title: String
        let image: NSImage?
    }

    @Published private(set) var appName = ""
    @Published private(set) var previews: [Preview] = []
    private var monitors: [Any] = []
    private var frontAtDown: String?
    private var hoverWork: DispatchWorkItem?
    private var hovered: String?
    private var panel: NSPanel?

    func featureChanged() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        let hub = FeatureHub.shared
        if hub.isOn(.dockClicks) {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { _ in
                MainActor.assumeIsolated { DockTools.shared.mouseDown() }
            }) { monitors.append(m) }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in
                MainActor.assumeIsolated { DockTools.shared.mouseUp() }
            }) { monitors.append(m) }
        }
        if hub.isOn(.dockPreview) {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { _ in
                MainActor.assumeIsolated { DockTools.shared.mouseMoved() }
            }) { monitors.append(m) }
        } else {
            hidePreview()
        }
    }

    /// The Dock item's title under the pointer, if any.
    private func dockItem() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let mouse = NSEvent.mouseLocation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(mouse.x), Float(top - mouse.y), &element) == .success,
              let element else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock" else { return nil }
        var subrole: CFTypeRef?, title: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard (subrole as? String) == "AXApplicationDockItem" else { return nil }
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        return title as? String
    }

    private func app(named name: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == name && $0.activationPolicy == .regular }
    }

    // MARK: Dock clicks

    private func mouseDown() {
        frontAtDown = nil
        guard let name = dockItem(), let app = app(named: name), app == NSWorkspace.shared.frontmostApplication else { return }
        frontAtDown = name
    }

    private func mouseUp() {
        guard let name = frontAtDown else { return }
        frontAtDown = nil
        guard dockItem() == name, let app = app(named: name) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { app.hide() }
    }

    // MARK: Dock preview

    private func mouseMoved() {
        hoverWork?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { DockTools.shared.checkHover() } }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func checkHover() {
        let name = dockItem()
        if name == nil {
            // Keep the preview while the pointer is on it.
            if let panel, panel.isVisible, NSMouseInRect(NSEvent.mouseLocation, panel.frame.insetBy(dx: -8, dy: -8), false) { return }
            hidePreview()
            return
        }
        guard name != hovered, let name, let app = app(named: name) else { return }
        hovered = name
        Task { await showPreview(for: app) }
    }

    private func showPreview(for app: NSRunningApplication) async {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }
        let windows = content.windows.filter {
            $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 120 && $0.frame.height > 80
        }.prefix(4)
        guard !windows.isEmpty else { hidePreview(); return }
        var list: [Preview] = []
        for w in windows {
            let config = SCStreamConfiguration()
            let scale = 220 / max(w.frame.width, 1)
            config.width = Int(w.frame.width * scale * 2)
            config.height = Int(w.frame.height * scale * 2)
            let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: config)
            list.append(Preview(id: w.windowID, title: w.title ?? "", image: image.map { NSImage(cgImage: $0, size: .zero) }))
        }
        guard hovered == app.localizedName else { return }
        appName = app.localizedName ?? ""
        previews = list
        present(near: NSEvent.mouseLocation)
    }

    private func present(near point: NSPoint) {
        let width = CGFloat(previews.count) * 236 + 20, height: CGFloat = 190
        if panel == nil {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .popUpMenu
            p.contentView = NSHostingView(rootView: DockPreviewView())
            panel = p
        }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return }
        let x = min(max(point.x - width / 2, screen.frame.minX + 8), screen.frame.maxX - width - 8)
        let y = screen.visibleFrame.minY + 6
        panel?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel?.orderFrontRegardless()
    }

    func hidePreview() {
        hovered = nil
        panel?.orderOut(nil)
    }

    /// Brings that window forward.
    func open(_ preview: Preview) {
        guard let app = app(named: appName) else { return }
        app.activate()
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] {
            for w in windows {
                var title: CFTypeRef?
                AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &title)
                if (title as? String ?? "") == preview.title {
                    AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                    break
                }
            }
        }
        hidePreview()
    }
}

private struct DockPreviewView: View {
    @ObservedObject private var dock = DockTools.shared
    var body: some View {
        HStack(spacing: 12) {
            ForEach(dock.previews) { p in
                VStack(spacing: 4) {
                    if let image = p.image {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 220, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)).frame(width: 220, height: 140)
                    }
                    Text(verbatim: p.title.isEmpty ? dock.appName : p.title).font(.system(size: 11)).foregroundColor(.white).lineLimit(1)
                }
                .frame(width: 224)
                .contentShape(Rectangle())
                .onTapGesture { dock.open(p) }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Super key: Caps Lock becomes ⌃⌥⇧⌘ while held, Escape when tapped alone

@MainActor
final class SuperKey {
    static let shared = SuperKey()
    private static let f18: Int64 = 79
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held = false
    private var used = false

    func featureChanged() {
        if FeatureHub.shared.isOn(.superKey) { start() } else { stop() }
    }

    private func start() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        // Caps Lock (0x700000039) reports as F18 (0x70000006D) while Rafiq runs.
        _ = JarvisMac.run("/usr/bin/hidutil", ["property", "--set",
            "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x700000039,\"HIDKeyboardModifierMappingDst\":0x70000006D}]}"])
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                callback: { _, type, event, _ in
            let keep = MainActor.assumeIsolated { SuperKey.shared.handle(type, event) }
            return keep ? Unmanaged.passUnretained(event) : nil
        }, userInfo: nil)
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Caps Lock is given back to macOS.
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        _ = JarvisMac.run("/usr/bin/hidutil", ["property", "--set", "{\"UserKeyMapping\":[]}"])
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == Self.f18 {
            if type == .keyDown {
                if !held { held = true; used = false }
            } else {
                held = false
                if !used { InputTools.postKey(53, flags: []) }   // alone: Escape
            }
            return false
        }
        if held {
            used = true
            event.flags.formUnion([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        }
        return true
    }
}
#endif
