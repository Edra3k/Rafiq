#if !APPSTORE
import SwiftUI

// MARK: - Features: install only what you use
//
// Every tool Rafiq brings beyond the agents and the prayers is a feature the user turns on or
// off in Settings → Features. An off feature disappears from the island and loads nothing: no
// timer, no listener, no process. Each one says what it does at rest ("nothing", "reads the
// clipboard", "listens to the keyboard"), so the user knows what they let in.

enum RafiqFeature: String, CaseIterable, Identifiable {
    case claudeUsage, macMonitor, speedTest, ports, keepAwake, quickToggles, colorPicker, screenText, quitApps
    case clipboard, cleanURL, plainPaste, shelf, scratchpad
    case screenshots, recorder, camera, media
    case appUpdates, homebrew, uninstaller, cleaner, diskImages
    case outputSwitcher, micTools, musicBlocker, displays, bluetoothSleep, appMixer
    case windowLayout, windowSwitcher, quitProtection, quitOnClose, spacesOrder
    case commandBar, radialMenu, quickPanel
    case dockClicks, dockPreview, superKey
    case reverseScroll, linearScroll, sideButtons, clickFilter, keyDebounce, typedSnippets, finderShortcuts, focusFollowsMouse, pointerAccel

    var id: String { rawValue }

    enum Family: String, CaseIterable, Identifiable {
        case agents, quick, system, sound, energy, windows, input, write, capture, apps
        var id: String { rawValue }
        var title: String {
            switch self {
            case .agents:  return String(localized: "feature.family.agents", defaultValue: "Agents")
            case .system:  return String(localized: "feature.family.system", defaultValue: "Your Mac")
            case .sound:   return String(localized: "feature.family.sound", defaultValue: "Sound")
            case .energy:  return String(localized: "feature.family.energy", defaultValue: "Energy")
            case .windows: return String(localized: "feature.family.windows", defaultValue: "Windows")
            case .quick:   return String(localized: "feature.family.quick", defaultValue: "Quick access")
            case .input:   return String(localized: "feature.family.input", defaultValue: "Mouse and keyboard")
            case .write:   return String(localized: "feature.family.write", defaultValue: "Write and paste")
            case .capture: return String(localized: "feature.family.capture", defaultValue: "Capture")
            case .apps:    return String(localized: "feature.family.apps", defaultValue: "Apps")
            }
        }
    }

    /// What the feature does while the user is not using it.
    enum AtRest {
        case nothing, files, network, clipboard, keyboard, mouse
        var label: String {
            switch self {
            case .nothing: return String(localized: "feature.rest.nothing", defaultValue: "nothing at rest")
            case .files:   return String(localized: "feature.rest.files", defaultValue: "reads local files")
            case .network: return String(localized: "feature.rest.network", defaultValue: "asks your account")
            case .clipboard: return String(localized: "feature.rest.clipboard", defaultValue: "reads the clipboard")
            case .keyboard: return String(localized: "feature.rest.keyboard", defaultValue: "listens to the keyboard")
            case .mouse: return String(localized: "feature.rest.mouse", defaultValue: "listens to the mouse")
            }
        }
    }

    var family: Family {
        switch self {
        case .claudeUsage: return .agents
        case .macMonitor, .speedTest, .ports: return .system
        case .keepAwake, .quickToggles, .displays, .bluetoothSleep: return .energy
        case .outputSwitcher, .micTools, .musicBlocker, .appMixer: return .sound
        case .windowLayout, .windowSwitcher, .quitProtection, .quitOnClose, .spacesOrder, .dockClicks, .dockPreview: return .windows
        case .superKey: return .input
        case .commandBar, .radialMenu, .quickPanel: return .quick
        case .reverseScroll, .linearScroll, .sideButtons, .clickFilter, .keyDebounce, .typedSnippets, .finderShortcuts, .focusFollowsMouse, .pointerAccel: return .input
        case .colorPicker, .screenText, .screenshots, .recorder, .camera, .media: return .capture
        case .quitApps, .appUpdates, .homebrew, .uninstaller, .cleaner, .diskImages: return .apps
        case .clipboard, .cleanURL, .plainPaste, .shelf, .scratchpad: return .write
        }
    }

