#if !APPSTORE
import AppKit
import ApplicationServices
import Carbon

// MARK: - Mouse and keyboard
//
// One session event tap, created only while one of these features is on: the mouse wheel's
// direction and steps, the side buttons, the click filter, the key debounce, typed snippets and
// Finder's cut and paste. Focus follows mouse uses a passive monitor. Nothing typed is kept:
// the snippet buffer holds the last 32 characters, in memory, and is cleared on any click.

@MainActor
final class InputTools {
    static let shared = InputTools()
    static let linesKey = "input.linearLines"

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastKeyUp: [Int64: TimeInterval] = [:]
    private var lastMouseUp: TimeInterval = 0
    private var typed = ""
    private var finderCut = false
    private var focusMonitor: Any?
    private var focusWork: DispatchWorkItem?

    private var tapFeatures: [RafiqFeature] {
        [.reverseScroll, .linearScroll, .sideButtons, .clickFilter, .keyDebounce, .typedSnippets, .finderShortcuts]
    }

    func featureChanged() {
        let hub = FeatureHub.shared
        let needTap = tapFeatures.contains(where: hub.isOn)
        if needTap { startTap() } else { stopTap() }
        if hub.isOn(.focusFollowsMouse) { startFocus() } else { stopFocus() }
    }

    // MARK: The event tap

    private func startTap() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else { WindowManager.askAccessibility(); return }
        let types: [CGEventType] = [.keyDown, .keyUp, .scrollWheel, .otherMouseDown, .otherMouseUp, .leftMouseDown, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                callback: { _, type, event, _ in
            let keep = MainActor.assumeIsolated { InputTools.shared.handle(type, event) }
            return keep ? Unmanaged.passUnretained(event) : nil
        }, userInfo: nil)
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// true lets the event through (possibly changed).
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let hub = FeatureHub.shared
        let now = ProcessInfo.processInfo.systemUptime
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true

