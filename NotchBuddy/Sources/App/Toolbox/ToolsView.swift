#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - The Tools tab of the island
//
// Rafiq stays on the left as everywhere; on the right, three pages: the installed tools in
// tiles, the Mac (processor, memory, disk, network, battery, what consumes, open ports), and the
// agents' usage (Claude's limits, tokens and their API value).

struct ToolsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var hub = FeatureHub.shared
    @AppStorage("tools.page") private var page = "tools"
    @Environment(\.islandViewActive) private var active

    private var pages: [(id: String, title: String)] {
        var list = [("tools", String(localized: "tools.page.tools", defaultValue: "Tools"))]
        if hub.isOn(.macMonitor) { list.append(("mac", String(localized: "tools.page.mac", defaultValue: "Mac"))) }
        if hub.isOn(.claudeUsage) { list.append(("usage", String(localized: "tools.page.usage", defaultValue: "Usage"))) }
        if hub.isOn(.clipboard) { list.append(("clip", String(localized: "tools.page.clip", defaultValue: "Clipboard"))) }
        if hub.isOn(.shelf) { list.append(("shelf", String(localized: "feature.shelf", defaultValue: "Shelf"))) }
        if hub.isOn(.scratchpad) { list.append(("notes", String(localized: "tools.page.notes", defaultValue: "Notes"))) }
        return list
    }

    private var shown: String { pages.contains { $0.id == page } ? page : "tools" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(pages, id: \.id) { p in
                        Button { withAnimation(.easeInOut(duration: 0.15)) { page = p.id } } label: {
                            Text(p.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(shown == p.id ? RafiqLook.gold : Color(hex: "#8E939C"))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(shown == p.id ? RafiqLook.gold.opacity(0.14) : Color.white.opacity(0.04))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button { SettingsOpener.features() } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "tools.manage", defaultValue: "Choose the features"))
                }
                switch shown {
                case "mac": MacPage(active: active)
                case "usage": UsagePage(state: state, active: active)
                case "clip": ClipboardPage()
                case "shelf": ShelfPage()
                case "notes": NotesPage()
                default: ToolsGrid()
                }
            }
            .padding(.leading, 112)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
        }
    }
}

enum SettingsOpener {
    @MainActor static func features() {
        FlowHubController.shared.show(.features)
    }
}

// MARK: - Clipboard page

private struct ClipboardPage: View {
    @ObservedObject private var history = ClipboardHistory.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                TextField(String(localized: "tools.clip.search", defaultValue: "Search what you copied"), text: $history.query)
                    .textFieldStyle(.plain).font(.system(size: 11.5))
                SmallButton(String(localized: "tools.clip.clear", defaultValue: "Clear")) { history.clearUnpinned() }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8))
            if history.shown.isEmpty {
                Text(String(localized: "tools.clip.empty", defaultValue: "Copy something: it shows up here."))
                    .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).padding(.top, 6)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(history.shown) { item in ClipRow(item: item) }
                }
            }
            Text(String(localized: "tools.clip.hint", defaultValue: "Click to paste in the front app · ⌃⌥⌘V opens this page"))
                .font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
        }
    }
}

private struct ClipRow: View {
    let item: ClipItem
    @State private var hovered = false

