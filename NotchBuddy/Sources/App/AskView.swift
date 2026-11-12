#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - The "Ask…" card (the `.ask` island view)
// Rafiq on the left. With no task shown: who to ask (Auto, Hermes, Claude, Just answer),
// the task (typed or dictated) and where Auto would send it. With a task: Hermes or Claude
// at work (its last steps), then the answer, to read aloud, copy, follow up or hand to
// Claude. The approvals come on their own card, as for any session.

struct AskView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var runner = AskRunner.shared
    @ObservedObject private var launcher = SessionLauncher.shared
    @State private var text = ""
    @State private var chosen: AskTarget = .auto
    @State private var message: String?
    @State private var dictation = MacDictation()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: .indigo)
            Group {
                if let job = runner.shownJob {
                    JobCard(job: job, runner: runner, onNew: newTask)
                } else {
                    composer
                }
            }
            .padding(.leading, 110)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: state.view) { _, view in
            if view == .ask && runner.shownJob == nil { focused = true; message = nil }
        }
    }

    private func newTask() {
        runner.shown = nil
        message = nil
        focused = true
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("ask.title")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#8E939C"))
                chip(.auto, icon: "sparkles", label: String(localized: "ask.auto", defaultValue: "Auto"))
                chip(.hermes, dot: "#C084FC", label: "Hermes")
                chip(.claude, dot: "#D97757", label: "Claude")
                chip(.answer, icon: "bubble.left", label: String(localized: "ask.just-answer", defaultValue: "Just answer"))
                Spacer(minLength: 0)
                if let busy = runner.running.first {
                    Button { runner.shown = busy.id } label: {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text(verbatim: "\(runner.running.count)")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#C9CDD4"))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "ask.running", defaultValue: "Tasks running"))
                }
            }
            HStack(spacing: 8) {
                TextField(String(localized: "ask.placeholder", defaultValue: "Check the server's disk space"), text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...3)
                    .focused($focused)
                    .writingToolsBehavior(.disabled)
                    .onSubmit(send)
                Button {
                    Task {
                        if dictation.isRecording { text = await dictation.finish() }
                        else { await dictation.start(from: text) }
                    }
                } label: {
                    Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(dictation.isRecording ? Color(hex: "#F4505E") : RafiqLook.gold)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(dictation.isRecording ? String(localized: "Stop dictation") : String(localized: "Dictate (right-click to choose the language)"))
                .contextMenu { DictationLanguageMenu(dictation: dictation) }
                .onChange(of: dictation.transcript) { _, _ in
                    if dictation.isRecording { text = dictation.text }
                }
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#0B0C0E"))
                }
                .buttonStyle(SendButtonStyle())
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .simultaneousGesture(TapGesture().onEnded { focused = true })
            HStack(spacing: 6) {
                Image(systemName: message == nil ? "arrow.triangle.branch" : "exclamationmark.circle")
                    .font(.system(size: 10))
                Text(verbatim: message ?? routeHint)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if route.target == .claude && AskRouter.project(in: route.text, among: launcher.projects) == nil {
                    projectMenu
                }
            }
            .foregroundColor(message == nil ? Color(hex: "#8E939C") : Color(hex: "#F4505E"))
            Text("ask.safety")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#6B7079"))
                .lineLimit(1)
        }
    }

    private var route: AskRoute {
        AskRouter.route(text, chosen: chosen, hasHermes: runner.hasHermes)
    }

    /// "Auto will pick Hermes · on pve".
    private var routeHint: String {
        let r = route
        guard !r.text.isEmpty else {
            return runner.hasHermes ? String(localized: "ask.hint.empty", defaultValue: "Hermes for the server and the home, Claude for code, the chat for a question")
                : String(localized: "ask.hint.no-hermes", defaultValue: "Claude for code, the chat for a question (Hermes isn't installed)")
        }
        let who: String
        switch r.target {
        case .hermes:
            let place = runner.hermesPlace(for: r.text) ?? "Mac"
            who = String(format: String(localized: "ask.hint.hermes %@", defaultValue: "Hermes · on %@"), place)
        case .claude:
            let folder = AskRouter.project(in: r.text, among: launcher.projects) ?? launcher.folder
            who = String(format: String(localized: "ask.hint.claude %@", defaultValue: "Claude Code · in %@"),
                         folder.map(SessionLauncher.name(of:)) ?? "—")
        case .answer, .auto:
            who = String(localized: "ask.hint.chat", defaultValue: "the chat answers")
        }
        return r.explicit ? who : String(format: String(localized: "ask.hint.auto %@", defaultValue: "Auto picks %@"), who)
    }

    private func chip(_ target: AskTarget, icon: String? = nil, dot: String? = nil, label: String) -> some View {
        let on = chosen == target
        return Button { chosen = target } label: {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 9, weight: .semibold)) }
                if let dot { Circle().fill(Color(hex: dot)).frame(width: 6, height: 6) }
                Text(verbatim: label).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .foregroundColor(on ? Color(hex: "#0B0C0E") : Color(hex: "#C9CDD4"))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(on ? Color(hex: "#F5F6F8") : Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var projectMenu: some View {
        Menu {
            ForEach(launcher.projects, id: \.self) { path in
                Button {
                    launcher.choose(path)
                } label: {
                    if path == launcher.folder { Label(SessionLauncher.name(of: path), systemImage: "checkmark") }
                    else { Text(verbatim: SessionLauncher.name(of: path)) }
                }
            }
            if !launcher.projects.isEmpty { Divider() }
            Button(String(localized: "launch.choose-folder")) { launcher.chooseFolder() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder").font(.system(size: 9))
                Text(verbatim: launcher.folder.map(SessionLauncher.name(of:)) ?? String(localized: "launch.no-project"))
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(Color(hex: "#C9CDD4"))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func send() {
        if dictation.isRecording { Task { text = await dictation.finish(); go() } } else { go() }
    }

    private func go() {
        let outcome = runner.ask(text, chosen: chosen, project: launcher.folder, source: "notch")
        switch outcome {
        case .started:
            text = ""
            message = nil
            SoundEngine.shared.play("send")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        case .chat:
            text = ""
        case .needsProject:
            message = String(localized: "ask.needs-project", defaultValue: "Pick a project for Claude")
            if launcher.folder == nil { launcher.chooseFolder() }
        case .noHermes:
            message = String(localized: "ask.no-hermes", defaultValue: "Hermes isn't installed here, nor on the server")
        case .busy:
            message = String(localized: "ask.busy", defaultValue: "Three tasks are already running")
        case .empty:
            message = nil
        }
        if case .started = outcome {} else if outcome != .chat { SoundEngine.shared.play("error") }
    }
}

// MARK: - A task: at work, then its answer

private struct JobCard: View {
    let job: AskRunner.Job
    @ObservedObject var runner: AskRunner
    let onNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: job.target == .hermes ? "#C084FC" : "#D97757")).frame(width: 7, height: 7)
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if job.state == .running {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(verbatim: Self.elapsed(from: job.startedAt, to: ctx.date))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                }
                Button(action: onNew) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            Text(verbatim: job.text)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#9398A1"))
                .lineLimit(1)
                .truncationMode(.tail)
            content
            Spacer(minLength: 0)
            buttons
        }
    }

    private var title: String {
        let name = job.target == .hermes ? "Hermes" : "Claude Code"
        switch job.state {
        case .running: return name
        case .done: return String(format: String(localized: "ask.done %@", defaultValue: "%@ is done"), name)
        case .failed: return String(format: String(localized: "ask.failed %@", defaultValue: "%@ stopped"), name)
        case .stopped: return String(format: String(localized: "ask.stopped %@", defaultValue: "%@ was stopped"), name)
        }
    }

    private var subtitle: String {
        var parts = [job.target == .hermes ? String(format: String(localized: "ask.on %@", defaultValue: "on %@"), job.place)
                     : String(format: String(localized: "ask.in %@", defaultValue: "in %@"), job.place)]
        if let end = job.endedAt { parts.append(Self.elapsed(from: job.startedAt, to: end)) }
        if !job.steps.isEmpty {
            parts.append(job.steps.count == 1 ? String(localized: "ask.step-one", defaultValue: "1 step")
                         : String(format: String(localized: "ask.steps %lld", defaultValue: "%lld steps"), job.steps.count))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var content: some View {
        switch job.state {
        case .running, .stopped:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(job.steps.suffix(3).enumerated()), id: \.offset) { i, step in
                    let last = i == min(job.steps.count, 3) - 1 && job.state == .running
                    HStack(spacing: 5) {
                        Image(systemName: last ? "circle.dotted" : "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(last ? Color(hex: "#F5F6F8") : Color(hex: "#34D399"))
                        Text(verbatim: step)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(last ? Color(hex: "#E8E9EC") : Color(hex: "#8E939C"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if job.steps.isEmpty && job.state == .running {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("ask.thinking")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                }
            }
        case .done:
            ScrollView {
                Text(verbatim: job.answer.isEmpty ? String(localized: "ask.no-answer", defaultValue: "Done, with nothing to say.") : job.answer)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#E8E9EC"))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 96)
        case .failed(let why):
            Text(verbatim: why)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(hex: "#F7C1C1"))
                .lineLimit(3)
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 8) {
            switch job.state {
            case .running:
                SecondaryButton(verbatim: String(localized: "ask.stop", defaultValue: "Stop")) { runner.stop(job.id) }
                SecondaryButton(verbatim: String(localized: "ask.new", defaultValue: "New task"), action: onNew)
            case .done:
                PrimaryButton(verbatim: String(localized: "ask.read", defaultValue: "Read aloud")) {
                    runner.readAloud(job)
                }
                SecondaryButton(verbatim: String(localized: "ask.copy", defaultValue: "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(job.answer, forType: .string)
                    SoundEngine.shared.play("pop")
                }
                if job.target == .hermes {
                    SecondaryButton(verbatim: String(localized: "ask.to-claude", defaultValue: "Hand to Claude")) {
                        _ = runner.passToClaude(job)
                    }
                }
                SecondaryButton(verbatim: String(localized: "ask.new", defaultValue: "New task"), action: onNew)
            case .failed, .stopped:
                PrimaryButton(verbatim: String(localized: "ask.retry", defaultValue: "Try again")) {
                    _ = runner.ask(job.text, chosen: job.target, source: "retry")
                }
                SecondaryButton(verbatim: String(localized: "ask.new", defaultValue: "New task"), action: onNew)
            }
        }
    }

    static func elapsed(from start: Date, to end: Date) -> String {
        let s = max(0, Int(end.timeIntervalSince(start)))
        return s < 3600 ? String(format: "%d:%02d", s / 60, s % 60) : String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}
#endif
