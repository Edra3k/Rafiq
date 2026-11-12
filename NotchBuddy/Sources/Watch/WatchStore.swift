import Foundation
import WatchConnectivity
import WidgetKit

// MARK: - What the Watch knows: from the iPhone, never from the Mac
// The iPhone sends its sessions, the latest "Ask…" tasks and the next prayer (one
// application context). The Watch answers through the iPhone: a decision (allow or deny one
// exact request) or a task to ask. The complications read a copy in the App Group.

@MainActor
@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    static let shared = WatchStore()

    var sessions: [WatchSession] = []
    var asks: [AskResult] = []
    var prayerName: String?
    var prayerAt: Date?
    var reachable = false

    static let groupID = "group.com.edra3k.rafiq.ios"

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        apply(WCSession.default.receivedApplicationContext)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "watchDemo") { fillDemo() }
        #endif
    }

    #if DEBUG
    /// `-watchDemo YES` at launch: a request waiting, an agent at work, two tasks, the next prayer.
    private func fillDemo() {
        sessions = [
            WatchSession(id: "agent_hermes", name: "Hermes", title: "Nettoyer les sauvegardes", color: "#C084FC",
                         state: "approval", step: "", needsApproval: true,
                         command: "rm /var/lib/vz/dump/*.old", fingerprint: "demo"),
            WatchSession(id: "integration_claude", name: "Claude Code", title: "Rafiq", color: "#F5F6F8",
                         state: "working", step: "Edit AskRunner.swift", needsApproval: false, command: "", fingerprint: ""),
        ]
        let now = Date()
        asks = [
            AskResult(id: "ask-demo1", target: .hermes, text: "Vérifie le disque du serveur", place: "pve", state: .done,
                      answer: "Disque à 71 %. La VM jellyfin débordera dans trois semaines.", steps: ["df -h"],
                      startedAt: now.addingTimeInterval(-98), endedAt: now),
            AskResult(id: "ask-demo2", target: .claude, text: "Corrige le build", place: "Rafiq", state: .running,
                      answer: "", steps: ["Edit AskRunner.swift"], startedAt: now, endedAt: nil),
        ]
        prayerName = "Dhuhr"
        prayerAt = now.addingTimeInterval(3 * 3600)
    }
    #endif

    var waiting: WatchSession? { sessions.first { $0.needsApproval && !$0.fingerprint.isEmpty } }
    var working: [WatchSession] { sessions.filter { $0.state == "working" || $0.state == "thinking" } }

    // MARK: Answers

    enum SendResult { case sent, failed, noPhone }

    func decide(_ decision: String, for session: WatchSession) async -> SendResult {
        await send([WatchSnapshot.decisionKey: decision,
                    WatchSnapshot.fingerprintKey: session.fingerprint,
                    WatchSnapshot.pillKey: session.id,
                    WatchSnapshot.commandKey: session.command])
    }

    func ask(_ text: String, target: AskTarget) async -> SendResult {
        await send([WatchSnapshot.askTextKey: text, WatchSnapshot.askTargetKey: target.rawValue])
    }

    private func send(_ message: [String: Any]) async -> SendResult {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return .noPhone }
        let box = MessageBox(message)
        return await withCheckedContinuation { cont in
            WCSession.default.sendMessage(box.message, replyHandler: { reply in
                cont.resume(returning: (reply["ok"] as? Bool ?? false) ? .sent : .failed)
            }, errorHandler: { _ in
                cont.resume(returning: .failed)
            })
        }
    }

    // MARK: Context

    private func apply(_ context: [String: Any]) {
        sessions = WatchSnapshot.decode(context)
        asks = WatchSnapshot.decodeAsks(context)
        prayerName = context[WatchSnapshot.prayerNameKey] as? String
        prayerAt = context[WatchSnapshot.prayerAtKey] as? Date
        // The complications' copy.
        let shared = UserDefaults(suiteName: Self.groupID)
        shared?.set(prayerName, forKey: WatchShared.prayerNameKey)
        shared?.set(prayerAt, forKey: WatchShared.prayerAtKey)
        shared?.set(working.count + asks.filter { $0.state == .running }.count, forKey: WatchShared.activeKey)
        shared?.set(waiting != nil, forKey: WatchShared.waitingKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = MessageBox(session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            self.apply(context.message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let context = MessageBox(applicationContext)
        Task { @MainActor in self.apply(context.message) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable }
    }
}

/// WatchConnectivity dictionaries hold plist values only; this carries one across actors.
struct MessageBox: @unchecked Sendable {
    let message: [String: Any]
    init(_ message: [String: Any]) { self.message = message }
}