    private var symbol: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .file: return "doc"
        case .image: return "photo"
        case .secret: return "key"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.pinned ? "pin.fill" : symbol).font(.system(size: 10))
                .foregroundColor(item.pinned ? RafiqLook.gold : item.kind == .secret ? Color(hex: "#F4505E") : Color(hex: "#8E939C"))
                .frame(width: 14)
            if item.kind == .image, let data = item.imageData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 22).clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(verbatim: item.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                .font(.system(size: 11, design: item.kind == .secret ? .monospaced : .default))
                .foregroundColor(Color(hex: item.kind == .secret ? "#8E939C" : "#E1E3E6")).lineLimit(1)
            if item.cleaned {
                Text(String(localized: "tools.clip.cleaned", defaultValue: "cleaned")).font(.system(size: 9)).foregroundColor(Color(hex: "#34D399"))
            }
            Spacer(minLength: 4)
            if hovered && item.kind != .secret {
                Button { ClipboardHistory.shared.togglePin(item) } label: { Image(systemName: item.pinned ? "pin.slash" : "pin") }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C"))
                Button { ClipboardHistory.shared.use(item, paste: false) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C"))
                Button { ClipboardHistory.shared.remove(item) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C"))
            } else {
                Text(verbatim: item.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                    .font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Color.white.opacity(hovered ? 0.06 : 0)).clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture {
            guard item.kind != .secret else { return }
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { ClipboardHistory.shared.use(item, paste: true) }
        }
    }
}

// MARK: - Shelf page

private struct ShelfPage: View {
    @ObservedObject private var shelf = Shelf.shared
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "tools.shelf.hint", defaultValue: "Drop files here, drag them out when you need them."))
                    .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                Spacer()
                if !shelf.paths.isEmpty { SmallButton(String(localized: "tools.clip.clear", defaultValue: "Clear")) { shelf.clear() } }
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(shelf.paths, id: \.self) { path in ShelfTile(path: path) }
                }
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(targeted ? RafiqLook.gold : Color.white.opacity(0.12)))
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in Shelf.shared.add([url]) }
                    }
                }
                return true
            }
        }
    }
}

private struct ShelfTile: View {
    let path: String
    @State private var hovered = false
    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 30, height: 30)
            Text(verbatim: (path as NSString).lastPathComponent).font(.system(size: 9)).foregroundColor(Color(hex: "#B0B5BE"))
                .lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity).padding(6)
        .background(Color.white.opacity(hovered ? 0.08 : 0.04)).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button { Shelf.shared.remove(path) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain).padding(2)
            }
        }
        .onHover { hovered = $0 }
        .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    }
}

// MARK: - Notes page

private struct NotesPage: View {
    @ObservedObject private var pad = Scratchpad.shared
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(pad.notes) { note in
                            Button { pad.selected = note.id } label: {
                                Text(verbatim: note.title).font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(pad.selected == note.id ? RafiqLook.gold : Color(hex: "#8E939C"))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(pad.selected == note.id ? RafiqLook.gold.opacity(0.12) : Color.white.opacity(0.04))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(String(localized: "tools.notes.delete", defaultValue: "Delete this note")) { pad.delete(note.id) }
                            }
                        }
                        Button { pad.add() } label: { Image(systemName: "plus").font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C")) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if let id = pad.selected {
                TextEditor(text: pad.binding(for: id))
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 6) {
                    SmallButton(String(localized: "tools.notes.copy", defaultValue: "Copy")) {
                        ClipboardHistory.shared.write(pad.binding(for: id).wrappedValue)
                    }
                    SmallButton(sent ? String(localized: "tools.notes.sent", defaultValue: "Sent to Claude")
                                     : String(localized: "tools.notes.send", defaultValue: "Send to Claude")) {
                        let text = pad.binding(for: id).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        _ = AskRunner.shared.ask(text, chosen: .claude, source: "notes")
                        sent = true
                    }
                    Spacer()
                    Text(String(localized: "tools.notes.saved", defaultValue: "saved as you type")).font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
                }
            }
        }
        .onChange(of: pad.selected) { _, _ in sent = false }
    }
}

// MARK: - Tools grid