    var symbol: String {
        switch self {
        case .claudeUsage:  return "chart.bar.xaxis"
        case .macMonitor:   return "cpu"
        case .speedTest:    return "speedometer"
        case .ports:        return "point.3.connected.trianglepath.dotted"
        case .keepAwake:    return "cup.and.saucer"
        case .quickToggles: return "switch.2"
        case .colorPicker:  return "eyedropper"
        case .screenText:   return "text.viewfinder"
        case .quitApps:     return "xmark.app"
        case .clipboard:    return "doc.on.clipboard"
        case .cleanURL:     return "link"
        case .plainPaste:   return "textformat"
        case .shelf:        return "tray"
        case .scratchpad:   return "note.text"
        case .screenshots:  return "camera.viewfinder"
        case .recorder:     return "record.circle"
        case .camera:       return "web.camera"
        case .media:        return "photo.on.rectangle.angled"
        case .appUpdates:   return "arrow.triangle.2.circlepath"
        case .homebrew:     return "mug"
        case .uninstaller:  return "trash.square"
        case .cleaner:      return "sparkles"
        case .diskImages:   return "externaldrive"
        case .outputSwitcher: return "hifispeaker.2"
        case .micTools:     return "mic"
        case .musicBlocker: return "music.note.slash"
        case .displays:     return "sun.max"
        case .bluetoothSleep: return "bolt.horizontal.circle"
        case .appMixer:     return "slider.vertical.3"
        case .windowLayout: return "rectangle.split.2x1"
        case .windowSwitcher: return "square.on.square"
        case .quitProtection: return "hand.raised"
        case .quitOnClose:  return "xmark.square"
        case .spacesOrder:  return "square.stack.3d.up"
        case .commandBar:   return "sparkle.magnifyingglass"
        case .radialMenu:   return "circle.dashed"
        case .quickPanel:   return "square.grid.2x2"
        case .reverseScroll: return "arrow.up.arrow.down"
        case .linearScroll: return "scroll"
        case .sideButtons:  return "computermouse"
        case .clickFilter:  return "cursorarrow.click.2"
        case .keyDebounce:  return "keyboard"
        case .typedSnippets: return "text.badge.plus"
        case .finderShortcuts: return "folder"
        case .focusFollowsMouse: return "cursorarrow.motionlines"
        case .pointerAccel: return "speedometer"
        case .dockClicks:   return "dock.arrow.down.rectangle"
        case .dockPreview:  return "rectangle.on.rectangle"
        case .superKey:     return "capslock"
        }
    }

