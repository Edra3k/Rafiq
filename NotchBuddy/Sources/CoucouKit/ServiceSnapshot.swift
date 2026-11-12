import Foundation

// What the iPhone shows for one service Rafiq (GitHub, Stripe, Vercel, Resend,
// Cal.com, n8n, Notion): its state dot, why it has that color, and the latest
// items the Mac fetched. The Mac builds it from the data its pollers already
// keep (ServicePublisher) and writes it to the private iCloud zone, encrypted;
// the iPhone only reads it. No API key ever leaves the Mac.

enum ServiceTone: String, Codable, Sendable {
    case ok, warning, error, info, idle
}

struct ServiceItem: Codable, Equatable, Sendable {
    var title: String
    var detail: String = ""
    var tone: ServiceTone = .idle
    var date: Date? = nil
    var url: String? = nil
}

struct ServiceSection: Codable, Equatable, Sendable {
    var title: String
    var items: [ServiceItem]
}

struct ServiceSnapshot: Codable, Equatable, Sendable {
    var pillId: String
    var tone: ServiceTone
    /// One line under the name ("Balance 1 240,00 EUR", "2 pull requests").
    var headline: String
    /// Why the dot has its color ("CI failing on coucou · main").
    var reason: String
    var sections: [ServiceSection]
    var updatedAt: Date

    static let recordType = "Service"

    static func recordName(for pillId: String) -> String { "service-\(pillId)" }

    static func pillId(fromRecordName name: String) -> String? {
        name.hasPrefix("service-") ? String(name.dropFirst("service-".count)) : nil
    }

    /// Equal apart from the date: nothing to write again.
    func sameContent(as other: ServiceSnapshot) -> Bool {
        var a = self, b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }
}

extension PillCatalog {
    /// The service Rafiq the iPhone shows, in this order.
    static let phoneServices = [
        "integration_github", "integration_stripe", "integration_vercel", "integration_resend",
        "integration_calcom", "integration_n8n", "integration_notion",
    ]

    /// Agent sessions (VS Code, Cursor, Codex…), as opposed to services and chat providers.
    static func isSession(_ id: String) -> Bool {
        switch definition(for: id)?.category {
        case .service, .ai: false
        default: true
        }
    }
}

// MARK: - Prayer times, as the Mac computed them

/// The Mac publishes today's and tomorrow's prayer times as the `integration_prayer`
/// service (items: title = the prayer's name, detail = its key, date = its time).
enum PrayerSchedule {
    static let pillId = "integration_prayer"

    /// The next prayer after `now` (sunrise left out), from the published times.
    static func next(in snapshot: ServiceSnapshot?, after now: Date = Date()) -> (name: String, at: Date)? {
        guard let snapshot else { return nil }
        let items = snapshot.sections.flatMap(\.items)
            .filter { $0.detail != "sunrise" }
            .compactMap { item in item.date.map { (name: item.title, at: $0) } }
            .filter { $0.at > now }
            .sorted { $0.at < $1.at }
        return items.first
    }
}
