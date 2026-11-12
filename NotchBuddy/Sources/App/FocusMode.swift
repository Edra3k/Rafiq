import Combine
import Foundation

// MARK: - FocusMode: a Pomodoro's work keeps what can wait
//
// While a Pomodoro is in its work phase (and the setting is on, the default), an agent that
// finishes no longer opens the island nor rings: it is put aside, and one card at the end of
// the work says what came in. What needs you still comes at once: a request to allow, a
// question, an error. Prayer keeps its own, stricter quiet (PrayerQuiet).

@MainActor
final class FocusMode: ObservableObject {
    static let shared = FocusMode()
    static let enabledKey = "focusQuietEnabled"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    @Published private(set) var isActive = false
    private var held: [String] = []
    private var started: Date?
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = CoucoudoroController.shared.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                MainActor.assumeIsolated { self?.update(phase) }
            }
    }

    /// Settings changed: start or end now.
    func settingsChanged() { update(CoucoudoroController.shared.phase) }

    private func update(_ phase: CoucoudoroPhase) {
        let on = Self.isEnabled && phase == .work
        if on, !isActive {
            isActive = true
            started = Date()
            held = []
        } else if !on, isActive {
            end()
        }
    }

    /// Kept for later: an agent done or confused. Approvals, questions and errors pass.
    func holds(_ view: IslandView) -> Bool {
        isActive && (view == .finished || view == .confused)
    }

    func note(_ view: IslandView, name: String?) {
        let who = (name?.isEmpty == false ? name! : "Claude")
        held.append(view == .finished
            ? String(format: String(localized: "focus.finished %@", defaultValue: "%@ finished"), who)
            : String(format: String(localized: "focus.confused %@", defaultValue: "%@ got stuck"), who))
    }

    private func end() {
        isActive = false
        defer { held = [] }
        guard !held.isEmpty else { return }
        let minutes = Int(Date().timeIntervalSince(started ?? Date()) / 60)
        DigestCenter.shared.show(Digest(
            kind: .focus,
            title: String(format: String(localized: "focus.title %@", defaultValue: "During your focus (%@)"),
                          PrayerController.countdown(TimeInterval(max(1, minutes) * 60))),
            subtitle: String(localized: "focus.subtitle", defaultValue: "Kept for now: what could wait."),
            lines: Array(held.suffix(6))
        ))
    }
}
