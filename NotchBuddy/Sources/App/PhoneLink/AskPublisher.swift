#if PHONE_LINK && !APPSTORE
import CloudKit
import Foundation

// MARK: - "Ask…" tasks, for the iPhone and the Watch
// Each task Hermes or Claude runs for "Ask…" is written to the private iCloud zone,
// encrypted (task, steps, answer): when it starts, as its steps come (at most every 5 s)
// and when it ends. A task gone from this Mac's list is deleted. Only when the iPhone
// link is on (Settings → General → iPhone).

@MainActor
final class AskPublisher {
    static let shared = AskPublisher()

    private var database: CKDatabase { CKContainer(identifier: CloudProbe.containerID).privateCloudDatabase }
    private var published: [String: AskResult] = [:]
    private var lastWrite: [String: Date] = [:]
    private var pending: Set<String> = []

    func publish(_ jobs: [AskRunner.Job]) {
        guard CloudProbe.isEnabled else { return }
        let results = jobs.map(Self.result(of:))
        let now = Date()
        var saving: [CKRecord] = []
        for result in results where published[result.id] != result {
            // Steps throttle; a start or an end goes at once.
            let stepOnly = published[result.id].map { $0.state == result.state } ?? false
            if stepOnly, let last = lastWrite[result.id], now.timeIntervalSince(last) < 5 {
                schedule(result.id)
                continue
            }
            if let record = record(for: result) { saving.append(record) }
            published[result.id] = result
            lastWrite[result.id] = now
        }
        let gone = published.keys.filter { id in !results.contains { $0.id == id } }
        let deleting = gone.map { CKRecord.ID(recordName: AskResult.recordName(for: $0), zoneID: SessionSnapshot.zoneID) }
        for id in gone { published[id] = nil; lastWrite[id] = nil }
        guard !saving.isEmpty || !deleting.isEmpty else { return }
        Task {
            do {
                _ = try await database.modifyRecords(saving: saving, deleting: deleting, savePolicy: .changedKeys, atomically: false)
            } catch {
                CloudProbe.shared.log("[ask] publish failed: \(error.localizedDescription)")
            }
        }
    }

    private func schedule(_ id: String) {
        guard pending.insert(id).inserted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.pending.remove(id)
            self?.publish(AskRunner.shared.jobs)
        }
    }

    static func result(of job: AskRunner.Job) -> AskResult {
        let state: AskResult.State
        switch job.state {
        case .running: state = .running
        case .done: state = .done
        case .failed: state = .failed
        case .stopped: state = .stopped
        }
        var answer = job.answer
        if case .failed(let why) = job.state { answer = why }
        return AskResult(id: job.id, target: job.target, text: String(job.text.prefix(1000)), place: job.place,
                         state: state, answer: String(answer.prefix(6000)), steps: Array(job.steps.suffix(8)),
                         startedAt: job.startedAt, endedAt: job.endedAt)
    }

    private func record(for result: AskResult) -> CKRecord? {
        guard let json = try? JSONEncoder().encode(result), let payload = String(data: json, encoding: .utf8) else { return nil }
        let record = CKRecord(recordType: AskResult.recordType,
                              recordID: CKRecord.ID(recordName: AskResult.recordName(for: result.id), zoneID: SessionSnapshot.zoneID))
        record["state"] = result.state.rawValue
        record["updatedAt"] = Date()
        record.encryptedValues["payload"] = payload
        return record
    }
}
#endif