    var title: String {
        switch self {
        case .claudeUsage:  return String(localized: "feature.claudeUsage", defaultValue: "Agent usage")
        case .macMonitor:   return String(localized: "feature.macMonitor", defaultValue: "Mac monitor")
        case .speedTest:    return String(localized: "feature.speedTest", defaultValue: "Speed test")
        case .ports:        return String(localized: "feature.ports", defaultValue: "Open ports")
        case .keepAwake:    return String(localized: "feature.keepAwake", defaultValue: "Keep awake")
        case .quickToggles: return String(localized: "feature.quickToggles", defaultValue: "Quick toggles")
        case .colorPicker:  return String(localized: "feature.colorPicker", defaultValue: "Color picker")
        case .screenText:   return String(localized: "feature.screenText", defaultValue: "Text from screen")
        case .quitApps:     return String(localized: "feature.quitApps", defaultValue: "Quit apps")
        case .clipboard:    return String(localized: "feature.clipboard", defaultValue: "Clipboard history")
        case .cleanURL:     return String(localized: "feature.cleanURL", defaultValue: "Clean links")
        case .plainPaste:   return String(localized: "feature.plainPaste", defaultValue: "Paste as plain text")
        case .shelf:        return String(localized: "feature.shelf", defaultValue: "Shelf")
        case .scratchpad:   return String(localized: "feature.scratchpad", defaultValue: "Scratchpad")
        case .screenshots:  return String(localized: "feature.screenshots", defaultValue: "Screenshots")
        case .recorder:     return String(localized: "feature.recorder", defaultValue: "Screen recording")
        case .camera:       return String(localized: "feature.camera", defaultValue: "Camera preview")
        case .media:        return String(localized: "feature.media", defaultValue: "Media tools")
        case .appUpdates:   return String(localized: "feature.appUpdates", defaultValue: "App updates")
        case .homebrew:     return String(localized: "feature.homebrew", defaultValue: "Homebrew")
        case .uninstaller:  return String(localized: "feature.uninstaller", defaultValue: "Uninstaller")
        case .cleaner:      return String(localized: "feature.cleaner", defaultValue: "Cleaner")
        case .diskImages:   return String(localized: "feature.diskImages", defaultValue: "Disk image installer")
        case .outputSwitcher: return String(localized: "feature.outputSwitcher", defaultValue: "Sound outputs")
        case .micTools:     return String(localized: "feature.micTools", defaultValue: "Microphone")
        case .musicBlocker: return String(localized: "feature.musicBlocker", defaultValue: "Block the Music app")
        case .displays:     return String(localized: "feature.displays", defaultValue: "Displays")
        case .bluetoothSleep: return String(localized: "feature.bluetoothSleep", defaultValue: "Bluetooth off in sleep")
        case .appMixer:     return String(localized: "feature.appMixer", defaultValue: "Volume per app")
        case .windowLayout: return String(localized: "feature.windowLayout", defaultValue: "Window layout")
        case .windowSwitcher: return String(localized: "feature.windowSwitcher", defaultValue: "Window switcher")
        case .quitProtection: return String(localized: "feature.quitProtection", defaultValue: "Quit protection")
        case .quitOnClose:  return String(localized: "feature.quitOnClose", defaultValue: "Quit on close")
        case .spacesOrder:  return String(localized: "feature.spacesOrder", defaultValue: "Spaces in a fixed order")
        case .commandBar:   return String(localized: "command.title", defaultValue: "Command bar")
        case .radialMenu:   return String(localized: "feature.radialMenu", defaultValue: "Radial menu")
        case .quickPanel:   return String(localized: "feature.quickPanel", defaultValue: "Tools from anywhere")
        case .reverseScroll: return String(localized: "feature.reverseScroll", defaultValue: "Reverse the mouse wheel")
        case .linearScroll: return String(localized: "feature.linearScroll", defaultValue: "Linear scrolling")
        case .sideButtons:  return String(localized: "feature.sideButtons", defaultValue: "Side buttons")
        case .clickFilter:  return String(localized: "feature.clickFilter", defaultValue: "Extra click filter")
        case .keyDebounce:  return String(localized: "feature.keyDebounce", defaultValue: "Key debounce")
        case .typedSnippets: return String(localized: "feature.typedSnippets", defaultValue: "Typed snippets")
        case .finderShortcuts: return String(localized: "feature.finderShortcuts", defaultValue: "Finder shortcuts")
        case .focusFollowsMouse: return String(localized: "feature.focusFollowsMouse", defaultValue: "Focus follows mouse")
        case .pointerAccel: return String(localized: "feature.pointerAccel", defaultValue: "No pointer acceleration")
        case .dockClicks:   return String(localized: "feature.dockClicks", defaultValue: "Dock clicks")
        case .dockPreview:  return String(localized: "feature.dockPreview", defaultValue: "Dock preview")
        case .superKey:     return String(localized: "feature.superKey", defaultValue: "Super key")
        }
    }

