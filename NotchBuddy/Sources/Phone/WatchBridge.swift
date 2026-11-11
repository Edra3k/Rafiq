import Foundation
import WatchConnectivity

/// Keeps the Watch up to date with the Mac's sessions and takes its answers.
/// Deny goes straight through; Allow was confirmed on the Watch (two taps on the wrist,
/// which watchOS keeps locked when the Watch is off the wrist).
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private var lastSent: [WatchSession] = []

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func push(_ sessions: [SessionItem]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let items = sessions.sortedByUrgency().prefix(8).map { s in
            WatchSession(id: s.id, name: s.pillName, title: s.title, color: s.color, state: s.state.rawValue,
                         step: s.currentStep ?? "", needsApproval: s.needsApproval,
                         command: String(s.approvalCommand.prefix(300)), fingerprint: s.approvalFingerprint)
        }
        guard Array(items) != lastSent else { return }
        lastSent = Array(items)
        try? WCSession.default.updateApplicationContext(WatchSnapshot.encode(Array(items)))
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in WatchBridge.shared.push(PhoneLink.shared.sessions) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let decision = message[WatchSnapshot.decisionKey] as? String ?? ""
        let fingerprint = message[WatchSnapshot.fingerprintKey] as? String ?? ""
        let pill = message[WatchSnapshot.pillKey] as? String ?? ""
        let command = message[WatchSnapshot.commandKey] as? String ?? "Permission"
        let reply = UncheckedReply(replyHandler)
        Task { @MainActor in
            guard let d = Decision(rawValue: decision), !fingerprint.isEmpty else { reply.send(["ok": false]); return }
            let ok = await PhoneLink.shared.decide(d, fingerprint: fingerprint, pillId: pill,
                                                   summary: String(command.prefix(200)))
            reply.send(["ok": ok])
        }
    }
}

/// The reply handler crosses to the main actor once; WatchConnectivity allows calling it from any thread.
private struct UncheckedReply: @unchecked Sendable {
    let handler: ([String: Any]) -> Void
    init(_ h: @escaping ([String: Any]) -> Void) { handler = h }
    func send(_ value: [String: Any]) { handler(value) }
}
