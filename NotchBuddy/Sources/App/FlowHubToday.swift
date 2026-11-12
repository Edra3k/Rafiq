#if !APPSTORE
import SwiftUI

/// The Rafiq window opens here: salam, the day in both calendars, the prayers, what the
/// agents did, the security alerts, the next prayer and the verse of the day.
struct HubTodayPage: View {
    @ObservedObject var router: HubRouter
    @ObservedObject private var prayer = PrayerController.shared
    @ObservedObject private var center = DigestCenter.shared

    private var greeting: String {
        if let name = resolveUserFirstName() { return String(format: String(localized: "hub.hello %@"), name) }
        return String(localized: "hub.hello")
    }

    var body: some View {
        TimelineView(.everyMinute) { tl in
            let now = tl.date
            let day = RecapStore.shared.daySummary(on: now)
            let prayerOn = AppState.shared.activeIntegrations.contains(PrayerController.pillId) && prayer.today != nil
            HubPageScaffold(title: greeting, subtitle: subtitle(now)) {
                EmptyView()
            } content: {
                Text(verbatim: "السلام عليكم")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(RafiqLook.gold)
                    .padding(.top, -10)
                HStack(spacing: 12) {
                    if prayerOn {
                        tile("\(prayer.prayed.count)/5", String(localized: "brief.tile.prayers", defaultValue: "prayers"), RafiqLook.gold)
                    }
                    tile("\(day?.sessions ?? 0)", String(localized: "brief.tile.sessions", defaultValue: "sessions"), HubTheme.text)
                    tile("+\(day?.linesAdded ?? 0)", String(localized: "brief.tile.lines", defaultValue: "lines added"), HubTheme.green)
                    let alerts = center.securityAlerts(on: now)
                    tile("\(alerts)", String(localized: "today.security", defaultValue: "security alerts"), alerts > 0 ? HubTheme.red : HubTheme.text)
                }
                if prayerOn, let next = prayer.next(at: now) {
                    HStack {
                        Image(systemName: "moon.fill").foregroundColor(RafiqLook.gold)
                        Text(verbatim: "\(PrayerController.name(next.prayer)) \(prayer.clock(next.at)) · "
                             + String(format: String(localized: "prayer.in %@", defaultValue: "in %@"),
                                      PrayerController.countdown(next.at.timeIntervalSince(now))))
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if EveningBrief.isEnabled, let brief = EveningBrief.shared.nextBriefTime(after: now) {
                            Text(String(format: String(localized: "today.brief-at %@", defaultValue: "Evening brief at %@"),
                                        prayer.clock(brief)))
                                .font(.system(size: 13))
                                .foregroundColor(HubTheme.secondary)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(HubTheme.card))
                }
                TodayTimelineCard(now: now)
                WeekCostCard(now: now)
                let verse = Verses.verse(on: now)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: verse.arabic)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(RafiqLook.gold)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(verbatim: verse.meaning)
                        .font(.system(size: 14))
                        .foregroundColor(HubTheme.body)
                    Text(verbatim: verse.reference)
                        .font(.system(size: 12))
                        .foregroundColor(HubTheme.muted)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(HubTheme.card))
            }
        }
    }

    private func subtitle(_ now: Date) -> String {
        let date = DateFormatter.localizedString(from: now, dateStyle: .full, timeStyle: .none)
        return "\(date) · \(prayer.hijriShortArabic(at: now))"
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .foregroundColor(color)
            Text(verbatim: label)
                .font(.system(size: 12))
                .foregroundColor(HubTheme.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(HubTheme.card))
    }
}
#endif
