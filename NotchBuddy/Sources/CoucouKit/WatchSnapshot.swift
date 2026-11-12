import Foundation

// MARK: - What the iPhone sends the Watch, and what the Watch answers
// Plain dictionaries for WatchConnectivity (applicationContext and messages). The Watch
// never talks to the Mac: it asks the iPhone, which sends the decision through iCloud
// like its own buttons.

struct WatchSession: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var title: String
    var color: String
    var state: String
    var step: String
    var needsApproval: Bool
    var command: String
    var fingerprint: String
}

enum WatchSnapshot {
    static let sessionsKey = "sessions"
    static let decisionKey = "decision"
    static let fingerprintKey = "fingerprint"
    static let pillKey = "pillId"
    static let commandKey = "command"
    /// "Ask…" from the Watch: the task and who (AskTarget raw value).
    static let askTextKey = "askText"
    static let askTargetKey = "askTarget"
    static let asksKey = "asks"
    static let prayerNameKey = "prayerName"
    static let prayerAtKey = "prayerAt"

    static func encode(_ sessions: [WatchSession]) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(sessions) else { return [:] }
        return [sessionsKey: data]
    }

    static func encodeAsks(_ asks: [AskResult]) -> Data? {
        // The Watch shows the latest three, with a short answer.
        let latest = asks.sorted { $0.startedAt > $1.startedAt }.prefix(3).map { a -> AskResult in
            var short = a
            short.answer = String(a.answer.prefix(600))
            short.steps = Array(a.steps.suffix(2))
            return short
        }
        return try? JSONEncoder().encode(Array(latest))
    }

    static func decodeAsks(_ context: [String: Any]) -> [AskResult] {
        guard let data = context[asksKey] as? Data,
              let asks = try? JSONDecoder().decode([AskResult].self, from: data) else { return [] }
        return asks
    }

    static func decode(_ context: [String: Any]) -> [WatchSession] {
        guard let data = context[sessionsKey] as? Data,
              let sessions = try? JSONDecoder().decode([WatchSession].self, from: data) else { return [] }
        return sessions
    }
}
