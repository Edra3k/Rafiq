#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - Command bar (⌥Space): apps, files, clipboard, snippets, Rafiq's tools, a calculator,
// and Jarvis for anything else. Radial menu (⌃⌥R): six actions around the pointer.

struct CommandResult: Identifiable {
    enum Kind { case app, file, clip, snippet, tool, math, ask }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let icon: NSImage?
    let symbol: String
    let run: @MainActor () -> Void
}

@MainActor
final class CommandBar: ObservableObject {
    static let shared = CommandBar()
    @Published var query = "" { didSet { search() } }
    @Published private(set) var results: [CommandResult] = []
    @Published var selection = 0
    @Published private(set) var answer: String?
    @Published private(set) var thinking = false
    private var panel: NSPanel?
    private var fileSearch: Task<Void, Never>?

    func toggle() {
        if panel?.isVisible == true { hide(); return }
        query = ""
        answer = nil
        results = []
        if panel == nil {
            let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420), styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .modalPanel
            p.contentView = NSHostingView(rootView: CommandBarView())
            panel = p
        }
        if let screen = NSScreen.main {
            panel?.setFrameOrigin(NSPoint(x: screen.frame.midX - 310, y: screen.frame.maxY - screen.frame.height * 0.28 - 420))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }

    func runSelected() {
        guard results.indices.contains(selection) else { return }
        results[selection].run()
    }

    private func search() {
        answer = nil
        selection = 0
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        var list: [CommandResult] = []
        let lower = q.lowercased()

        // A calculation.
        if q.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/×÷^")) != nil,
           q.allSatisfy({ "0123456789.,+-*/×÷() ^".contains($0) }) {
            let expression = q.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: ",", with: ".")
            if let value = NSExpression(format: expression).expressionValue(with: nil, context: nil) as? NSNumber {
                let text = value.stringValue
                list.append(CommandResult(kind: .math, title: "= \(text)", detail: String(localized: "command.copy", defaultValue: "Copy"),
                                          icon: nil, symbol: "equal.circle") { ClipboardHistory.shared.write(text); CommandBar.shared.hide() })
            }
        }
        // Apps.
        let apps = AppsManager.shared
        if apps.apps.isEmpty { apps.refreshApps() }
        let systemApps = ((try? FileManager.default.contentsOfDirectory(atPath: "/System/Applications")) ?? [])
            .filter { $0.hasSuffix(".app") }.map { URL(fileURLWithPath: "/System/Applications").appendingPathComponent($0) }
        for app in (apps.apps + systemApps) where app.deletingPathExtension().lastPathComponent.lowercased().contains(lower) {
            list.append(CommandResult(kind: .app, title: app.deletingPathExtension().lastPathComponent, detail: String(localized: "command.app", defaultValue: "App"),
                                      icon: NSWorkspace.shared.icon(forFile: app.path), symbol: "app") {
                NSWorkspace.shared.open(app); CommandBar.shared.hide()
            })
            if list.count > 6 { break }
        }
        // Rafiq's tools.
        for feature in FeatureHub.shared.enabled.sorted(by: { $0.rawValue < $1.rawValue }) where feature.title.lowercased().contains(lower) {
            list.append(CommandResult(kind: .tool, title: feature.title, detail: "Rafiq", icon: nil, symbol: feature.symbol) {
                CommandBar.shared.hide()
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.tools)
            })
        }
        // Snippets and the clipboard.
        for snippet in FlowStore.shared.snippets where snippet.trigger.lowercased().contains(lower) || snippet.text.lowercased().contains(lower) {
            list.append(CommandResult(kind: .snippet, title: snippet.trigger, detail: String(snippet.text.prefix(60)), icon: nil, symbol: "text.badge.plus") {
                CommandBar.shared.hide(); _ = FlowPaste.insert(InputTools.expand(snippet.text))
            })
        }
        for item in ClipboardHistory.shared.items.prefix(80) where item.kind != .secret && item.text.lowercased().contains(lower) {
            list.append(CommandResult(kind: .clip, title: String(item.text.prefix(70)), detail: String(localized: "tools.page.clip", defaultValue: "Clipboard"),
                                      icon: nil, symbol: "doc.on.clipboard") {
                CommandBar.shared.hide(); ClipboardHistory.shared.use(item, paste: true)
            })
            if list.filter({ $0.kind == .clip }).count >= 4 { break }
        }
        // Jarvis, always last.
        list.append(CommandResult(kind: .ask, title: q, detail: String(localized: "command.ask", defaultValue: "Ask Rafiq"), icon: nil, symbol: "sparkles") {
            CommandBar.shared.ask(q)
        })
        results = list
        searchFiles(q)
    }

    private func searchFiles(_ q: String) {
        fileSearch?.cancel()
        guard q.count >= 3 else { return }
        fileSearch = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let out = await Task.detached { JarvisMac.run("/usr/bin/mdfind", ["-onlyin", NSHomeDirectory(), "-name", q], timeout: 3) ?? "" }.value
            guard !Task.isCancelled, query.trimmingCharacters(in: .whitespaces) == q else { return }
            let paths = out.split(separator: "\n").map(String.init)
                .filter { !$0.contains("/Library/") && !$0.contains("/.") && !$0.contains("/node_modules/") }.prefix(5)
            let files = paths.map { path in
                CommandResult(kind: .file, title: (path as NSString).lastPathComponent,
                              detail: ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath,
                              icon: NSWorkspace.shared.icon(forFile: path), symbol: "doc") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path)); CommandBar.shared.hide()
                }
            }
            if let ask = results.last, ask.kind == .ask { results = results.dropLast() + files + [ask] } else { results += files }
        }
    }

    func ask(_ q: String) {
        thinking = true
        answer = nil
        Task {
            let reply = await JarvisAsk.answer(q)
            thinking = false
            answer = reply
        }
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct CommandBarView: View {
    @ObservedObject private var bar = CommandBar.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 17)).foregroundColor(RafiqLook.gold)
                TextField(String(localized: "command.placeholder", defaultValue: "Search or ask Rafiq"), text: $bar.query)
                    .textFieldStyle(.plain).font(.system(size: 18)).foregroundColor(.white)
                    .focused($focused)
                    .onSubmit { bar.runSelected() }
                    .onKeyPress(.escape) { bar.hide(); return .handled }
                    .onKeyPress(.downArrow) { bar.selection = min(bar.selection + 1, max(0, bar.results.count - 1)); return .handled }
                    .onKeyPress(.upArrow) { bar.selection = max(bar.selection - 1, 0); return .handled }
                if bar.thinking { ProgressView().controlSize(.small) }
            }
            .padding(12).background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
            if let answer = bar.answer {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").foregroundColor(RafiqLook.gold)
                    Text(verbatim: answer).font(.system(size: 13)).foregroundColor(.white).textSelection(.enabled)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RafiqLook.gold.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(bar.results.enumerated()), id: \.element.id) { index, r in
                        HStack(spacing: 10) {
                            if let icon = r.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                            else { Image(systemName: r.symbol).font(.system(size: 13)).foregroundColor(Color(hex: "#B0B5BE")).frame(width: 22) }
                            Text(verbatim: r.title).font(.system(size: 13)).foregroundColor(.white).lineLimit(1)
                            Spacer()
                            Text(verbatim: r.detail).font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079")).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(index == bar.selection ? RafiqLook.gold.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture { bar.selection = index; bar.runSelected() }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 620, height: 420, alignment: .top)
        .background(Color.black.opacity(0.93))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear { focused = true }
    }
}