    var detail: String {
        switch self {
        case .claudeUsage:  return String(localized: "feature.claudeUsage.detail", defaultValue: "Claude's limits, tokens and their API value")
        case .macMonitor:   return String(localized: "feature.macMonitor.detail", defaultValue: "Processor, memory, disk, network, battery")
        case .speedTest:    return String(localized: "feature.speedTest.detail", defaultValue: "Your connection's speed, measured by macOS")
        case .ports:        return String(localized: "feature.ports.detail", defaultValue: "What listens on a port, and stop it")
        case .keepAwake:    return String(localized: "feature.keepAwake.detail", defaultValue: "The Mac stays awake while an agent works")
        case .quickToggles: return String(localized: "feature.quickToggles.detail", defaultValue: "Dark mode, desktop icons, eject, Trash, lock")
        case .colorPicker:  return String(localized: "feature.colorPicker.detail", defaultValue: "Copy a color from the screen as HEX")
        case .screenText:   return String(localized: "feature.screenText.detail", defaultValue: "Select an area, its text is copied")
        case .quitApps:     return String(localized: "feature.quitApps.detail", defaultValue: "Every open app, quit one or all")
        case .clipboard:    return String(localized: "feature.clipboard.detail", defaultValue: "What you copied, searchable, pinned; keys masked and wiped (⌃⌥⌘V)")
        case .cleanURL:     return String(localized: "feature.cleanURL.detail", defaultValue: "Copied links lose their tracking parameters")
        case .plainPaste:   return String(localized: "feature.plainPaste.detail", defaultValue: "Paste without formatting (⌃⌥⇧V)")
        case .shelf:        return String(localized: "feature.shelf.detail", defaultValue: "Park files in the island, drag them out later")
        case .scratchpad:   return String(localized: "feature.scratchpad.detail", defaultValue: "Notes in tabs, saved as you type")
        case .screenshots:  return String(localized: "feature.screenshots.detail", defaultValue: "An area for Claude, the screen, a window, a QR code")
        case .recorder:     return String(localized: "feature.recorder.detail", defaultValue: "The screen with its sound and your microphone, to a movie")
        case .camera:       return String(localized: "feature.camera.detail", defaultValue: "Check yourself in the island before a call")
        case .media:        return String(localized: "feature.media.detail", defaultValue: "Compress a video, make a GIF, convert an image, read its text")
        case .appUpdates:   return String(localized: "feature.appUpdates.detail", defaultValue: "Apps and tools with a new version, updated in one click")
        case .homebrew:     return String(localized: "feature.homebrew.detail", defaultValue: "Search and install formulae and apps without a terminal")
        case .uninstaller:  return String(localized: "feature.uninstaller.detail", defaultValue: "An app and everything it left behind, to the Trash")
        case .cleaner:      return String(localized: "feature.cleaner.detail", defaultValue: "Caches, logs, build data and old downloads, measured")
        case .diskImages:   return String(localized: "feature.diskImages.detail", defaultValue: "The app of an open disk image, installed and ejected")
        case .outputSwitcher: return String(localized: "feature.outputSwitcher.detail", defaultValue: "Switch outputs; the speakers start low when headphones leave")
        case .micTools:     return String(localized: "feature.micTools.detail", defaultValue: "Choose the input, its level, mute it in one click")
        case .musicBlocker: return String(localized: "feature.musicBlocker.detail", defaultValue: "The play key no longer opens the Music app")
        case .displays:     return String(localized: "feature.displays.detail", defaultValue: "Each display's brightness, dimmed in software when needed")
        case .bluetoothSleep: return String(localized: "feature.bluetoothSleep.detail", defaultValue: "Off while the Mac sleeps, back on when it wakes")
        case .appMixer:     return String(localized: "feature.appMixer.detail", defaultValue: "Each app's volume up to 200 %, and its own output")
        case .windowLayout: return String(localized: "feature.windowLayout.detail", defaultValue: "Halves, thirds, full, center, next display with ⌃⌥ arrows, or a window dragged to an edge")
        case .windowSwitcher: return String(localized: "feature.windowSwitcher.detail", defaultValue: "Every window in one searchable list (⌥⇥)")
        case .quitProtection: return String(localized: "feature.quitProtection.detail", defaultValue: "Hold ⌘Q to quit an app, a slip of the finger does nothing")
        case .quitOnClose:  return String(localized: "feature.quitOnClose.detail", defaultValue: "Preview and TextEdit quit when their last window closes")
        case .spacesOrder:  return String(localized: "feature.spacesOrder.detail", defaultValue: "Spaces stay where you put them instead of moving by use")
        case .commandBar:   return String(localized: "feature.commandBar.detail", defaultValue: "Apps, files, clipboard, snippets, Rafiq's tools, sums, and Jarvis (⌃⌥K)")
        case .radialMenu:   return String(localized: "feature.radialMenu.detail", defaultValue: "Six actions around the pointer (⌃⌥R)")
        case .quickPanel:   return String(localized: "feature.quickPanel.detail", defaultValue: "The Tools tab from any app (⌃⌥⌘T)")
        case .reverseScroll: return String(localized: "feature.reverseScroll.detail", defaultValue: "The wheel scrolls the other way; the trackpad stays as it is")
        case .linearScroll: return String(localized: "feature.linearScroll.detail", defaultValue: "Each notch of the wheel scrolls three lines, however fast")
        case .sideButtons:  return String(localized: "feature.sideButtons.detail", defaultValue: "Back and Forward buttons go back and forward")
        case .clickFilter:  return String(localized: "feature.clickFilter.detail", defaultValue: "A worn button's double clicks are ignored")
        case .keyDebounce:  return String(localized: "feature.keyDebounce.detail", defaultValue: "A worn key's doubled letters are ignored")
        case .typedSnippets: return String(localized: "feature.typedSnippets.detail", defaultValue: "A snippet whose trigger starts with ; : / or ! is expanded as you type")
        case .finderShortcuts: return String(localized: "feature.finderShortcuts.detail", defaultValue: "⌘X then ⌘V moves files, F2 renames")
        case .focusFollowsMouse: return String(localized: "feature.focusFollowsMouse.detail", defaultValue: "The window under the pointer comes forward after a pause")
        case .pointerAccel: return String(localized: "feature.pointerAccel.detail", defaultValue: "The pointer moves as far as the mouse, at any speed")
        case .dockClicks:   return String(localized: "feature.dockClicks.detail", defaultValue: "A click on the app in front hides it")
        case .dockPreview:  return String(localized: "feature.dockPreview.detail", defaultValue: "Hover a Dock icon to see its windows, click one to bring it forward")
        case .superKey:     return String(localized: "feature.superKey.detail", defaultValue: "Caps Lock held is ⌃⌥⇧⌘ for your shortcuts, tapped alone it's Escape")
        }
    }

