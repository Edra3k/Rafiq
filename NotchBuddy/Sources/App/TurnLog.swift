import Foundation

// MARK: - TurnLog: a short line per finished turn, kept 30 days
//
// For the morning brief (what the agents did overnight), the day's timeline and the week's cost
// per project. One small JSON file in Application Support, on this Mac only: the project, when,
// how long, the first words of the prompt (secrets masked), the tokens, the files and lines, the
// guard's worst rating. No answer, no command, no file content.

struct TurnRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var pill: String
    var title: String
    var cwd: String
    var prompt: String
    var startedAt: Date
    var endedAt: Date
    var tokens: Int?
    var steps: Int
    /// CommandRisk.Level raw value of the worst step (0 safe, 1 caution, 2 high).
    var worst: Int
    var files: Int
    var added: Int
    var removed: Int
    var model: String?
    var stopped: Bool

    /// The project's name: the folder's last component, else the session's title.
    var project: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || cwd.isEmpty ? (title.isEmpty ? "—" : title) : name
    }
}

@MainActor
final class TurnLog: ObservableObject {
    static let shared = TurnLog()

    @Published private(set) var records: [TurnRecord] = []

    static let keptDays = 30
    nonisolated static let promptLength = 140

    private var saveScheduled = false

    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchBuddy/turnlog.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = (try? decoder.decode([TurnRecord].self, from: data)) ?? []
        }
        prune()
    }

    /// A turn ended (or was stopped): its line, added or updated (the tokens come later).
    func note(_ turn: TurnHistory.Turn) {
        guard let end = turn.endedAt else { return }
        let files = TurnHistory.shared.files(of: turn)
        let record = TurnRecord(
            id: turn.id, pill: turn.pill, title: turn.title, cwd: turn.cwd,
            prompt: Self.safePrompt(turn.prompt),
            startedAt: turn.startedAt, endedAt: end, tokens: turn.tokens,
            steps: turn.steps.count,
            worst: turn.steps.map(\.risk.level.rawValue).max() ?? 0,
            files: files.count, added: files.reduce(0) { $0 + $1.added }, removed: files.reduce(0) { $0 + $1.removed },
            model: turn.model, stopped: turn.stopped)
        if let i = records.firstIndex(where: { $0.id == turn.id }) {
            guard records[i] != record else { return }
            records[i] = record
        } else {
            records.append(record)
        }
        scheduleSave()
    }

    /// Turns that ended between two dates, oldest first.
    func turns(from start: Date, to end: Date = .distantFuture) -> [TurnRecord] {
        records.filter { $0.endedAt >= start && $0.endedAt < end }.sorted { $0.endedAt < $1.endedAt }
    }

    /// The prompt's first words, one line, secrets masked.
    nonisolated static func safePrompt(_ prompt: String) -> String {
        let text = prompt.replacingOccurrences(of: "\n", with: " ")
        guard !SecretScanner.scan(text).isEmpty else { return String(text.prefix(promptLength)) }
        // A key in the prompt: each word that is one is masked ("sk-a••••••••Qf").
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let w = String(word)
            return SecretScanner.scan(w).isEmpty && SecretScanner.scan("key=" + w).isEmpty ? w : SecretScanner.mask(w)
        }
        return String(words.joined(separator: " ").prefix(promptLength))
    }

    private func prune() {
        let limit = Date().addingTimeInterval(-Double(Self.keptDays) * 86_400)
        let before = records.count
        records.removeAll { $0.endedAt < limit }
        if records.count != before { scheduleSave() }
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated {
                TurnLog.shared.saveScheduled = false
                TurnLog.shared.save()
            }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
