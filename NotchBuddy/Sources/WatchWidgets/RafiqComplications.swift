import SwiftUI
import WidgetKit

// MARK: - Complications: the next prayer, Rafiq and his agents, on the watch face
// They read what the Watch app last received from the iPhone (App Group). The prayer
// counts down by itself; the timeline moves on at the prayer's time.

struct RafiqEntry: TimelineEntry {
    let date: Date
    let prayerName: String?
    let prayerAt: Date?
    let active: Int
    let waiting: Bool
}

struct RafiqProvider: TimelineProvider {
    func placeholder(in context: Context) -> RafiqEntry {
        RafiqEntry(date: .now, prayerName: "Asr", prayerAt: .now.addingTimeInterval(3600), active: 2, waiting: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (RafiqEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RafiqEntry>) -> Void) {
        let entry = current()
        // After the prayer, the Watch app sends the next one; until then look again in 15 min.
        let next = entry.prayerAt.map { max($0, .now.addingTimeInterval(60)) } ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(min(next, .now.addingTimeInterval(900)))))
    }

    private func current() -> RafiqEntry {
        let d = UserDefaults(suiteName: WatchShared.groupID)
        let at = d?.object(forKey: WatchShared.prayerAtKey) as? Date
        return RafiqEntry(date: .now,
                          prayerName: at.map { $0 > .now } == true ? d?.string(forKey: WatchShared.prayerNameKey) : nil,
                          prayerAt: at.flatMap { $0 > .now ? $0 : nil },
                          active: d?.integer(forKey: WatchShared.activeKey) ?? 0,
                          waiting: d?.bool(forKey: WatchShared.waitingKey) ?? false)
    }
}

private let gold = Color(red: 0.91, green: 0.71, blue: 0.29)

struct PrayerComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RafiqEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            if let name = entry.prayerName, let at = entry.prayerAt {
                Text("\(Image(systemName: "moon.fill")) \(name) \(at, style: .time)")
            } else {
                Text("\(Image(systemName: "moon.fill")) Rafiq")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label {
                    Text(verbatim: entry.prayerName ?? "Rafiq").font(.headline)
                } icon: {
                    Image(systemName: "moon.fill").foregroundStyle(gold)
                }
                if let at = entry.prayerAt {
                    Text(at, style: .relative).font(.caption).monospacedDigit()
                    Text(at, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .widgetAccentable()
        case .accessoryCorner:
            Image(systemName: "moon.fill")
                .font(.title3)
                .foregroundStyle(gold)
                .widgetLabel {
                    if let name = entry.prayerName, let at = entry.prayerAt {
                        Text("\(name) \(at, style: .time)")
                    } else {
                        Text(verbatim: "Rafiq")
                    }
                }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "moon.fill").font(.caption2).foregroundStyle(gold)
                    Text(verbatim: entry.prayerName ?? "—").font(.system(size: 11, weight: .semibold))
                        .minimumScaleFactor(0.6)
                    if let at = entry.prayerAt {
                        Text(at, style: .time).font(.system(size: 9)).minimumScaleFactor(0.6)
                    }
                }
            }
        }
    }
}

struct AgentsComplicationView: View {
    let entry: RafiqEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: entry.waiting ? "hand.raised.fill" : "sparkles")
                    .font(.caption)
                    .foregroundStyle(entry.waiting ? Color.orange : gold)
                Text(verbatim: "\(entry.active)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
        .widgetAccentable()
    }
}

struct PrayerComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RafiqPrayer", provider: RafiqProvider()) { entry in
            PrayerComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Next prayer")
        .description("The next prayer, as Rafiq computed it on your Mac.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct AgentsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RafiqAgents", provider: RafiqProvider()) { entry in
            AgentsComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Agents at work")
        .description("How many agents are working, and a hand when one waits for your OK.")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct RafiqComplications: WidgetBundle {
    var body: some Widget {
        PrayerComplication()
        AgentsComplication()
    }
}
