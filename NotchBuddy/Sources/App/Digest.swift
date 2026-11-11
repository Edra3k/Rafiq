import AppKit
import SwiftUI

// MARK: - Digest: one card for what Rafiq kept or noticed for you
// The same card shows four things, one at a time (the `.digest` island view):
// - what happened during a prayer (PrayerQuiet held the alerts back),
// - the evening brief of the day (EveningBrief),
// - known vulnerabilities in a project's dependencies (OSVWatch, opt-in),
// - a secret written into a file by an agent (SecretScanner, from the live diff).
// A card stays up until the user dismisses it (it holds the island open like an approval)
// and the next one waits behind it. Nothing here answers an agent: buttons only open,
// copy or dismiss.

struct Digest: Identifiable, Equatable {
    enum Kind: Equatable { case prayer, evening, cve, secret, verse, injection, canary, away, care, server }

    struct Tile: Equatable {
        var value: String
        var label: String
        var tone: Tone = .plain
    }

    enum Tone: Equatable {
        case plain, good, warn, bad, gold

        var color: Color {
            switch self {
            case .plain: return Color(hex: "#F5F6F8")
            case .good:  return Color(hex: "#34D399")
            case .warn:  return Color(hex: "#F07A3A")
            case .bad:   return Color(hex: "#F4505E")
            case .gold:  return RafiqLook.gold
            }
        }
    }

    enum Action: Equatable {
        /// Focus a pill (the session that asked, the Prayer card…).
        case focus(String)
        /// Put text on the clipboard (a prompt for Claude, a reminder).
        case copy(String)
        /// Open a file in its app.
        case openFile(String)
        /// Open a web page (an advisory).
        case openURL(URL)
        /// The tasbih after a prayer.
        case tasbih
        /// "It's me": an SSH login from this address is the user's (the server watch).
        case trustIP(String)
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var subtitle: String
    var tiles: [Tile] = []
    var lines: [String] = []
    /// A monospaced line (the masked secret, the package and its fix).
    var code: String? = nil
    var primary: (label: String, action: Action)? = nil

    static func == (a: Digest, b: Digest) -> Bool { a.id == b.id }

    var titleColor: Color {
        switch kind {
        case .prayer, .verse:  return RafiqLook.gold
        case .evening, .away, .care: return Color(hex: "#F5F6F8")
        case .cve, .secret, .injection, .canary, .server: return Color(hex: "#F7C1C1")
        }
    }
}

@MainActor
final class DigestCenter: ObservableObject {
    static let shared = DigestCenter()

    @Published private(set) var current: Digest?
    private var waiting: [Digest] = []

    /// A card up holds the island open like an approval, except the verse of the day.
    var holdsIsland: Bool { current != nil && current?.kind != .verse && current?.kind != .care }

    /// Security cards shown today (secret, CVE, injection, trap), for the Today page.
    func securityAlerts(on date: Date) -> Int {
        UserDefaults.standard.integer(forKey: Self.securityKey(date))
    }

    private static func securityKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "securityAlerts-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// Shows the card now if none is up, else after the ones before it.
    func show(_ digest: Digest) {
        if [.secret, .cve, .injection, .canary, .server].contains(digest.kind) {
            let key = Self.securityKey(Date())
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
            objectWillChange.send()
        }
        if current == nil {
            current = digest
            surface()
        } else {
            waiting.append(digest)
        }
    }

    func dismiss() {
        if waiting.isEmpty {
            current = nil
            let state = AppState.shared
            if state.mode == .expanded && state.view == .digest {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .overview }
            }
        } else {
            current = waiting.removeFirst()
            surface()
        }
    }

    func perform(_ action: Digest.Action) {
        switch action {
        case .focus(let pill):
            let state = AppState.shared
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.focusId = pill
                state.view = .overview
            }
            dismissKeepingView()
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            SoundEngine.shared.play("pop")
            dismiss()
        case .openFile(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            dismiss()
        case .openURL(let url):
            NSWorkspace.shared.open(url)
            dismiss()
        case .tasbih:
            dismissKeepingView()
            TasbihCounter.shared.open()
        case .trustIP(let ip):
            #if !APPSTORE
            ServerLink.shared.trust(ip)
            #endif
            _ = ip
            dismiss()
        }
    }

    /// Dismiss without sending the island back home (the action already chose a view).
    private func dismissKeepingView() {
        if waiting.isEmpty { current = nil } else { current = waiting.removeFirst(); surface() }
    }

    /// Opens the island on the card, unless a card the user is in the middle of is up:
    /// then the card waits until that one is answered (`resumeIfWaiting`).
    private func surface() {
        let state = AppState.shared
        if state.pendingApproval != nil || state.pendingQuestion != nil { return }
        if PrayerQuiet.shared.isActive { return }
        if state.mode != .expanded {
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.digest)
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .digest }
        }
    }

    /// An approval or a question was answered, or a prayer ended: the card can come up.
    func resumeIfWaiting() {
        guard current != nil else { return }
        let state = AppState.shared
        if state.mode == .expanded && state.view == .digest { return }
        surface()
    }
}