private struct ToolsGrid: View {
    @ObservedObject private var hub = FeatureHub.shared
    @ObservedObject private var awake = KeepAwake.shared
    @ObservedObject private var speed = SpeedTest.shared
    @State private var status: String?
    @State private var confirmTrash = false
    @State private var showingApps = false
    @State private var panel: String?
    @ObservedObject private var recorder = ScreenRecorder.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 6)

    var body: some View {
        if showingApps {
            QuitAppsList(back: { showingApps = false })
        } else if panel == "camera" {
            CameraPanel(back: { panel = nil })
        } else if panel == "media" {
            MediaPanel(back: { panel = nil })
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                LazyVGrid(columns: columns, spacing: 5) {
                    if hub.isOn(.keepAwake) {
                        ToolTile(symbol: "cup.and.saucer", title: String(localized: "tools.awake", defaultValue: "Awake"),
                                 on: awake.active, badge: awake.manualOn ? "1 h" : (awake.active ? "auto" : nil)) {
                            if awake.manualOn { awake.stopManual() } else { awake.keepFor(minutes: 60) }
                        }
                    }
                    if hub.isOn(.quickToggles) {
                        ToolTile(symbol: "circle.lefthalf.filled", title: String(localized: "tools.dark", defaultValue: "Dark mode")) {
                            QuickActions.toggleDarkMode()
                        }
                        ToolTile(symbol: "menubar.dock.rectangle", title: String(localized: "tools.desktop", defaultValue: "Desktop"),
                                 on: QuickActions.desktopIconsHidden) {
                            QuickActions.toggleDesktopIcons()
                        }
                        ToolTile(symbol: "eject", title: String(localized: "tools.eject", defaultValue: "Eject")) {
                            let n = QuickActions.ejectAll()
                            status = n == 0 ? String(localized: "tools.eject.none", defaultValue: "No disk to eject.")
                                : String(format: String(localized: "tools.eject.done %lld", defaultValue: "%lld disks ejected."), n)
                        }
                        ToolTile(symbol: "trash", title: confirmTrash ? String(localized: "tools.trash.confirm", defaultValue: "Sure?")
                                                                      : String(localized: "tools.trash", defaultValue: "Trash"),
                                 on: confirmTrash, badge: QuickActions.trashCount > 0 ? "\(QuickActions.trashCount)" : nil) {
                            if confirmTrash {
                                confirmTrash = false
                                QuickActions.emptyTrash()
                                status = String(localized: "tools.trash.done", defaultValue: "Trash emptied.")
                            } else {
                                confirmTrash = true
                                status = String(localized: "tools.trash.ask", defaultValue: "Click again to empty the Trash for good.")
                            }
                        }
                        ToolTile(symbol: "lock", title: String(localized: "tools.lock", defaultValue: "Lock")) {
                            QuickActions.lockScreen()
                        }
                    }
                    if hub.isOn(.colorPicker) {
                        ToolTile(symbol: "eyedropper", title: String(localized: "tools.color", defaultValue: "Color")) {
                            QuickActions.pickColor { hex in
                                if let hex { status = String(format: String(localized: "tools.color.copied %@", defaultValue: "%@ copied."), hex) }
                            }
                        }
                    }
                    if hub.isOn(.screenText) {
                        ToolTile(symbol: "text.viewfinder", title: String(localized: "tools.text", defaultValue: "Screen text")) {
                            Task {
                                if let text = await QuickActions.textFromScreen() {
                                    let lines = text.split(separator: "\n").count
                                    status = String(format: String(localized: "tools.text.copied %lld", defaultValue: "%lld lines copied."), lines)
                                }
                            }
                        }
                    }
                    if hub.isOn(.screenshots) {
                        ToolTile(symbol: "rectangle.dashed", title: String(localized: "tools.capture.area", defaultValue: "Area")) {
                            NotificationCenter.default.post(name: .islandCollapse, object: nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ScreenCapture.shared.begin() }
                        }
                        ToolTile(symbol: "macwindow", title: String(localized: "tools.capture.window", defaultValue: "Window")) {
                            NotificationCenter.default.post(name: .islandCollapse, object: nil)
                            CaptureExtras.window()
                            status = String(localized: "tools.capture.window.hint", defaultValue: "Click a window: it goes to the clipboard.")
                        }
                        ToolTile(symbol: "qrcode.viewfinder", title: "QR") {
                            Task {
                                if let code = await CaptureExtras.readCode() {
                                    status = String(format: String(localized: "tools.color.copied %@", defaultValue: "%@ copied."), String(code.prefix(60)))
                                } else {
                                    status = String(localized: "tools.qr.none", defaultValue: "No code found there.")
                                }
                            }
                        }
                    }
                    if hub.isOn(.recorder) {
                        ToolTile(symbol: recorder.recording ? "stop.circle.fill" : "record.circle",
                                 title: recorder.recording ? String(localized: "tools.record.stop", defaultValue: "Stop")
                                                           : String(localized: "tools.record", defaultValue: "Record"),
                                 on: recorder.recording,
                                 badge: recorder.recording ? TokenLedger.clock(recorder.elapsed) : nil) { recorder.toggle() }
                    }
                    if hub.isOn(.camera) {
                        ToolTile(symbol: "web.camera", title: String(localized: "tools.camera", defaultValue: "Camera")) { panel = "camera" }
                    }
                    if hub.isOn(.media) {
                        ToolTile(symbol: "photo.on.rectangle.angled", title: String(localized: "tools.media", defaultValue: "Media")) { panel = "media" }
                    }
                    if hub.isOn(.speedTest) {
                        ToolTile(symbol: "speedometer", title: speed.running ? String(localized: "tools.speed.running", defaultValue: "Testing…")
                                                                             : String(localized: "tools.speed", defaultValue: "Speed"),
                                 on: speed.running) { speed.run() }
                    }
                    if hub.isOn(.quitApps) {
                        ToolTile(symbol: "xmark.app", title: String(localized: "tools.quit", defaultValue: "Quit apps")) {
                            showingApps = true
                        }
                    }
                }
                }
                if let down = speed.down, !speed.running {
                    Text(verbatim: "↓ \(SpeedTest.mbps(down))" + (speed.up.map { "   ↑ \(SpeedTest.mbps($0))" } ?? ""))
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#E1E3E6"))
                }
                if let status {
                    Text(status).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                if let failure = recorder.failure {
                    Text(failure).font(.system(size: 11)).foregroundColor(Color(hex: "#F4505E"))
                }
                HStack(spacing: 14) {
                    if hub.isOn(.keepAwake) {
                        Toggle(isOn: $awake.whileAgents) {
                            Text(String(localized: "tools.awake.agents", defaultValue: "Keep the Mac awake while an agent works"))
                                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                        }
                        .toggleStyle(.switch).controlSize(.mini)
                    }
                    if hub.isOn(.recorder) {
                        Toggle(isOn: Binding(get: { UserDefaults.standard.bool(forKey: ScreenRecorder.micKey) },
                                             set: { UserDefaults.standard.set($0, forKey: ScreenRecorder.micKey) })) {
                            Text(String(localized: "tools.record.mic", defaultValue: "Record my microphone too"))
                                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                        }
                        .toggleStyle(.switch).controlSize(.mini)
                    }
                }
            }
        }
    }
}