        case .scrollWheel:
            // A mouse wheel, not a trackpad or a Magic Mouse (those are continuous).
            guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return true }
            if hub.isOn(.linearScroll) {
                let lines = Int64(UserDefaults.standard.object(forKey: Self.linesKey) as? Int ?? 3)
                let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                if delta != 0 {
                    let fixed = (delta > 0 ? 1 : -1) * lines
                    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: fixed)
                    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: fixed * 10)
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(fixed))
                }
            }
            if hub.isOn(.reverseScroll) {
                for (line, point, fixed) in [(CGEventField.scrollWheelEventDeltaAxis1, CGEventField.scrollWheelEventPointDeltaAxis1, CGEventField.scrollWheelEventFixedPtDeltaAxis1),
                                             (.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2)] {
                    event.setIntegerValueField(line, value: -event.getIntegerValueField(line))
                    event.setIntegerValueField(point, value: -event.getIntegerValueField(point))
                    event.setDoubleValueField(fixed, value: -event.getDoubleValueField(fixed))
                }
            }
            return true

        case .otherMouseDown, .otherMouseUp:
            guard hub.isOn(.sideButtons) else { return true }
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            guard button == 3 || button == 4 else { return true }
            if type == .otherMouseDown { Self.postKey(button == 3 ? UInt16(kVK_ANSI_LeftBracket) : UInt16(kVK_ANSI_RightBracket), flags: .maskCommand) }
            return false

        case .leftMouseDown:
            typed = ""
            if hub.isOn(.clickFilter), now - lastMouseUp < 0.045 { return false }
            return true

        case .leftMouseUp:
            lastMouseUp = now
            return true

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let repeatKey = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if hub.isOn(.keyDebounce), !repeatKey, let up = lastKeyUp[code], now - up < 0.035 { return false }
            if hub.isOn(.finderShortcuts), NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
               let handled = finder(code: code, flags: event.flags) { return handled }
            if hub.isOn(.typedSnippets) { trackTyped(event, code: code) }
            return true

        case .keyUp:
            lastKeyUp[event.getIntegerValueField(.keyboardEventKeycode)] = now
            return true

        default:
            return true
        }
    }

    // MARK: Finder: ⌘X then ⌘V moves, F2 renames

    private func finder(code: Int64, flags: CGEventFlags) -> Bool? {
        let command = flags.contains(.maskCommand) && !flags.contains(.maskShift) && !flags.contains(.maskControl)
        if command && code == Int64(kVK_ANSI_X) && !flags.contains(.maskAlternate) {
            finderCut = true
            Self.postKey(UInt16(kVK_ANSI_C), flags: .maskCommand)
            return false
        }
        if command && code == Int64(kVK_ANSI_V) && finderCut && !flags.contains(.maskAlternate) {
            finderCut = false
            Self.postKey(UInt16(kVK_ANSI_V), flags: [.maskCommand, .maskAlternate])
            return false
        }
        if command && code == Int64(kVK_ANSI_C) { finderCut = false }
        if code == Int64(kVK_F2) && flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty {
            Self.postKey(UInt16(kVK_Return), flags: [])
            return false
        }
        return nil
    }

    // MARK: Typed snippets: a trigger that starts with ; : / or ! becomes its text

    private func trackTyped(_ event: CGEvent, code: Int64) {
        if code == Int64(kVK_Delete) { typed = String(typed.dropLast()); return }
        if [kVK_Return, kVK_Tab, kVK_Escape, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].map(Int64.init).contains(code) {
            typed = ""
            return
        }
        if event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) { typed = ""; return }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return }
        typed += String(utf16CodeUnits: chars, count: length)
        if typed.count > 32 { typed = String(typed.suffix(32)) }
        let snippets = FlowStore.shared.snippets.filter { $0.trigger.count >= 2 && ";:/!".contains($0.trigger.first!) }
        guard let hit = snippets.first(where: { typed.hasSuffix($0.trigger) }) else { return }
        let erase = hit.trigger.count - 1   // the last character hasn't reached the app yet
        typed = ""
        let text = Self.expand(hit.text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            for _ in 0..<erase { InputTools.postKey(UInt16(kVK_Delete), flags: []) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                InputTools.postKey(UInt16(kVK_Delete), flags: [])
                _ = FlowPaste.insert(text)
            }
        }
    }

    /// {date}, {time} and {clipboard} in a snippet.
    static func expand(_ text: String) -> String {
        let now = Date()
        return text
            .replacingOccurrences(of: "{date}", with: now.formatted(date: .abbreviated, time: .omitted))
            .replacingOccurrences(of: "{time}", with: now.formatted(date: .omitted, time: .shortened))
            .replacingOccurrences(of: "{clipboard}", with: NSPasteboard.general.string(forType: .string) ?? "")
    }

    static func postKey(_ code: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    // MARK: Focus follows mouse

    private func startFocus() {
        guard focusMonitor == nil else { return }
        focusMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
            MainActor.assumeIsolated { InputTools.shared.mouseMoved() }
        }
    }

    private func stopFocus() {
        if let focusMonitor { NSEvent.removeMonitor(focusMonitor) }
        focusMonitor = nil
    }

    private func mouseMoved() {
        focusWork?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated { InputTools.shared.focusUnderPointer() }
        }
        focusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func focusUnderPointer() {
        guard AXIsProcessTrusted(), NSEvent.pressedMouseButtons == 0 else { return }
        let mouse = NSEvent.mouseLocation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(mouse.x), Float(top - mouse.y), &element) == .success,
              let element else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
              app != NSWorkspace.shared.frontmostApplication else { return }
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &window) == .success, let window {
            AXUIElementPerformAction(window as! AXUIElement, kAXRaiseAction as CFString)
        }
        app.activate()
    }

    // MARK: Pointer acceleration (macOS's own setting)

    static var accelerationOff: Bool {
        UserDefaults(suiteName: ".GlobalPreferences")?.object(forKey: "com.apple.mouse.linear") as? Bool ?? false
    }

    static func setAcceleration(off: Bool) {
        _ = JarvisMac.run("/usr/bin/defaults", ["write", ".GlobalPreferences", "com.apple.mouse.linear", "-bool", off ? "true" : "false"])
    }
}
#endif
