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

    static func encode(_ sessions: [WatchSession]) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(sessions) else { return [:] }
        return [sessionsKey: data]
    }

    static func decode(_ context: [String: Any]) -> [WatchSession] {
        guard let data = context[sessionsKey] as? Data,
              let sessions = try? JSONDecoder().decode([WatchSession].self, from: data) else { return [] }
        return sessions
    }
}