private struct ToolTile: View {
    let symbol: String
    let title: String
    var on = false
    var badge: String? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15))
                    .foregroundColor(on ? RafiqLook.gold : Color(hex: "#E1E3E6"))
                Text(title).font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Color(hex: "#B0B5BE")).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(on ? RafiqLook.gold.opacity(0.12) : Color.white.opacity(hovered ? 0.08 : 0.045))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? RafiqLook.gold.opacity(0.45) : Color.white.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(verbatim: badge).font(.system(size: 8.5, weight: .bold)).foregroundColor(.black)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RafiqLook.gold).clipShape(Capsule()).padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct CameraPanel: View {
    let back: () -> Void
    @ObservedObject private var camera = CameraPreview.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: back) {
                Label(String(localized: "tools.back", defaultValue: "Back"), systemImage: "chevron.left")
                    .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            if camera.denied {
                Text(String(localized: "tools.camera.denied", defaultValue: "Allow Rafiq in Privacy & Security → Camera."))
                    .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            } else {
                CameraView(session: camera.session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}

private struct MediaPanel: View {
    let back: () -> Void
    @State private var file: URL?
    @State private var busy = false
    @State private var result: String?
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: back) {
                Label(String(localized: "tools.back", defaultValue: "Back"), systemImage: "chevron.left")
                    .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            VStack(spacing: 6) {
                if let file {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().frame(width: 28, height: 28)
                        Text(verbatim: file.lastPathComponent).font(.system(size: 11.5)).foregroundColor(Color(hex: "#E1E3E6")).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        switch MediaTools.kind(of: file) {
                        case .video:
                            SmallButton(String(localized: "tools.media.compress", defaultValue: "Compress")) { run { await MediaTools.compress(file) } }
                            SmallButton("GIF") { run { await MediaTools.gif(file) } }
                        case .image:
                            SmallButton("JPEG") { run { MediaTools.convert(file, to: .jpeg) } }
                            SmallButton("PNG") { run { MediaTools.convert(file, to: .png) } }
                            SmallButton("HEIC") { run { MediaTools.convert(file, to: .heic) } }
                            SmallButton(String(localized: "tools.media.text", defaultValue: "Read the text")) {
                                if let text = MediaTools.text(in: file) {
                                    ClipboardHistory.shared.write(text)
                                    result = String(format: String(localized: "tools.text.copied %lld", defaultValue: "%lld lines copied."),
                                                    text.split(separator: "\n").count)
                                }
                            }
                        case .other:
                            Text(String(localized: "tools.media.unknown", defaultValue: "A video or an image, please."))
                                .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                        }
                    }
                    if busy { ProgressView().controlSize(.small) }
                } else {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 20)).foregroundColor(Color(hex: "#6B7079"))
                    Text(String(localized: "tools.media.drop", defaultValue: "Drop a video or an image"))
                        .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                if let result { Text(result).font(.system(size: 10.5)).foregroundColor(Color(hex: "#34D399")) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(targeted ? RafiqLook.gold : Color.white.opacity(0.12)))
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                    Task { @MainActor in file = url; result = nil }
                }
                return true
            }
        }
    }

    private func run(_ work: @escaping () async -> URL?) {
        busy = true
        result = nil
        Task {
            let out = await work()
            busy = false
            if let out {
                result = String(format: String(localized: "tools.media.done %@", defaultValue: "Saved: %@"), out.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } else {
                result = String(localized: "tools.media.failed", defaultValue: "That didn't work.")
            }
        }
    }
}

