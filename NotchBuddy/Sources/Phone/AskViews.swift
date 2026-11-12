import AVFoundation
import NaturalLanguage
import SwiftUI

// MARK: - "Ask…" on the iPhone
// The same card as the notch: who (Auto, Hermes, Claude), the task, typed or dictated. The
// Mac runs it (Hermes on the Mac or the server, Claude in the project named), the approvals
// come here like any other, and the answer comes back to read or to hear.

struct AskCard: View {
    let link: PhoneLink
    @State private var text = ""
    @State private var target: AskTarget = .auto
    @State private var sending = false
    @State private var sentAt: Date?
    @State private var failed = false
    @State private var dictation = Dictation()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Ask")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let next = link.nextPrayer {
                    Label {
                        Text(verbatim: next.name + " ") + Text(next.at, style: .time)
                    } icon: {
                        Image(systemName: "moon.fill")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(hex: "#E8B64A"))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(.auto, icon: "sparkles", label: String(localized: "Auto"))
                    chip(.hermes, dot: "#C084FC", label: "Hermes")
                    chip(.claude, dot: "#D97757", label: "Claude")
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Check the server's disk space", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                Button {
                    Task { await dictation.toggle(startingFrom: text) }
                } label: {
                    Image(systemName: dictation.isRecording ? "waveform" : "mic.fill")
                        .foregroundStyle(dictation.isRecording ? Color.red : Color(hex: "#E8B64A"))
                        .symbolEffect(.variableColor.iterative, isActive: dictation.isRecording)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel(dictation.isRecording ? Text("Stop dictation") : Text("Dictate"))
                Button(action: send) {
                    Image(systemName: sending ? "ellipsis" : "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(text.isEmpty ? Color.gray : Color.white))
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                .accessibilityLabel(Text("Send"))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            Text(verbatim: status)
                .font(.caption)
                .foregroundStyle(failed ? Color.red : Color.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .glassCard()
        .onChange(of: dictation.transcript) { _, words in
            if dictation.isRecording { text = dictation.prefix + words }
        }
    }

    private var status: String {
        if failed { return String(localized: "Couldn't reach your Mac. Is the iPhone link on in Rafiq's Settings?") }
        if sentAt != nil { return String(localized: "Sent. Your Mac starts it within a few seconds; approvals come here.") }
        let route = AskRouter.route(text, chosen: target)
        guard !route.text.isEmpty else {
            return String(localized: "Hermes for the server and the home, Claude for code. It runs on your Mac.")
        }
        switch route.target {
        case .hermes: return String(localized: "Hermes will do it.")
        case .claude: return String(localized: "Claude Code will do it.")
        case .answer, .auto: return String(localized: "Hermes will answer.")
        }
    }

    private func chip(_ t: AskTarget, icon: String? = nil, dot: String? = nil, label: String) -> some View {
        let on = target == t
        return Button { target = t } label: {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.caption2.weight(.bold)) }
                if let dot { Circle().fill(Color(hex: dot)).frame(width: 7, height: 7) }
                Text(verbatim: label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(on ? Color.black : Color.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func send() {
        dictation.stop()
        let task = text
        guard !task.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        sending = true
        failed = false
        Task {
            let ok = await link.sendAsk(task, target: target)
            sending = false
            if ok {
                text = ""
                sentAt = Date()
                focused = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                failed = true
            }
        }
    }
}

// MARK: - A task in the list

struct AskRow: View {
    let result: AskResult

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color(hex: result.colorHex)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: result.text)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if result.state == .running {
                ProgressView()
            } else if result.state == .done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        switch result.state {
        case .running:
            return result.steps.last.map { "\(result.agentName) · \($0)" } ?? String(localized: "\(result.agentName) is on it")
        case .done:
            return result.answer.isEmpty ? result.agentName : result.answer.replacingOccurrences(of: "\n", with: " ")
        case .failed:
            return String(localized: "\(result.agentName) stopped")
        case .stopped:
            return String(localized: "\(result.agentName) was stopped")
        }
    }
}

// MARK: - A task up close

struct AskResultView: View {
    let link: PhoneLink
    let id: String
    @State private var copied = false

    var body: some View {
        if let result = link.asks[id] {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: result.colorHex)).frame(width: 9, height: 9)
                            Text(verbatim: result.agentName).font(.headline)
                            Text(verbatim: result.place).font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            if let end = result.endedAt {
                                Text(verbatim: Self.duration(end.timeIntervalSince(result.startedAt)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(verbatim: result.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if !result.answer.isEmpty {
                    Section(result.state == .done ? "Answer" : "What happened") {
                        Text(verbatim: result.answer)
                            .textSelection(.enabled)
                        HStack {
                            Button {
                                AskSpeaker.shared.read(result.answer, all: true)
                            } label: {
                                Label("Read aloud", systemImage: "speaker.wave.2.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.black)
                            Button {
                                UIPasteboard.general.string = result.answer
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            ShareLink(item: result.answer) { Image(systemName: "square.and.arrow.up") }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                if !result.steps.isEmpty {
                    Section("Steps") {
                        ForEach(Array(result.steps.enumerated()), id: \.offset) { _, step in
                            Label {
                                Text(verbatim: step).font(.system(.footnote, design: .monospaced))
                            } icon: {
                                Image(systemName: "checkmark").foregroundStyle(.green)
                            }
                        }
                    }
                }
                if result.state == .running {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("\(result.agentName) is on it")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(result.agentName)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("This task is gone", systemImage: "sparkles")
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Said aloud on the iPhone

/// Says an answer with the iPhone's own voice: when a task ends while Rafiq is open (if
/// "Say answers aloud" is on), or on "Read aloud".
@MainActor
final class AskSpeaker {
    static let shared = AskSpeaker()
    static let speakKey = "askSpeakAnswers"
    private let synth = AVSpeechSynthesizer()

    var speaksAnswers: Bool { UserDefaults.standard.object(forKey: Self.speakKey) as? Bool ?? true }

    func finished(_ result: AskResult) {
        guard speaksAnswers, UIApplication.shared.applicationState == .active, result.state == .done else { return }
        read(result.answer, all: false)
    }

    func read(_ answer: String, all: Bool) {
        let sentences = all ? AskSpeech.sentences(answer, max: 12, maxLength: 1500) : AskSpeech.sentences(answer)
        guard !sentences.isEmpty else { return }
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let text = sentences.joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let utterance = AVSpeechUtterance(string: text)
        if let language = recognizer.dominantLanguage?.rawValue {
            utterance.voice = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix(language) }
                .max { $0.quality.rawValue < $1.quality.rawValue }
                ?? AVSpeechSynthesisVoice(language: language)
        }
        synth.speak(utterance)
    }
}

// MARK: - Demo tasks (debug builds: the test screen, or `-askDemo YES` at launch)

enum AskDemo {
    @MainActor static func fill(_ link: PhoneLink) {
        let now = Date()
        link.asks["ask-demo1"] = AskResult(
            id: "ask-demo1", target: .hermes, text: "Vérifie l'espace disque du serveur", place: "pve",
            state: .done,
            answer: "Disque à 71 %. La VM jellyfin occupe 212 Go sur 250 : elle débordera dans trois semaines. 18 Go de vieilles sauvegardes peuvent partir.",
            steps: ["df -h", "pvesh get /nodes/pve/qemu", "du -sh /var/lib/vz/images/*"],
            startedAt: now.addingTimeInterval(-98), endedAt: now)
        link.asks["ask-demo2"] = AskResult(
            id: "ask-demo2", target: .claude, text: "Corrige le build de Rafiq", place: "Rafiq",
            state: .running, answer: "", steps: ["Read HookServer.swift", "Edit AskRunner.swift"],
            startedAt: now.addingTimeInterval(-42), endedAt: nil)
    }
}
