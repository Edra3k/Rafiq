#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - Apps: updates, Homebrew, uninstaller, cleaner, old downloads, disk images
//
// Everything is read when its page opens and done on a click. Removals go to the Trash (never
// deleted for good), so a mistake is one drag away from being undone.

struct BrewPackage: Identifiable, Equatable {
    let name: String
    let installed: String
    let latest: String
    let cask: Bool
    var id: String { (cask ? "cask:" : "") + name }
}

struct Leftover: Identifiable, Equatable {
    let url: URL
    let size: Int64
    var id: String { url.path }
}

struct CleanItem: Identifiable, Equatable {
    let title: String
    let urls: [URL]
    let size: Int64
    /// Your own files (old downloads): shown in the Finder to sort by hand, never trashed in bulk.
    var personal = false
    var id: String { title }
}

@MainActor
final class AppsManager: ObservableObject {
    static let shared = AppsManager()

    @Published private(set) var outdated: [BrewPackage] = []
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var loadingUpdates = false
    @Published private(set) var searchResults: [String] = []
    @Published private(set) var log: String?

    @Published private(set) var apps: [URL] = []
    @Published private(set) var leftovers: [Leftover] = []
    @Published var chosenApp: URL?

    @Published private(set) var cleanItems: [CleanItem] = []
    @Published private(set) var scanningClean = false

    @Published private(set) var images: [URL] = []

    static var brew: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: Updates (Homebrew formulae and casks)

    func refreshUpdates() {
        guard let brew = Self.brew, !loadingUpdates else { return }
        loadingUpdates = true
        Task {
            let out = await Task.detached { JarvisMac.run(brew, ["outdated", "--json=v2"], timeout: 120) ?? "" }.value
            loadingUpdates = false
            outdated = Self.parseOutdated(out)
        }
    }

    nonisolated static func parseOutdated(_ out: String) -> [BrewPackage] {
        guard let data = out.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var list: [BrewPackage] = []
        for (key, cask) in [("formulae", false), ("casks", true)] {
            for item in json[key] as? [[String: Any]] ?? [] {
                guard let name = item["name"] as? String else { continue }
                if item["pinned"] as? Bool == true { continue }
                let installed = (item["installed_versions"] as? [String])?.last ?? ""
                let latest = item["current_version"] as? String ?? ""
                list.append(BrewPackage(name: name, installed: installed, latest: latest, cask: cask))
            }
        }
        return list.sorted { ($0.cask ? 0 : 1, $0.name) < ($1.cask ? 0 : 1, $1.name) }
    }

    func brew(_ args: [String], key: String, then: @escaping @MainActor () -> Void = {}) {
        guard let brew = Self.brew else { return }
        busy.insert(key)
        Task {
            let out = await Task.detached { JarvisMac.run(brew, args, timeout: 1800) }.value
            busy.remove(key)
            log = out.map { String($0.split(separator: "\n").last ?? "") }
            then()
        }
    }

    func upgrade(_ p: BrewPackage) {
        brew(["upgrade"] + (p.cask ? ["--cask"] : []) + [p.name], key: p.id) { [weak self] in
            self?.outdated.removeAll { $0.id == p.id }
        }
    }

    func upgradeAll() {
        brew(["upgrade"], key: "all") { [weak self] in self?.refreshUpdates() }
    }

    func search(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let brew = Self.brew, q.count >= 2 else { searchResults = []; return }
        Task {
            let out = await Task.detached { JarvisMac.run(brew, ["search", q], timeout: 60) ?? "" }.value
            searchResults = out.split(separator: "\n").map(String.init)
                .filter { !$0.hasPrefix("==>") && !$0.isEmpty }.prefix(30).map { $0 }
        }
    }

    func install(_ name: String) {
        brew(["install", name], key: "install:\(name)")
    }

    // MARK: Uninstaller

    func refreshApps() {
        let folders = ["/Applications", NSHomeDirectory() + "/Applications"]
        apps = folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
                .filter { $0.hasSuffix(".app") }
                .map { URL(fileURLWithPath: folder).appendingPathComponent($0) }
        }
        .filter { $0.lastPathComponent != "Rafiq.app" && !$0.path.hasPrefix("/System") }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    func choose(_ app: URL) {
        chosenApp = app
        leftovers = []
        Task {
            let found = await Task.detached { Self.leftovers(of: app) }.value
            if chosenApp == app { leftovers = found }
        }
    }