private struct QuitAppsList: View {
    let back: () -> Void
    @State private var apps: [NSRunningApplication] = QuickActions.openApps

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: back) {
                    Label(String(localized: "tools.back", defaultValue: "Back"), systemImage: "chevron.left")
                        .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain)
                Spacer()
                SmallButton(String(localized: "tools.quit.others", defaultValue: "All but the front one")) {
                    QuickActions.quitAll(except: true); reload()
                }
                SmallButton(String(localized: "tools.quit.all", defaultValue: "Quit all")) {
                    QuickActions.quitAll(except: false); reload()
                }
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(apps, id: \.processIdentifier) { app in
                        HStack(spacing: 8) {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                            Text(verbatim: app.localizedName ?? "?").font(.system(size: 11.5)).foregroundColor(Color(hex: "#E1E3E6"))
                            Spacer()
                            SmallButton(String(localized: "tools.quit.one", defaultValue: "Quit")) { app.terminate(); reload() }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func reload() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { apps = QuickActions.openApps }
    }
}

struct SmallButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: "#E1E3E6"))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.white.opacity(0.07)).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mac page

private struct MacPage: View {
    let active: Bool
    @ObservedObject private var mac = MacMonitor.shared
    @ObservedObject private var ports = PortWatch.shared
    @ObservedObject private var hub = FeatureHub.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Stat(title: "CPU", value: "\(Int(mac.cpu.rounded())) %")
                    Stat(title: String(localized: "tools.mac.temp", defaultValue: "Temp."),
                         value: mac.cpuTemperature.map { "\(Int($0.rounded()))°" } ?? "—")
                    Stat(title: String(localized: "tools.mac.battery", defaultValue: "Battery"),
                         value: mac.battery.map { "\($0.percent) %" } ?? "—")
                }
                Sparkline(values: mac.cpuHistory, color: Color(hex: "#5EA7F0"))
                    .frame(height: 26)
                Meter(title: String(localized: "tools.mac.memory", defaultValue: "Memory"),
                      share: mac.memoryTotal > 0 ? mac.memoryUsed / mac.memoryTotal : 0,
                      detail: "\(MacMonitor.bytes(mac.memoryUsed)) / \(MacMonitor.bytes(mac.memoryTotal))",
                      color: mac.memoryPressure >= 4 ? "#F4505E" : mac.memoryPressure >= 2 ? "#F59E0B" : "#34D399")
                Meter(title: String(localized: "tools.mac.disk", defaultValue: "Disk"),
                      share: mac.diskUsedShare,
                      detail: String(format: String(localized: "tools.mac.free %@", defaultValue: "%@ free"), MacMonitor.bytes(mac.diskFree)),
                      color: mac.diskUsedShare > 0.9 ? "#F59E0B" : "#5EA7F0")
                HStack {
                    Text(String(localized: "tools.mac.network", defaultValue: "Network")).foregroundColor(Color(hex: "#8E939C"))
                    Spacer()
                    Text(verbatim: "↓ \(MacMonitor.rate(mac.downRate))  ↑ \(MacMonitor.rate(mac.upRate))").foregroundColor(Color(hex: "#E1E3E6"))
                }
                .font(.system(size: 10.5))
                if let b = mac.battery, b.health != nil || b.cycles != nil {
                    Text(verbatim: [b.health.map { String(format: String(localized: "tools.mac.health %lld", defaultValue: "health %lld %%"), $0) },
                                    b.cycles.map { String(format: String(localized: "tools.mac.cycles %lld", defaultValue: "%lld cycles"), $0) }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "tools.mac.top", defaultValue: "Using the processor")).font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                ForEach(mac.top) { p in
                    HStack {
                        Text(verbatim: p.name).lineLimit(1).foregroundColor(Color(hex: "#E1E3E6"))
                        Spacer()
                        Text(verbatim: "\(Int(p.percent.rounded())) %").foregroundColor(Color(hex: "#8E939C"))
                    }
                    .font(.system(size: 10.5))
                }
                if hub.isOn(.ports) {
                    Text(String(localized: "tools.mac.ports", defaultValue: "Open ports")).font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                        .padding(.top, 4)
                    if ports.ports.isEmpty {
                        Text(String(localized: "tools.mac.ports.none", defaultValue: "Nothing listens.")).font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                    }
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(ports.ports) { port in
                                HStack(spacing: 6) {
                                    Text(verbatim: "\(port.port)").font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color(hex: "#E1E3E6"))
                                    Text(verbatim: port.process).lineLimit(1).font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                                    Spacer()
                                    SmallButton(String(localized: "tools.mac.stop", defaultValue: "Stop")) { ports.stop(port) }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { if active { start() } }
        .onChange(of: active) { _, now in now ? start() : MacMonitor.shared.stop() }
        .onDisappear { if active { MacMonitor.shared.stop() } }
    }

    private func start() {
        MacMonitor.shared.start()
        if hub.isOn(.ports) { PortWatch.shared.refresh() }
    }
}

private struct Stat: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
            Text(verbatim: value).font(.system(size: 14, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 5)
        .background(Color.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct Meter: View {
    let title: String
    let share: Double
    let detail: String
    let color: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).foregroundColor(Color(hex: "#8E939C"))
                Spacer()
                Text(verbatim: detail).foregroundColor(Color(hex: "#E1E3E6"))
            }
            .font(.system(size: 10.5))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color(hex: color)).frame(width: g.size.width * min(1, max(0, share)))
                }
            }
            .frame(height: 4)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { g in
            Path { path in
                guard values.count > 1 else { return }
                let step = g.size.width / CGFloat(max(values.count - 1, 1))
                for (i, v) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(i) * step, y: g.size.height * (1 - CGFloat(min(100, v) / 100)))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Usage page

private struct UsagePage: View {
    @ObservedObject var state: AppState
    let active: Bool
    @ObservedObject private var ledger = TokenLedger.shared

    private var usage: PlanUsage? { state.demoPlanUsageOverride ?? state.claudePlanUsage }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        Ring(share: usage?.fiveHour.map { ClaudePlanGauge.effectivePct($0) / 100 } ?? 0, color: Color(hex: "#E49378"), width: 6)
                            .frame(width: 70, height: 70)
                        Ring(share: usage?.sevenDay.map { ClaudePlanGauge.effectivePct($0) / 100 } ?? 0, color: RafiqLook.gold, width: 6)
                            .frame(width: 50, height: 50)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        WindowLine(title: String(localized: "tools.usage.session", defaultValue: "Session"), window: usage?.fiveHour, color: "#E49378")
                        WindowLine(title: String(localized: "tools.usage.week", defaultValue: "Week"), window: usage?.sevenDay, color: "#E8B64A")
                    }
                }
                if usage == nil {
                    Text(String(localized: "tools.usage.none", defaultValue: "Claude Code didn't answer yet: is it installed and signed in?"))
                        .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                }
                HStack(spacing: 6) {
                    Figure(title: String(localized: "tools.usage.today", defaultValue: "Today"),
                           value: TokenLedger.compact(ledger.today.tokens), detail: TokenLedger.dollars(ledger.today.cost))
                    Figure(title: String(localized: "tools.usage.7days", defaultValue: "7 days"),
                           value: TokenLedger.compact(ledger.week.tokens), detail: TokenLedger.dollars(ledger.week.cost))
                }
                Text(String(localized: "tools.usage.value", defaultValue: "Tokens written, and what they would cost at API prices."))
                    .font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                DayBars(days: ledger.days).frame(height: 54)
                ForEach(ledger.projects, id: \.name) { p in
                    HStack {
                        Text(verbatim: p.name).lineLimit(1).foregroundColor(Color(hex: "#E1E3E6"))
                        Spacer()
                        Text(verbatim: "\(Int((p.share * 100).rounded())) %").foregroundColor(Color(hex: "#8E939C"))
                    }
                    .font(.system(size: 10.5))
                }
                if !ledger.models.isEmpty {
                    Text(verbatim: ledger.models.map { "\($0.name) \(Int(($0.share * 100).rounded())) %" }.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if active { refresh() } }
        .onChange(of: active) { _, now in if now { refresh() } }
    }

    private func refresh() {
        ledger.refresh()
        state.refreshClaudeAccountUsage()
    }
}

