import SwiftUI
import WatchKit

// MARK: - The Watch: Rafiq on the wrist
// Home: the next prayer, the agents at work, the latest tasks. A request waiting comes first
// (Allow takes a second tap; Deny goes at once). "Ask" dictates a task for Hermes or Claude.

struct WatchHomeView: View {
    let store: WatchStore

    var body: some View {
        NavigationStack {
            List {
                if let waiting = store.waiting {
                    NavigationLink {
                        WatchApprovalView(store: store, session: waiting)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label {
                                Text(verbatim: waiting.name).font(.headline)
                            } icon: {
                                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                            }
                            Text(verbatim: waiting.command)
                                .font(.system(.footnote, design: .monospaced))
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listItemTint(.orange)
                }

                Section {
                    NavigationLink {
                        WatchAskView(store: store)
                    } label: {
                        Label("Ask", systemImage: "mic.fill")
                            .foregroundStyle(Color(hex: "#E8B64A"))
                    }
                }

                if !store.sessions.isEmpty {
                    Section("Agents") {
                        ForEach(store.sessions.prefix(5)) { s in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Circle().fill(Color(hex: s.color)).frame(width: 6, height: 6)
                                    Text(verbatim: s.name).font(.footnote.weight(.semibold))
                                }
                                Text(verbatim: s.step.isEmpty ? s.title : s.step)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if !store.asks.isEmpty {
                    Section("Tasks") {
                        ForEach(store.asks) { ask in
                            NavigationLink {
                                WatchAskResultView(result: ask)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 5) {
                                        Circle().fill(Color(hex: ask.colorHex)).frame(width: 6, height: 6)
                                        Text(verbatim: ask.agentName).font(.footnote.weight(.semibold))
                                        if ask.state == .running { ProgressView().scaleEffect(0.5).frame(width: 12, height: 12) }
                                    }
                                    Text(verbatim: ask.state == .done && !ask.answer.isEmpty ? ask.answer : ask.text)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }

                if store.sessions.isEmpty && store.asks.isEmpty && store.waiting == nil {
                    Text("Nothing running. Ask Hermes or Claude from here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle {
                HStack(spacing: 6) {
                    WatchDome().frame(width: 18, height: 18)
                    Text(verbatim: "Rafiq")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let name = store.prayerName, let at = store.prayerAt {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(verbatim: name).font(.system(size: 11, weight: .semibold))
                            Text(at, style: .time).font(.system(size: 10))
                        }
                        .foregroundStyle(Color(hex: "#E8B64A"))
                    }
                }
            }
        }
    }
}

// MARK: - A request waiting

struct WatchApprovalView: View {
    let store: WatchStore
    let session: WatchSession
    @State private var confirming = false
    @State private var result: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: session.color)).frame(width: 7, height: 7)
                    Text(verbatim: session.name).font(.headline)
                }
                Text(verbatim: session.command)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                let risk = CommandRisk.assess(tool: "Bash", command: session.command)
                Label(risk.reason.label, systemImage: risk.level.symbol)
                    .font(.caption2)
                    .foregroundStyle(Color(hex: risk.level.hex))
                if let result {
                    Text(verbatim: result).font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    if confirming { answer("allow") } else { confirming = true; WKInterfaceDevice.current().play(.click) }
                } label: {
                    Text(confirming ? "Tap again to allow" : "Allow")
                        .frame(maxWidth: .infinity)
                }
                .tint(confirming ? .green : .white)
                Button(role: .destructive) { answer("deny") } label: {
                    Text("Deny").frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Permission")
    }

    private func answer(_ decision: String) {
        Task {
            switch await store.decide(decision, for: session) {
            case .sent:
                WKInterfaceDevice.current().play(decision == "allow" ? .success : .stop)
                dismiss()
            case .failed:
                result = String(localized: "Couldn't send. Try from your iPhone.")
                WKInterfaceDevice.current().play(.failure)
            case .noPhone:
                result = String(localized: "Your iPhone isn't reachable.")
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }
}

// MARK: - Ask by voice

struct WatchAskView: View {
    let store: WatchStore
    @State private var text = ""
    @State private var target: AskTarget = .auto
    @State private var status: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                TextField("Say the task", text: $text)
                    .submitLabel(.send)
                    .onSubmit(send)
                Picker("Who", selection: $target) {
                    Text("Auto").tag(AskTarget.auto)
                    Text(verbatim: "Hermes").tag(AskTarget.hermes)
                    Text(verbatim: "Claude").tag(AskTarget.claude)
                }
                .pickerStyle(.navigationLink)
                Button(action: send) {
                    Label("Send", systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity)
                }
                .tint(Color(hex: "#E8B64A"))
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                if let status {
                    Text(verbatim: status).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Ask")
    }

    private func send() {
        let task = text
        guard !task.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            switch await store.ask(task, target: target) {
            case .sent:
                WKInterfaceDevice.current().play(.success)
                dismiss()
            case .failed:
                status = String(localized: "Couldn't send. Is the iPhone link on in Rafiq on your Mac?")
            case .noPhone:
                status = String(localized: "Your iPhone isn't reachable.")
            }
        }
    }
}

struct WatchAskResultView: View {
    let result: AskResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: result.text).font(.footnote).foregroundStyle(.secondary)
                if result.state == .running {
                    HStack { ProgressView(); Text(result.steps.last ?? "…").font(.caption2) }
                } else {
                    Text(verbatim: result.answer.isEmpty ? "—" : result.answer).font(.body)
                }
            }
        }
        .navigationTitle(result.agentName)
    }
}

// MARK: - Rafiq, small

/// The dome with its golden crescent (RafiqLook's silhouette, drawn flat for the Watch).
struct WatchDome: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var dome = Path()
            dome.move(to: CGPoint(x: w * 0.08, y: h * 0.92))
            dome.addLine(to: CGPoint(x: w * 0.92, y: h * 0.92))
            dome.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.22),
                          control1: CGPoint(x: w * 0.96, y: h * 0.5), control2: CGPoint(x: w * 0.74, y: h * 0.26))
            dome.addCurve(to: CGPoint(x: w * 0.08, y: h * 0.92),
                          control1: CGPoint(x: w * 0.26, y: h * 0.26), control2: CGPoint(x: w * 0.04, y: h * 0.5))
            context.fill(dome, with: .color(.white))
            let r = w * 0.13
            let moon = Path(ellipseIn: CGRect(x: w * 0.5 - r, y: h * 0.02, width: r * 2, height: r * 2))
            let bite = Path(ellipseIn: CGRect(x: w * 0.5 - r * 0.45, y: h * 0.02 - r * 0.25, width: r * 2, height: r * 2))
            context.fill(moon.subtracting(bite), with: .color(Color(hex: "#E8B64A")))
            for x in [0.38, 0.62] {
                context.fill(Path(ellipseIn: CGRect(x: w * x - w * 0.05, y: h * 0.58, width: w * 0.1, height: h * 0.12)),
                             with: .color(.black))
            }
        }
    }
}
