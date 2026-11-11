import SwiftUI

// MARK: - Prayer card

/// The focused Prayer pill: the next prayer and how long until it, the sun on its arc,
/// and the five times of the day. Tap a time to check that prayer off.
struct PrayerCardView: View {
    @ObservedObject private var prayer = PrayerController.shared

    private var accent: Color {
        Color(hex: PillCatalog.definition(for: PrayerController.pillId)?.color ?? "#A78BFA")
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            card(at: timeline.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private func card(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(PrayerController.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                if let name = prayer.location?.name, !name.isEmpty {
                    Text(verbatim: name)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            if prayer.location == nil || prayer.today == nil {
                Text(String(localized: "prayer.no-location",
                            defaultValue: "Pick your city in Integrations → Prayer."))
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.leading, 116)
                    .padding(.trailing, 12)
            } else {
                headline(at: date)
                    .padding(.top, 4)
                    .padding(.leading, 116)
                    .padding(.trailing, 12)
                if let today = prayer.today {
                    PrayerSunArc(day: today, date: date, accent: accent)
                        .frame(height: 18)
                        .padding(.top, 4)
                        .padding(.leading, 116)
                        .padding(.trailing, 12)
                    times(today, at: date)
                        .padding(.top, 3)
                        .padding(.leading, 112)
                        .padding(.trailing, 8)
                }
            }
        }
    }

    /// "Maghrib 17:48 · in 1 h 8 min", or the prayer that has just come.
    @ViewBuilder private func headline(at date: Date) -> some View {
        let current = prayer.current(at: date)
        let isNow = current.map { date.timeIntervalSince($0.at) < PrayerController.nowWindow } ?? false
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if isNow, let current {
                Text(String(format: String(localized: "prayer.time-for %@", defaultValue: "It's time for %@"),
                            PrayerController.name(current.prayer)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let next = prayer.next(at: date) {
                Text(PrayerController.name(next.prayer))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text(verbatim: prayer.clock(next.at))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text(String(format: String(localized: "prayer.in %@", defaultValue: "in %@"),
                            PrayerController.countdown(next.at.timeIntervalSince(date))))
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if prayer.adhanPlaying {
                Button(action: { prayer.stopAdhan() }) {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#E8E9EC"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(String(localized: "prayer.stop-adhan", defaultValue: "Stop the adhan"))
            }
        }
    }

    /// The five times; the next one in the pill's colour, the ones checked off with a tick.
    private func times(_ day: PrayerDay, at date: Date) -> some View {
        let next = prayer.next(at: date)?.prayer
        return HStack(spacing: 0) {
            ForEach(Prayer.obligatory, id: \.self) { p in
                let done = prayer.prayed.contains(p)
                let highlighted = p == next
                Button(action: { prayer.togglePrayed(p) }) {
                    VStack(spacing: 1) {
                        HStack(spacing: 2) {
                            if done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(accent)
                            }
                            Text(PrayerController.name(p))
                                .font(.system(size: 9, weight: highlighted ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundColor(highlighted ? accent : Color(hex: "#8E939C"))
                        Text(verbatim: day.time(p).map { prayer.clock($0) } ?? "—")
                            .font(.system(size: 10, weight: highlighted ? .semibold : .regular))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundColor(highlighted ? Color(hex: "#F5F6F8") : Color(hex: "#C0C4CC"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(highlighted ? accent.opacity(0.12) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(done
                      ? String(localized: "prayer.unmark", defaultValue: "Prayed. Click to undo.")
                      : String(localized: "prayer.mark", defaultValue: "Click once you have prayed."))
            }
        }
    }
}

// MARK: - Sun arc

/// The day as an arc from sunrise to Maghrib, with the sun where it is now and a mark at
/// Dhuhr and Asr. At night the arc is dim and the sun rests at the horizon.
struct PrayerSunArc: View {
    let day: PrayerDay
    let date: Date
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func point(_ progress: Double) -> CGPoint {
                CGPoint(x: progress * w, y: h - 1 - sin(progress * .pi) * (h - 4))
            }
            var arc = Path()
            arc.move(to: point(0))
            for i in 1...48 { arc.addLine(to: point(Double(i) / 48)) }
            context.stroke(arc, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 3]))

            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: h - 0.5))
            horizon.addLine(to: CGPoint(x: w, y: h - 0.5))
            context.stroke(horizon, with: .color(.white.opacity(0.08)), lineWidth: 1)

            guard let rise = day.time(.sunrise), let set = day.time(.maghrib), set > rise else { return }
            let span = set.timeIntervalSince(rise)
            for p in [Prayer.dhuhr, .asr] {
                guard let t = day.time(p) else { continue }
                let progress = min(max(t.timeIntervalSince(rise) / span, 0), 1)
                let c = point(progress)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)),
                             with: .color(.white.opacity(0.35)))
            }

            if let progress = PrayerTimesEngine.sunProgress(at: date, day: day) {
                var done = Path()
                done.move(to: point(0))
                let steps = max(1, Int(progress * 48))
                for i in 1...steps { done.addLine(to: point(progress * Double(i) / Double(steps))) }
                context.stroke(done, with: .color(accent.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                let sun = point(progress)
                context.fill(Path(ellipseIn: CGRect(x: sun.x - 6, y: sun.y - 6, width: 12, height: 12)),
                             with: .color(accent.opacity(0.18)))
                context.fill(Path(ellipseIn: CGRect(x: sun.x - 3.5, y: sun.y - 3.5, width: 7, height: 7)),
                             with: .color(accent))
            } else {
                // Night: a small moon resting on the side the sun will come back from.
                let x = date < rise ? 3.0 : w - 3
                context.fill(Path(ellipseIn: CGRect(x: x - 3, y: h - 7, width: 6, height: 6)),
                             with: .color(.white.opacity(0.45)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Prayer pill

/// The capsule in the pill grid: the next prayer and its time, a countdown before it, "now" after.
struct PrayerPill: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
    let onTap: () -> Void
    @ObservedObject private var prayer = PrayerController.shared
    @State private var isHovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let label = prayer.pillLabel(at: timeline.date)
            Button(action: { onTap() }) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Capsule()
                            .fill(isHovered ? Color(hex: task.color).opacity(0.18) : Color(hex: "#0E0F11"))
                        Capsule()
                            .stroke(Color(hex: task.color).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                        HStack(spacing: 0) {
                            MiniBotCanvasView(task: task)
                                .frame(width: 22 / 0.6, height: 22 / 0.6)
                                .frame(width: 22, height: 22, alignment: .center)
                                .padding(.leading, 8)
                            Spacer()
                        }
                        Text(verbatim: label)
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(isHovered
                                             ? Color(hex: task.color).lighter(by: 0.3)
                                             : Color(hex: "#6B7079"))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, 30)
                            .padding(.trailing, 8)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .shadow(color: Color(hex: task.color).opacity(isHovered ? 0.35 : 0), radius: 10, x: 0, y: 2)

                    if let badge = task.pillBadge {
                        PillBadgeView(badge: badge, taskColor: task.color)
                            .offset(x: 3, y: -3)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(label)
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .brightness(isHovered ? 0.06 : 0)
            .onHover { hovering in
                guard !swapping else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = hovering }
            }
        }
    }
}

// MARK: - Settings

/// Settings → Integrations → Prayer: the place, the method, the reminders and a preview of today.
struct PrayerSettingsSection: View {
    @AppStorage(PrayerSettings.cityKey) private var city = ""
    @AppStorage(PrayerSettings.customNameKey) private var customName = ""
    @AppStorage(PrayerSettings.latitudeKey) private var latitude: Double = 0
    @AppStorage(PrayerSettings.longitudeKey) private var longitude: Double = 0
    @AppStorage(PrayerSettings.methodKey) private var method = ""
    @AppStorage(PrayerSettings.asrKey) private var asr = AsrSchool.standard.rawValue
    @AppStorage(PrayerSettings.highLatitudeKey) private var highLatitude = HighLatitudeRule.angleBased.rawValue
    @AppStorage(PrayerSettings.reminderKey) private var reminder = PrayerSettings.defaultReminder
    @AppStorage(PrayerSettings.pauseMusicKey) private var pauseMusic = true
    @AppStorage(PrayerSettings.adhanKey) private var playAdhan = false
    @AppStorage(PrayerSettings.adjustmentKey(.fajr)) private var adjustFajr = 0
    @AppStorage(PrayerSettings.adjustmentKey(.sunrise)) private var adjustSunrise = 0
    @AppStorage(PrayerSettings.adjustmentKey(.dhuhr)) private var adjustDhuhr = 0
    @AppStorage(PrayerSettings.adjustmentKey(.asr)) private var adjustAsr = 0
    @AppStorage(PrayerSettings.adjustmentKey(.maghrib)) private var adjustMaghrib = 0
    @AppStorage(PrayerSettings.adjustmentKey(.isha)) private var adjustIsha = 0
    @ObservedObject private var prayer = PrayerController.shared

    private let accent = Color(hex: "#A78BFA")
    private let hint = Color(hex: "#8E939C")

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(PrayerController.title).font(.system(size: 12, weight: .semibold))
            }

            Picker(String(localized: "prayer.city", defaultValue: "City"), selection: $city) {
                Text(automaticCityLabel).tag("")
                ForEach(PrayerCities.all, id: \.name) { c in
                    Text(verbatim: c.name).tag(c.name)
                }
                Text(String(localized: "prayer.city.other", defaultValue: "Another place…")).tag(PrayerSettings.custom)
            }

            if city == PrayerSettings.custom {
                TextField(String(localized: "prayer.place-name", defaultValue: "Name of the place"), text: $customName)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    TextField(String(localized: "prayer.latitude", defaultValue: "Latitude"),
                              value: $latitude, format: .number.precision(.fractionLength(0...4)))
                        .textFieldStyle(.roundedBorder)
                    TextField(String(localized: "prayer.longitude", defaultValue: "Longitude"),
                              value: $longitude, format: .number.precision(.fractionLength(0...4)))
                        .textFieldStyle(.roundedBorder)
                }
                Text(String(localized: "prayer.coordinates.hint",
                            defaultValue: "Decimal degrees: north and east are positive (Paris: 48.8566, 2.3522). Times use your Mac's time zone."))
                    .font(.system(size: 10))
                    .foregroundColor(hint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(String(localized: "prayer.method", defaultValue: "Calculation method"), selection: $method) {
                Text(String(format: String(localized: "prayer.method.recommended %@", defaultValue: "Recommended · %@"),
                            recommendedMethod.name)).tag("")
                ForEach(PrayerMethod.allCases, id: \.rawValue) { m in
                    Text(verbatim: m.name).tag(m.rawValue)
                }
            }

            Picker(String(localized: "prayer.asr", defaultValue: "Asr"), selection: $asr) {
                Text(String(localized: "prayer.asr.standard", defaultValue: "Standard (Shafi'i, Maliki, Hanbali)"))
                    .tag(AsrSchool.standard.rawValue)
                Text(String(localized: "prayer.asr.hanafi", defaultValue: "Hanafi")).tag(AsrSchool.hanafi.rawValue)
            }

            Picker(String(localized: "prayer.high-latitude", defaultValue: "High latitudes"), selection: $highLatitude) {
                Text(String(localized: "prayer.high-latitude.angle", defaultValue: "Angle based")).tag(HighLatitudeRule.angleBased.rawValue)
                Text(String(localized: "prayer.high-latitude.middle", defaultValue: "Middle of the night")).tag(HighLatitudeRule.middleOfNight.rawValue)
                Text(String(localized: "prayer.high-latitude.seventh", defaultValue: "Seventh of the night")).tag(HighLatitudeRule.seventhOfNight.rawValue)
            }

            reminderRow

            #if !APPSTORE
            Toggle(String(localized: "prayer.pause-music", defaultValue: "Pause Music and Spotify at prayer time"),
                   isOn: $pauseMusic)
            #endif
            HStack(spacing: 8) {
                Toggle(String(localized: "prayer.adhan", defaultValue: "Play my adhan at prayer time"), isOn: $playAdhan)
                Spacer(minLength: 4)
                Button(String(localized: "Open sounds folder")) { SoundEngine.shared.revealCustomFolder() }
                    .controlSize(.small)
            }
            if playAdhan {
                Text(PrayerController.adhanFile == nil
                     ? String(localized: "prayer.adhan.missing", defaultValue: "Put a file named adhan.mp3 (or .m4a, .wav) in the sounds folder. Until then Mochi greets you.")
                     : String(localized: "prayer.adhan.found", defaultValue: "Your adhan file is ready. Stop it from the card."))
                    .font(.system(size: 10))
                    .foregroundColor(hint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup(String(localized: "prayer.adjust", defaultValue: "Adjust times to your mosque")) {
                VStack(alignment: .leading, spacing: 3) {
                    adjustRow(.fajr, $adjustFajr)
                    adjustRow(.sunrise, $adjustSunrise)
                    adjustRow(.dhuhr, $adjustDhuhr)
                    adjustRow(.asr, $adjustAsr)
                    adjustRow(.maghrib, $adjustMaghrib)
                    adjustRow(.isha, $adjustIsha)
                }
                .padding(.top, 2)
            }
            .font(.system(size: 11))

            preview

            Text(String(localized: "prayer.hint",
                        defaultValue: "Calculated on your Mac, nothing is sent. Turn the Prayer pill on to see the next prayer, with a reminder before each one."))
                .font(.system(size: 10))
                .foregroundColor(hint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .onAppear { clamp(); PrayerController.shared.settingsChanged() }
        .onChange(of: [city, customName, method, asr, highLatitude]) { _, _ in changed() }
        .onChange(of: [latitude, longitude]) { _, _ in changed() }
        .onChange(of: [reminder, adjustFajr, adjustSunrise, adjustDhuhr, adjustAsr, adjustMaghrib, adjustIsha]) { _, _ in changed() }
    }

    private var automaticCityLabel: String {
        let found = PrayerCities.matching(timeZoneId: TimeZone.current.identifier)?.name
            ?? String(localized: "prayer.city.none", defaultValue: "no city found")
        return String(format: String(localized: "prayer.city.automatic %@", defaultValue: "Automatic · %@"), found)
    }

    private var recommendedMethod: PrayerMethod {
        if let c = PrayerCities.named(city) { return c.method }
        if city == PrayerSettings.custom { return PrayerMethod.recommended(forTimeZone: TimeZone.current.identifier) }
        return PrayerSettings.city?.method ?? PrayerMethod.recommended(forTimeZone: TimeZone.current.identifier)
    }

    private var reminderRow: some View {
        let bounds = PrayerSettings.reminderBounds
        let shown = PrayerSettings.clampReminder(reminder)
        let minutes = Binding<Double>(
            get: { Double(PrayerSettings.clampReminder(reminder)) },
            set: { reminder = Int($0.rounded()) }
        )
        let label = String(localized: "prayer.reminder", defaultValue: "Reminder before")
        let unit = String(localized: "coucoudoro.unit", defaultValue: "min")
        return HStack(spacing: 8) {
            Text(label).lineLimit(1)
            Slider(value: minutes, in: Double(bounds.lowerBound)...Double(bounds.upperBound), step: 5)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(verbatim: "\(shown) \(unit)"))
            Text(shown == 0 ? String(localized: "prayer.reminder.off", defaultValue: "No reminder") : "\(shown) \(unit)")
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    private func adjustRow(_ p: Prayer, _ value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(PrayerController.name(p)).frame(width: 90, alignment: .leading)
            Stepper(value: value, in: PrayerSettings.adjustmentBounds) {
                Text(verbatim: value.wrappedValue > 0 ? "+\(value.wrappedValue)" : "\(value.wrappedValue)")
                    .monospacedDigit()
                    .foregroundColor(value.wrappedValue == 0 ? .secondary : .primary)
            }
            Text(String(localized: "coucoudoro.unit", defaultValue: "min"))
                .foregroundColor(.secondary)
        }
    }

    /// Today's times, the Hijri date and the qibla, so a change can be checked at once.
    @ViewBuilder private var preview: some View {
        if let today = prayer.today, prayer.location != nil {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    ForEach(Prayer.allCases, id: \.self) { p in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(PrayerController.name(p)).font(.system(size: 9)).foregroundColor(hint)
                            Text(verbatim: today.time(p).map { prayer.clock($0) } ?? "—")
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                        }
                    }
                }
                HStack(spacing: 10) {
                    Text(verbatim: prayer.hijriDate(at: Date()))
                    if let q = prayer.qibla {
                        Text(String(format: String(localized: "prayer.qibla %@", defaultValue: "Qibla %@"),
                                    "\(Int(q.rounded()))° \(PrayerTimesEngine.compassPoint(q))"))
                            .help(String(localized: "prayer.qibla.help",
                                         defaultValue: "The direction of the Kaaba, in degrees clockwise from true north."))
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(hint)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
        } else if prayer.location == nil {
            Text(String(localized: "prayer.no-location",
                        defaultValue: "Pick your city in Integrations → Prayer."))
                .font(.system(size: 10))
                .foregroundColor(hint)
        }
    }

    private func clamp() {
        let r = PrayerSettings.clampReminder(reminder)
        if r != reminder { reminder = r }
    }

    private func changed() {
        clamp()
        PrayerController.shared.settingsChanged()
    }
}