// MARK: - Card

struct DigestCardView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var center = DigestCenter.shared

    var body: some View {
        content
            // The verse of the day goes away with the island (it never holds it open).
            .onChange(of: state.mode) { _, mode in
                if mode != .expanded, center.current?.kind == .verse || center.current?.kind == .care { center.dismiss() }
            }
            // Covered by another card (finished, error) that then went home: come back.
            .onChange(of: state.view) { _, view in
                if view == .overview, state.mode == .expanded, center.holdsIsland {
                    DispatchQueue.main.async { center.resumeIfWaiting() }
                }
            }
    }

    @ViewBuilder private var content: some View {
        ZStack {
            CardBackground(wash: wash)
            if let d = center.current {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(verbatim: d.title)
                            .font(.system(size: d.kind == .verse ? 19 : 13, weight: .semibold))
                            .foregroundColor(d.titleColor)
                            .lineLimit(d.kind == .verse ? 2 : 1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Button(action: { center.dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color(hex: "#6B7079"))
                                .frame(width: 18, height: 18)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    if !d.subtitle.isEmpty {
                        Text(verbatim: d.subtitle)
                            .font(.system(size: d.kind == .verse ? 12.5 : 11))
                            .foregroundColor(Color(hex: d.kind == .verse ? "#C0C4CC" : "#8E939C"))
                            .lineLimit(d.kind == .verse ? 2 : 1)
                    }
                    if !d.tiles.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(d.tiles.enumerated()), id: \.offset) { _, tile in
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(verbatim: tile.value)
                                        .font(.system(size: 15, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundColor(tile.tone.color)
                                    Text(verbatim: tile.label)
                                        .font(.system(size: 9.5))
                                        .foregroundColor(Color(hex: "#8E939C"))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
                            }
                        }
                    }
                    if let code = d.code {
                        Text(verbatim: code)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "#E8E9EC"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                    }
                    ForEach(Array(d.lines.prefix(d.tiles.isEmpty ? 3 : 1).enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .font(.system(size: 10.5))
                            .foregroundColor(Color(hex: "#9398A1"))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        if let primary = d.primary {
                            PrimaryButton(verbatim: primary.label) { center.perform(primary.action) }
                        }
                        SecondaryButton(verbatim: String(localized: "digest.got-it", defaultValue: "Got it")) {
                            center.dismiss()
                        }
                    }
                }
                .padding(.leading, 116)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var wash: CardBackground<EmptyView>.Wash? {
        switch center.current?.kind {
        case .prayer?, .verse?:  return .amber
        case .cve?, .secret?, .injection?, .canary?, .server?: return .red
        default: return .soft
        }
    }
}

// MARK: - Secret written by an agent

@MainActor
enum SecretAlert {
    /// The same file and value warned about once per run: an agent editing the file again
    /// should not bring the card back each time.
    private static var warned = Set<String>()

    static func show(_ hits: [SecretHit], path: String, pill: String) {
        let fresh = hits.filter { warned.insert(path + "|" + $0.masked).inserted }
        guard let first = fresh.first else { return }
        let file = path.isEmpty ? "" : URL(fileURLWithPath: path).lastPathComponent
        let kind = label(first.kind)
        let prompt = String(format: String(localized: "secret.prompt %@ %lld", defaultValue: "You just wrote a secret into %@ (line %lld). Move it to an environment variable or the Keychain, read it from there, and make sure it is not committed."),
                            file.isEmpty ? "a file" : file, first.line)
        SoundEngine.shared.play("approval")
        DigestCenter.shared.show(Digest(
            kind: .secret,
            title: String(format: String(localized: "secret.title %@", defaultValue: "Secret spotted · %@"), kind),
            subtitle: file.isEmpty ? String(localized: "secret.subtitle", defaultValue: "In what an agent is writing")
                : String(format: String(localized: "secret.in-file %@ %lld", defaultValue: "In %@, line %lld"), file, first.line),
            lines: [String(localized: "secret.advice", defaultValue: "Better in an environment variable or the Keychain, never in git.")],
            code: first.masked,
            primary: (String(localized: "secret.copy", defaultValue: "Copy a prompt for Claude"), .copy(prompt))
        ))
        _ = pill
    }

    static func label(_ kind: SecretHit.Kind) -> String {
        switch kind {
        case .awsKey: return "AWS"
        case .githubToken: return "GitHub"
        case .slackToken: return "Slack"
        case .stripeKey: return "Stripe"
        case .googleKey: return "Google"
        case .openAIKey: return "OpenAI"
        case .anthropicKey: return "Anthropic"
        case .privateKey: return String(localized: "secret.kind.private-key", defaultValue: "private key")
        case .jwt: return "JWT"
        case .assignedSecret: return String(localized: "secret.kind.password", defaultValue: "password or key")
        }
    }
}