    var atRest: AtRest {
        switch self {
        case .claudeUsage: return .network
        case .clipboard, .cleanURL: return .clipboard
        case .windowLayout: return .mouse
        case .windowSwitcher, .quitProtection, .keyDebounce, .typedSnippets, .finderShortcuts: return .keyboard
        case .reverseScroll, .linearScroll, .sideButtons, .clickFilter, .focusFollowsMouse, .dockClicks, .dockPreview: return .mouse
        case .superKey: return .keyboard
        default: return .nothing
        }
    }

    /// The features that change how the Mac itself behaves start off.
    var onByDefault: Bool {
        family != .input && ![.musicBlocker, .bluetoothSleep, .windowSwitcher, .quitProtection, .quitOnClose, .spacesOrder,
                              .dockClicks, .dockPreview].contains(self)
    }
}

/// The packs that set the features in one click.
enum FeaturePack: String, CaseIterable, Identifiable {
    case dev, light, everything
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dev:        return String(localized: "feature.pack.dev", defaultValue: "Developer")
        case .light:      return String(localized: "feature.pack.light", defaultValue: "Light")
        case .everything: return String(localized: "feature.pack.all", defaultValue: "Everything")
        }
    }

    var detail: String {
        switch self {
        case .dev:        return String(localized: "feature.pack.dev.detail", defaultValue: "Usage, monitor, ports, keep awake")
        case .light:      return String(localized: "feature.pack.light.detail", defaultValue: "Only what does nothing at rest")
        case .everything: return String(localized: "feature.pack.all.detail", defaultValue: "Every feature, one click away")
        }
    }

    var symbol: String {
        switch self {
        case .dev: return "chevron.left.forwardslash.chevron.right"
        case .light: return "leaf"
        case .everything: return "square.grid.3x3"
        }
    }

    var features: Set<RafiqFeature> {
        switch self {
        case .dev: return [.claudeUsage, .macMonitor, .ports, .keepAwake, .quickToggles, .screenText, .clipboard, .cleanURL, .plainPaste, .scratchpad]
        case .light: return Set(RafiqFeature.allCases.filter { $0.atRest == .nothing })
        case .everything: return Set(RafiqFeature.allCases)
        }
    }
}

@MainActor
final class FeatureHub: ObservableObject {
    static let shared = FeatureHub()
    private static let key = "featureHub.enabled"
    private static let knownKey = "featureHub.known"

    @Published private(set) var enabled: Set<RafiqFeature>

    private init() {
        let ud = UserDefaults.standard
        if let saved = ud.array(forKey: Self.key) as? [String] {
            // A feature added by an update starts as its default; the user's choices stay.
            let known = Set(ud.stringArray(forKey: Self.knownKey) ?? saved)
            let added = RafiqFeature.allCases.filter { !known.contains($0.rawValue) && $0.onByDefault }
            enabled = Set(saved.compactMap(RafiqFeature.init(rawValue:))).union(added)
        } else {
            enabled = Set(RafiqFeature.allCases.filter(\.onByDefault))
        }
    }

    func isOn(_ feature: RafiqFeature) -> Bool { enabled.contains(feature) }