struct Ring: View {
    let share: Double
    let color: Color
    var width: CGFloat = 4
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: width)
            Circle().trim(from: 0, to: min(1, max(0, share)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct WindowLine: View {
    let title: String
    let window: PlanWindow?
    let color: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: color)).frame(width: 6, height: 6)
                Text(title).font(.system(size: 11)).foregroundColor(Color(hex: "#E1E3E6"))
                Text(verbatim: window.map { "\(Int(ClaudePlanGauge.effectivePct($0).rounded())) %" } ?? "—")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            }
            if let w = window, w.resetsAt > Date() {
                Text(String(format: String(localized: "tools.usage.resets %@", defaultValue: "resets in %@"),
                            TokenLedger.span(w.resetsAt.timeIntervalSinceNow)))
                    .font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
            }
        }
    }
}

private struct Figure: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
            Text(verbatim: value).font(.system(size: 14, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            Text(verbatim: detail).font(.system(size: 10)).foregroundColor(RafiqLook.gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct DayBars: View {
    let days: [(day: Date, cost: Double)]
    var body: some View {
        let top = max(days.map(\.cost).max() ?? 0, 0.01)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, d in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#E49378").opacity(index == days.count - 1 ? 1 : 0.5))
                        .frame(height: max(2, 38 * d.cost / top))
                    Text(verbatim: String(d.day.formatted(.dateTime.weekday(.narrow))))
                        .font(.system(size: 8.5)).foregroundColor(Color(hex: "#6B7079"))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
#endif
