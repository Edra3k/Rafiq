import Foundation

// MARK: - Verse of the day
// One short verse a day, from a list kept in the app (nothing is fetched), shown the first
// time the island opens on its home view that day, from 4 a.m. It never holds the island
// open: it goes away with it, or with "Got it". Settings → General → Rafiq watches.

@MainActor
enum VerseOfTheDay {
    static let enabledKey = "verseOfTheDay"
    private static let lastDayKey = "verseOfTheDayLastDay"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// The island just opened: the day's verse, if not seen today.
    static func maybeShow(state: AppState) {
        let now = Date()
        guard isEnabled, Calendar.current.component(.hour, from: now) >= 4,
              UserDefaults.standard.string(forKey: lastDayKey) != dayKey(now),
              DigestCenter.shared.current == nil,
              state.pendingApproval == nil, state.pendingQuestion == nil,
              state.view == .overview || state.view == .empty else { return }
        UserDefaults.standard.set(dayKey(now), forKey: lastDayKey)
        show(Verses.verse(on: now))
    }

    static func show(_ v: Verse) {
        DigestCenter.shared.show(Digest(
            kind: .verse,
            title: v.arabic,
            subtitle: v.meaning,
            lines: [v.reference]
        ))
    }
}