    func set(_ feature: RafiqFeature, _ on: Bool) {
        if on { enabled.insert(feature) } else { enabled.remove(feature) }
        save()
        if feature == .keepAwake { KeepAwake.shared.featureChanged() }
        if feature == .clipboard { ClipboardHistory.shared.featureChanged() }
        if [.outputSwitcher, .musicBlocker].contains(feature) { SoundCenter.shared.featureChanged() }
        if feature == .bluetoothSleep { BluetoothSleep.shared.featureChanged() }
        if [.windowLayout, .windowSwitcher, .commandBar, .radialMenu, .quickPanel].contains(feature) { WindowManager.shared.featureChanged() }
        if feature.family == .input { InputTools.shared.featureChanged() }
        if [.dockClicks, .dockPreview].contains(feature) { DockTools.shared.featureChanged() }
        if feature == .superKey { SuperKey.shared.featureChanged() }
        if feature == .pointerAccel { InputTools.setAcceleration(off: on) }
        if feature == .quitProtection { QuitGuard.shared.featureChanged() }
        if feature == .quitOnClose { QuitOnClose.shared.featureChanged() }
        if feature == .spacesOrder { SpacesOrder.set(fixed: on) }
        if feature == .appMixer { if on { AppMixer.shared.restore() } else { AppMixer.shared.stopAll() } }
    }

    func apply(_ pack: FeaturePack) {
        let before = enabled
        enabled = pack.features
        // The two that change a macOS setting follow the pack too.
        if before.contains(.spacesOrder) != enabled.contains(.spacesOrder) { SpacesOrder.set(fixed: enabled.contains(.spacesOrder)) }
        if before.contains(.pointerAccel) != enabled.contains(.pointerAccel) { InputTools.setAcceleration(off: enabled.contains(.pointerAccel)) }
        if before.contains(.appMixer) && !enabled.contains(.appMixer) { AppMixer.shared.stopAll() }
        save()
        KeepAwake.shared.featureChanged()
        ClipboardHistory.shared.featureChanged()
        SoundCenter.shared.featureChanged()
        BluetoothSleep.shared.featureChanged()
        WindowManager.shared.featureChanged()
        QuitGuard.shared.featureChanged()
        QuitOnClose.shared.featureChanged()
        InputTools.shared.featureChanged()
        DockTools.shared.featureChanged()
        SuperKey.shared.featureChanged()
    }

    func binding(_ feature: RafiqFeature) -> Binding<Bool> {
        Binding(get: { self.isOn(feature) }, set: { self.set(feature, $0) })
    }

    private func save() {
        UserDefaults.standard.set(enabled.map(\.rawValue).sorted(), forKey: Self.key)
        UserDefaults.standard.set(RafiqFeature.allCases.map(\.rawValue), forKey: Self.knownKey)
    }
}

// MARK: - Settings → Features

struct HubFeaturesPage: View {
    @ObservedObject private var hub = FeatureHub.shared

    var body: some View {
        HubPageScaffold(title: String(localized: "feature.page", defaultValue: "Features")) {
            HStack {
                Text(String(format: String(localized: "feature.count %lld %lld", defaultValue: "%lld of %lld on"),
                            hub.enabled.count, RafiqFeature.allCases.count))
                    .font(.system(size: 12)).foregroundColor(HubTheme.secondary)
                Spacer()
            }
            HubLabel(String(localized: "feature.packs", defaultValue: "Start with a pack"))
            HStack(spacing: 10) {
                ForEach(FeaturePack.allCases) { pack in
                    let current = hub.enabled == pack.features
                    Button { hub.apply(pack) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(pack.title, systemImage: pack.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(current ? RafiqLook.gold : HubTheme.text)
                            Text(pack.detail).font(.system(size: 11)).foregroundColor(HubTheme.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(HubTheme.card)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(current ? RafiqLook.gold.opacity(0.6) : HubTheme.line))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(RafiqFeature.Family.allCases) { family in
                let items = RafiqFeature.allCases.filter { $0.family == family }
                if !items.isEmpty {
                    HubLabel(family.title)
                    HubCard {
                        ForEach(Array(items.enumerated()), id: \.element) { index, feature in
                            if index > 0 { HubDivider() }
                            HStack(spacing: 12) {
                                Image(systemName: feature.symbol)
                                    .font(.system(size: 14))
                                    .foregroundColor(RafiqLook.gold)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(feature.title).font(.system(size: 13, weight: .medium))
                                        Text(feature.atRest.label)
                                            .font(.system(size: 10))
                                            .foregroundColor(HubTheme.muted)
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Color.white.opacity(0.06))
                                            .clipShape(Capsule())
                                    }
                                    Text(feature.detail).font(.system(size: 11)).foregroundColor(HubTheme.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: hub.binding(feature)).toggleStyle(.switch).labelsHidden()
                            }
                        }
                    }
                }
            }
            Text(String(localized: "feature.footer", defaultValue: "An off feature leaves the island and loads nothing. Its settings stay if you turn it back on."))
                .font(.system(size: 11)).foregroundColor(HubTheme.muted)
        }
    }
}
#endif