    /// The app and what it left in the Library: support files, caches, preferences, containers,
    /// saved state, logs, launch agents.
    nonisolated static func leftovers(of app: URL) -> [Leftover] {
        let bundle = Bundle(url: app)
        let id = bundle?.bundleIdentifier ?? ""
        let name = app.deletingPathExtension().lastPathComponent
        let lib = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        var urls: [URL] = [app]
        let fm = FileManager.default
        let places = ["Application Support", "Caches", "Containers", "Group Containers", "Saved Application State", "Logs",
                      "HTTPStorages", "WebKit", "Preferences", "LaunchAgents", "Application Scripts", "Cookies"]
        for place in places {
            let dir = lib.appendingPathComponent(place)
            guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for entry in entries {
                let lower = entry.lowercased()
                let matchesId = !id.isEmpty && lower.contains(id.lowercased())
                let matchesName = name.count >= 4 && (lower == name.lowercased() || lower.hasPrefix(name.lowercased() + "."))
                if matchesId || matchesName { urls.append(dir.appendingPathComponent(entry)) }
            }
        }
        return urls.map { Leftover(url: $0, size: size(of: $0)) }
    }

    func uninstall() {
        guard !leftovers.isEmpty else { return }
        let urls = leftovers.map(\.url)
        if let app = chosenApp, let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == app }) {
            running.terminate()
        }
        NSWorkspace.shared.recycle(urls) { [weak self] _, _ in
            Task { @MainActor in
                self?.leftovers = []
                self?.chosenApp = nil
                self?.refreshApps()
            }
        }
    }

    // MARK: Cleaner

    func scanClean() {
        guard !scanningClean else { return }
        scanningClean = true
        Task {
            let items = await Task.detached { Self.cleanCandidates() }.value
            cleanItems = items
            scanningClean = false
        }
    }

    nonisolated static func cleanCandidates() -> [CleanItem] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let fm = FileManager.default
        func children(_ path: String) -> [URL] {
            let dir = home.appendingPathComponent(path)
            return ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { !$0.lastPathComponent.hasPrefix("com.apple.") && !$0.lastPathComponent.contains("edra3k") }
        }
        var items: [CleanItem] = []
        func add(_ title: String, _ urls: [URL], personal: Bool = false) {
            let total = urls.reduce(Int64(0)) { $0 + size(of: $1) }
            if total > 1_000_000 { items.append(CleanItem(title: title, urls: urls, size: total, personal: personal)) }
        }
        add(String(localized: "apps.clean.caches", defaultValue: "App caches"), children("Library/Caches").filter { $0.lastPathComponent != "Homebrew" })
        add(String(localized: "apps.clean.logs", defaultValue: "Logs"), children("Library/Logs"))
        add(String(localized: "apps.clean.derived", defaultValue: "Xcode build data"), children("Library/Developer/Xcode/DerivedData"))
        add(String(localized: "apps.clean.simulators", defaultValue: "Old simulator caches"), children("Library/Developer/CoreSimulator/Caches"))
        add(String(localized: "apps.clean.brew", defaultValue: "Homebrew downloads"), children("Library/Caches/Homebrew/downloads"))
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        let downloads = ((try? fm.contentsOfDirectory(at: home.appendingPathComponent("Downloads"),
                                                      includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).flatMap { $0 } ?? Date() < cutoff }
        add(String(localized: "apps.clean.downloads", defaultValue: "Downloads older than 30 days"), downloads, personal: true)
        return items.sorted { $0.size > $1.size }
    }

    func clean(_ item: CleanItem) {
        NSWorkspace.shared.recycle(item.urls) { [weak self] _, _ in
            Task { @MainActor in self?.cleanItems.removeAll { $0.id == item.id } }
        }
    }

    // MARK: Disk images

    func refreshImages() {
        let volumes = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
        images = volumes.flatMap { volume -> [URL] in
            let root = URL(fileURLWithPath: "/Volumes").appendingPathComponent(volume)
            return ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
                .filter { $0.hasSuffix(".app") }.map { root.appendingPathComponent($0) }
        }
    }

    /// Copies the app to /Applications, then ejects its disk image.
    func installFromImage(_ app: URL) {
        let key = "dmg:\(app.path)"
        busy.insert(key)
        Task {
            let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(app.lastPathComponent)
            let ok = await Task.detached { () -> Bool in
                let fm = FileManager.default
                if fm.fileExists(atPath: destination.path) { try? fm.trashItem(at: destination, resultingItemURL: nil) }
                do { try fm.copyItem(at: app, to: destination) } catch { return false }
                return true
            }.value
            busy.remove(key)
            if ok {
                let volume = URL(fileURLWithPath: "/Volumes").appendingPathComponent(app.pathComponents[2])
                try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
                log = String(format: String(localized: "apps.dmg.done %@", defaultValue: "%@ is in Applications."), app.deletingPathExtension().lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } else {
                log = String(localized: "tools.media.failed", defaultValue: "That didn't work.")
            }
            refreshImages()
        }
    }

    // MARK: Helpers

    nonisolated static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        if let v = try? url.resourceValues(forKeys: keys), v.isDirectory != true { return Int64(v.totalFileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let next = walker?.nextObject() as? URL {
            total += Int64((try? next.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}

// MARK: - The Apps page of the Tools tab

struct AppsPage: View {
    @ObservedObject private var apps = AppsManager.shared
    @ObservedObject private var hub = FeatureHub.shared
    @AppStorage("apps.section") private var section = "updates"
    @State private var query = ""
    @State private var confirm: String?

    private var sections: [(String, String)] {
        var list: [(String, String)] = []
        if hub.isOn(.appUpdates) { list.append(("updates", String(localized: "apps.updates", defaultValue: "Updates"))) }
        if hub.isOn(.homebrew) { list.append(("brew", "Homebrew")) }
        if hub.isOn(.uninstaller) { list.append(("uninstall", String(localized: "apps.uninstall", defaultValue: "Uninstall"))) }
        if hub.isOn(.cleaner) { list.append(("clean", String(localized: "apps.clean", defaultValue: "Clean"))) }
        if hub.isOn(.diskImages) { list.append(("dmg", String(localized: "apps.dmg", defaultValue: "Disk images"))) }
        return list
    }

    private var shown: String { sections.contains { $0.0 == section } ? section : (sections.first?.0 ?? "updates") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(sections, id: \.0) { s in
                    Button { section = s.0 } label: {
                        Text(verbatim: s.1).font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(shown == s.0 ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(shown == s.0 ? Color.white.opacity(0.1) : Color.clear).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if let log = apps.log { Text(verbatim: log).font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079")).lineLimit(1) }
            }
            switch shown {
            case "brew": brewSection
            case "uninstall": uninstallSection
            case "clean": cleanSection
            case "dmg": dmgSection
            default: updatesSection
            }
        }
        .onAppear { load(shown) }
        .onChange(of: section) { _, s in load(s) }
    }

    private func load(_ s: String) {
        switch s {
        case "updates": if apps.outdated.isEmpty { apps.refreshUpdates() }
        case "uninstall": apps.refreshApps()
        case "clean": if apps.cleanItems.isEmpty { apps.scanClean() }
        case "dmg": apps.refreshImages()
        default: break
        }
    }

    @ViewBuilder private var updatesSection: some View {
        if AppsManager.brew == nil {
            note(String(localized: "apps.no-brew", defaultValue: "Updates come from Homebrew, which isn't installed."))
        } else if apps.loadingUpdates {
            HStack { ProgressView().controlSize(.small); note(String(localized: "apps.checking", defaultValue: "Checking…")) }
        } else if apps.outdated.isEmpty {
            note(String(localized: "apps.uptodate", defaultValue: "Everything is up to date."))
        } else {
            HStack {
                note(String(format: String(localized: "apps.outdated %lld", defaultValue: "%lld updates"), apps.outdated.count))
                Spacer()
                busyOr("all") { SmallButton(String(localized: "apps.update-all", defaultValue: "Update all")) { apps.upgradeAll() } }
            }
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(apps.outdated) { p in
                        HStack(spacing: 6) {
                            Image(systemName: p.cask ? "app" : "terminal").font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C"))
                            Text(verbatim: p.name).font(.system(size: 11)).foregroundColor(Color(hex: "#E1E3E6"))
                            Text(verbatim: "\(p.installed) → \(p.latest)").font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079")).lineLimit(1)
                            Spacer()
                            busyOr(p.id) { SmallButton(String(localized: "apps.update", defaultValue: "Update")) { apps.upgrade(p) } }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var brewSection: some View {
        HStack(spacing: 6) {
            TextField(String(localized: "apps.brew.search", defaultValue: "Search a formula or an app"), text: $query)
                .textFieldStyle(.plain).font(.system(size: 11.5))
                .onSubmit { apps.search(query) }
            SmallButton(String(localized: "apps.brew.find", defaultValue: "Search")) { apps.search(query) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8))
        ScrollView {
            VStack(spacing: 3) {
                ForEach(apps.searchResults, id: \.self) { name in
                    HStack {
                        Text(verbatim: name).font(.system(size: 11)).foregroundColor(Color(hex: "#E1E3E6"))
                        Spacer()
                        busyOr("install:\(name)") { SmallButton(String(localized: "apps.install", defaultValue: "Install")) { apps.install(name) } }
                    }
                }
            }
        }
    }

    @ViewBuilder private var uninstallSection: some View {
        if let app = apps.chosenApp {
            HStack {
                Button { apps.chosenApp = nil; confirm = nil } label: {
                    Label(String(localized: "tools.back", defaultValue: "Back"), systemImage: "chevron.left").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain)
                Spacer()
                let total = apps.leftovers.reduce(Int64(0)) { $0 + $1.size }
                Text(verbatim: AppsManager.bytes(total)).font(.system(size: 10.5)).foregroundColor(Color(hex: "#E1E3E6"))
                SmallButton(confirm == app.path ? String(localized: "tools.trash.confirm", defaultValue: "Sure?")
                                                : String(localized: "apps.to-trash", defaultValue: "Move to Trash")) {
                    if confirm == app.path { apps.uninstall(); confirm = nil } else { confirm = app.path }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(apps.leftovers) { l in
                        HStack {
                            Text(verbatim: (l.url.path as NSString).abbreviatingWithTildeInPath).font(.system(size: 10)).foregroundColor(Color(hex: "#B0B5BE"))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(verbatim: AppsManager.bytes(l.size)).font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                        }
                    }
                }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                    ForEach(apps.apps, id: \.self) { app in
                        Button { apps.choose(app) } label: {
                            VStack(spacing: 2) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 26, height: 26)
                                Text(verbatim: app.deletingPathExtension().lastPathComponent).font(.system(size: 8.5))
                                    .foregroundColor(Color(hex: "#B0B5BE")).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity).padding(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var cleanSection: some View {
        if apps.scanningClean {
            HStack { ProgressView().controlSize(.small); note(String(localized: "apps.measuring", defaultValue: "Measuring…")) }
        } else if apps.cleanItems.isEmpty {
            note(String(localized: "apps.clean.nothing", defaultValue: "Nothing worth cleaning."))
        }
        ScrollView {
            VStack(spacing: 4) {
                ForEach(apps.cleanItems) { item in
                    HStack {
                        Text(verbatim: item.title).font(.system(size: 11)).foregroundColor(Color(hex: "#E1E3E6"))
                        Spacer()
                        Text(verbatim: AppsManager.bytes(item.size)).font(.system(size: 11, weight: .semibold)).foregroundColor(RafiqLook.gold)
                        if item.personal {
                            SmallButton(String(localized: "apps.clean.show", defaultValue: "Show in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting(item.urls)
                            }
                        } else {
                            SmallButton(confirm == item.id ? String(localized: "tools.trash.confirm", defaultValue: "Sure?")
                                                           : String(localized: "apps.to-trash", defaultValue: "Move to Trash")) {
                                if confirm == item.id { apps.clean(item); confirm = nil } else { confirm = item.id }
                            }
                        }
                    }
                }
            }
        }
        note(String(localized: "apps.clean.hint", defaultValue: "Everything goes to the Trash: you can still put it back."))
    }

    @ViewBuilder private var dmgSection: some View {
        if apps.images.isEmpty {
            note(String(localized: "apps.dmg.none", defaultValue: "Open a disk image: its app shows up here, ready to install."))
        }
        ForEach(apps.images, id: \.self) { app in
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 24, height: 24)
                Text(verbatim: app.deletingPathExtension().lastPathComponent).font(.system(size: 11.5)).foregroundColor(Color(hex: "#E1E3E6"))
                Spacer()
                busyOr("dmg:\(app.path)") { SmallButton(String(localized: "apps.install", defaultValue: "Install")) { apps.installFromImage(app) } }
            }
        }
        Spacer(minLength: 0)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
    }

    @ViewBuilder private func busyOr<V: View>(_ key: String, @ViewBuilder _ content: () -> V) -> some View {
        if apps.busy.contains(key) { ProgressView().controlSize(.mini) } else { content() }
    }
}
#endif