// MARK: - Radial menu

@MainActor
final class RadialMenu {
    static let shared = RadialMenu()
    private var panel: NSPanel?

    struct Item { let symbol: String; let title: String; let run: @MainActor () -> Void }

    var items: [Item] {
        [
            Item(symbol: "sparkle.magnifyingglass", title: String(localized: "command.title", defaultValue: "Command bar")) { CommandBar.shared.toggle() },
            Item(symbol: "rectangle.dashed", title: String(localized: "tools.capture.area", defaultValue: "Area")) { ScreenCapture.shared.begin() },
            Item(symbol: "doc.on.clipboard", title: String(localized: "tools.page.clip", defaultValue: "Clipboard")) {
                UserDefaults.standard.set("clip", forKey: "tools.page")
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.tools)
            },
            Item(symbol: "record.circle", title: String(localized: "tools.record", defaultValue: "Record")) { ScreenRecorder.shared.toggle() },
            Item(symbol: "eyedropper", title: String(localized: "tools.color", defaultValue: "Color")) { QuickActions.pickColor { _ in } },
            Item(symbol: "lock", title: String(localized: "tools.lock", defaultValue: "Lock")) { QuickActions.lockScreen() },
        ]
    }

    func show() {
        if panel?.isVisible == true { hide(); return }
        let size: CGFloat = 260
        if panel == nil {
            let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size), styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .popUpMenu
            panel = p
        }
        panel?.contentView = NSHostingView(rootView: RadialView(items: items, size: size))
        let mouse = NSEvent.mouseLocation
        panel?.setFrameOrigin(NSPoint(x: mouse.x - size / 2, y: mouse.y - size / 2))
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }
}

private struct RadialView: View {
    let items: [RadialMenu.Item]
    let size: CGFloat
    @State private var hovered: Int?

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.9)).frame(width: size, height: size)
            Circle().fill(Color(hex: "#141416")).frame(width: 74, height: 74)
            VStack(spacing: 0) {
                Image(systemName: "moon.fill").font(.system(size: 10)).foregroundColor(RafiqLook.gold)
                Text(verbatim: hovered.map { items[$0].title } ?? "Rafiq").font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                    .lineLimit(1).frame(width: 66)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let angle = Double(index) / Double(items.count) * 2 * .pi - .pi / 2
                Button {
                    RadialMenu.shared.hide()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { item.run() }
                } label: {
                    Image(systemName: item.symbol).font(.system(size: 18))
                        .foregroundColor(hovered == index ? .black : .white)
                        .frame(width: 46, height: 46)
                        .background(hovered == index ? RafiqLook.gold : Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? index : nil }
                .offset(x: cos(angle) * 88, y: sin(angle) * 88)
            }
        }
        .frame(width: size, height: size)
        .onExitCommand { RadialMenu.shared.hide() }
    }
}
#endif
