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

    var id: String { rawValue }

    enum Family: String, CaseIterable, Identifiable {
        case agents, system, energy, write, capture, apps
        var id: String { rawValue }
        var title: String {
            switch self {
            case .agents:  return String(localized: "feature.family.agents", defaultValue: "Agents")
            case .system:  return String(localized: "feature.family.system", defaultValue: "Your Mac")
            case .energy:  return String(localized: "feature.family.energy", defaultValue: "Energy")
            case .write:   return String(localized: "feature.family.write", defaultValue: "Write and paste")
            case .capture: return String(localized: "feature.family.capture", defaultValue: "Capture")
            case .apps:    return String(localized: "feature.family.apps", defaultValue: "Apps")
            }
        }
    }

    /// What the feature does while the user is not using it.
    enum AtRest {
        case nothing, files, network, clipboard
        var label: String {
            switch self {
            case .nothing: return String(localized: "feature.rest.nothing", defaultValue: "nothing at rest")
            case .files:   return String(localized: "feature.rest.files", defaultValue: "reads local files")
            case .network: return String(localized: "feature.rest.network", defaultValue: "asks your account")
            case .clipboard: return String(localized: "feature.rest.clipboard", defaultValue: "reads the clipboard")
            }
        }
    }

    var family: Family {
        switch self {
        case .claudeUsage: return .agents
        case .macMonitor, .speedTest, .ports: return .system
        case .keepAwake, .quickToggles: return .energy
        case .colorPicker, .screenText: return .capture
        case .quitApps: return .apps
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
        }
    }

    var atRest: AtRest {
        switch self {
        case .claudeUsage: return .network
        case .clipboard, .cleanURL: return .clipboard
        default: return .nothing
        }
    }

    var onByDefault: Bool { true }
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
    }

    func apply(_ pack: FeaturePack) {
        enabled = pack.features
        save()
        KeepAwake.shared.featureChanged()
        ClipboardHistory.shared.featureChanged()
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
