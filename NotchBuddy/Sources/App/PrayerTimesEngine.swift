import Foundation

// MARK: - Prayers

/// The five daily prayers, plus sunrise (shown, never announced: it ends Fajr).
enum Prayer: String, CaseIterable, Codable, Sendable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha

    /// The five prayers, in the order of the day.
    static let obligatory: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

    var isObligatory: Bool { self != .sunrise }
}

/// The shadow length that starts Asr.
enum AsrSchool: String, CaseIterable, Sendable {
    /// Shafi'i, Maliki, Hanbali: a shadow as long as the object.
    case standard
    /// Hanafi: twice as long.
    case hanafi

    var shadowFactor: Double { self == .hanafi ? 2 : 1 }
}

/// How Fajr and Isha are kept inside the night where the sun never goes deep enough
/// (northern Europe in summer).
enum HighLatitudeRule: String, CaseIterable, Sendable {
    /// A share of the night set by the angle (angle / 60). The usual choice.
    case angleBased
    /// Never past the middle of the night.
    case middleOfNight
    /// Within the first and the last seventh of the night.
    case seventhOfNight

    func portion(angle: Double) -> Double {
        switch self {
        case .angleBased: return angle / 60
        case .middleOfNight: return 1.0 / 2
        case .seventhOfNight: return 1.0 / 7
        }
    }
}

/// Isha starts at a sun angle, or a fixed time after Maghrib.
enum IshaRule: Equatable, Sendable {
    case angle(Double)
    case minutesAfterMaghrib(Double)
}

/// The angles and offsets a calculation method is made of.
struct PrayerMethodParameters: Equatable, Sendable {
    var fajrAngle: Double
    var isha: IshaRule
    /// Maghrib at a sun angle below the horizon (Tehran) instead of sunset.
    var maghribAngle: Double? = nil
    /// Minutes the method adds to each time (Diyanet, Dubai, Kemenag's ihtiyat).
    var adjustments: [Prayer: Double] = [:]
    /// Extra minutes after Maghrib for Isha during Ramadan (Umm al-Qura: 90 becomes 120).
    var ramadanIshaExtra: Double = 0
}

/// The calculation methods of the main authorities.
enum PrayerMethod: String, CaseIterable, Sendable {
    case muslimWorldLeague
    case northAmerica
    case egypt
    case ummAlQura
    case karachi
    case tehran
    case gulf
    case dubai
    case kuwait
    case qatar
    case singapore
    case malaysia
    case indonesia
    case turkey
    case franceUOIF
    case france15
    case france18
    case algeria
    case tunisia
    case morocco
    case russia

    /// The authority's own name, shown as is in every language.
    var name: String {
        switch self {
        case .muslimWorldLeague: return "Muslim World League"
        case .northAmerica: return "ISNA (North America)"
        case .egypt: return "Egyptian General Authority of Survey"
        case .ummAlQura: return "Umm al-Qura, Makkah"
        case .karachi: return "University of Islamic Sciences, Karachi"
        case .tehran: return "Institute of Geophysics, Tehran"
        case .gulf: return "Gulf Region"
        case .dubai: return "Dubai"
        case .kuwait: return "Kuwait"
        case .qatar: return "Qatar"
        case .singapore: return "MUIS (Singapore)"
        case .malaysia: return "JAKIM (Malaysia)"
        case .indonesia: return "Kemenag (Indonesia)"
        case .turkey: return "Diyanet (Türkiye)"
        case .franceUOIF: return "UOIF (France, 12°)"
        case .france15: return "France (15°)"
        case .france18: return "France (18°)"
        case .algeria: return "Algeria"
        case .tunisia: return "Tunisia"
        case .morocco: return "Morocco"
        case .russia: return "Spiritual Administration of Muslims of Russia"
        }
    }

    var parameters: PrayerMethodParameters {
        switch self {
        case .muslimWorldLeague: return .init(fajrAngle: 18, isha: .angle(17))
        case .northAmerica: return .init(fajrAngle: 15, isha: .angle(15))
        case .egypt: return .init(fajrAngle: 19.5, isha: .angle(17.5))
        case .ummAlQura: return .init(fajrAngle: 18.5, isha: .minutesAfterMaghrib(90), ramadanIshaExtra: 30)
        case .karachi: return .init(fajrAngle: 18, isha: .angle(18))
        case .tehran: return .init(fajrAngle: 17.7, isha: .angle(14), maghribAngle: 4.5)
        case .gulf: return .init(fajrAngle: 19.5, isha: .minutesAfterMaghrib(90))
        case .dubai: return .init(fajrAngle: 18.2, isha: .angle(18.2),
                                  adjustments: [.sunrise: -3, .dhuhr: 3, .asr: 3, .maghrib: 3])
        case .kuwait: return .init(fajrAngle: 18, isha: .angle(17.5))
        case .qatar: return .init(fajrAngle: 18, isha: .minutesAfterMaghrib(90))
        case .singapore: return .init(fajrAngle: 20, isha: .angle(18), adjustments: [.dhuhr: 1])
        case .malaysia: return .init(fajrAngle: 20, isha: .angle(18))
        case .indonesia: return .init(fajrAngle: 20, isha: .angle(18),
                                      adjustments: [.fajr: 2, .sunrise: -2, .dhuhr: 2, .asr: 2, .maghrib: 2, .isha: 2])
        case .turkey: return .init(fajrAngle: 18, isha: .angle(17),
                                   adjustments: [.sunrise: -7, .dhuhr: 5, .asr: 4, .maghrib: 7])
        case .franceUOIF: return .init(fajrAngle: 12, isha: .angle(12))
        case .france15: return .init(fajrAngle: 15, isha: .angle(15))
        case .france18: return .init(fajrAngle: 18, isha: .angle(18))
        case .algeria: return .init(fajrAngle: 18, isha: .angle(17))
        case .tunisia: return .init(fajrAngle: 18, isha: .angle(18))
        case .morocco: return .init(fajrAngle: 19, isha: .angle(17))
        case .russia: return .init(fajrAngle: 16, isha: .angle(15))
        }
    }

    /// The method most used where this time zone is. Muslim World League elsewhere.
    static func recommended(forTimeZone id: String) -> PrayerMethod {
        if let city = PrayerCities.all.first(where: { $0.timeZoneId == id }) { return city.method }
        if id.hasPrefix("America/") || id.hasPrefix("US/") || id.hasPrefix("Canada/") { return .northAmerica }
        return .muslimWorldLeague
    }
}

// MARK: - Places

/// Where the times are for. The time zone gives the calendar day and the clock the times are shown in.
struct PrayerLocation: Equatable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZoneId: String

    var timeZone: TimeZone { TimeZone(identifier: timeZoneId) ?? .current }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct PrayerCity: Equatable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZoneId: String
    let method: PrayerMethod

    var location: PrayerLocation {
        PrayerLocation(name: name, latitude: latitude, longitude: longitude, timeZoneId: timeZoneId)
    }
}

/// Cities to pick from without typing coordinates. Any other place: its latitude and longitude.
enum PrayerCities {
    static let all: [PrayerCity] = [
        .init(name: "Paris", latitude: 48.8566, longitude: 2.3522, timeZoneId: "Europe/Paris", method: .franceUOIF),
        .init(name: "Lyon", latitude: 45.7640, longitude: 4.8357, timeZoneId: "Europe/Paris", method: .franceUOIF),
        .init(name: "Marseille", latitude: 43.2965, longitude: 5.3698, timeZoneId: "Europe/Paris", method: .franceUOIF),
        .init(name: "Lille", latitude: 50.6292, longitude: 3.0573, timeZoneId: "Europe/Paris", method: .franceUOIF),
        .init(name: "Toulouse", latitude: 43.6047, longitude: 1.4442, timeZoneId: "Europe/Paris", method: .franceUOIF),
        .init(name: "Strasbourg", latitude: 48.5734, longitude: 7.7521, timeZoneId: "Europe/Paris", method: .franceUOIF),
        .init(name: "Bordeaux", latitude: 44.8378, longitude: -0.5792, timeZoneId: "Europe/Paris", method: .franceUOIF),
        .init(name: "Nice", latitude: 43.7102, longitude: 7.2620, timeZoneId: "Europe/Paris", method: .franceUOIF),
        .init(name: "Nantes", latitude: 47.2184, longitude: -1.5536, timeZoneId: "Europe/Paris", method: .franceUOIF),
        .init(name: "Brussels", latitude: 50.8503, longitude: 4.3517, timeZoneId: "Europe/Brussels", method: .muslimWorldLeague),
        .init(name: "Geneva", latitude: 46.2044, longitude: 6.1432, timeZoneId: "Europe/Zurich", method: .muslimWorldLeague),
        .init(name: "London", latitude: 51.5074, longitude: -0.1278, timeZoneId: "Europe/London", method: .muslimWorldLeague),
        .init(name: "Amsterdam", latitude: 52.3676, longitude: 4.9041, timeZoneId: "Europe/Amsterdam", method: .muslimWorldLeague),
        .init(name: "Berlin", latitude: 52.5200, longitude: 13.4050, timeZoneId: "Europe/Berlin", method: .muslimWorldLeague),
        .init(name: "Madrid", latitude: 40.4168, longitude: -3.7038, timeZoneId: "Europe/Madrid", method: .muslimWorldLeague),
        .init(name: "Istanbul", latitude: 41.0082, longitude: 28.9784, timeZoneId: "Europe/Istanbul", method: .turkey),
        .init(name: "Moscow", latitude: 55.7558, longitude: 37.6173, timeZoneId: "Europe/Moscow", method: .russia),
        .init(name: "Casablanca", latitude: 33.5731, longitude: -7.5898, timeZoneId: "Africa/Casablanca", method: .morocco),
        .init(name: "Rabat", latitude: 34.0209, longitude: -6.8416, timeZoneId: "Africa/Casablanca", method: .morocco),
        .init(name: "Algiers", latitude: 36.7538, longitude: 3.0588, timeZoneId: "Africa/Algiers", method: .algeria),
        .init(name: "Oran", latitude: 35.6971, longitude: -0.6308, timeZoneId: "Africa/Algiers", method: .algeria),
        .init(name: "Tunis", latitude: 36.8065, longitude: 10.1815, timeZoneId: "Africa/Tunis", method: .tunisia),
        .init(name: "Cairo", latitude: 30.0444, longitude: 31.2357, timeZoneId: "Africa/Cairo", method: .egypt),
        .init(name: "Dakar", latitude: 14.7167, longitude: -17.4677, timeZoneId: "Africa/Dakar", method: .muslimWorldLeague),
        .init(name: "Abidjan", latitude: 5.3600, longitude: -4.0083, timeZoneId: "Africa/Abidjan", method: .muslimWorldLeague),
        .init(name: "Bamako", latitude: 12.6392, longitude: -8.0029, timeZoneId: "Africa/Bamako", method: .muslimWorldLeague),
        .init(name: "Makkah", latitude: 21.4225, longitude: 39.8262, timeZoneId: "Asia/Riyadh", method: .ummAlQura),
        .init(name: "Madinah", latitude: 24.4686, longitude: 39.6142, timeZoneId: "Asia/Riyadh", method: .ummAlQura),
        .init(name: "Riyadh", latitude: 24.7136, longitude: 46.6753, timeZoneId: "Asia/Riyadh", method: .ummAlQura),
        .init(name: "Dubai", latitude: 25.2048, longitude: 55.2708, timeZoneId: "Asia/Dubai", method: .dubai),
        .init(name: "Doha", latitude: 25.2854, longitude: 51.5310, timeZoneId: "Asia/Qatar", method: .qatar),
        .init(name: "Kuwait City", latitude: 29.3759, longitude: 47.9774, timeZoneId: "Asia/Kuwait", method: .kuwait),
        .init(name: "Tehran", latitude: 35.6892, longitude: 51.3890, timeZoneId: "Asia/Tehran", method: .tehran),
        .init(name: "Karachi", latitude: 24.8607, longitude: 67.0011, timeZoneId: "Asia/Karachi", method: .karachi),
        .init(name: "Lahore", latitude: 31.5204, longitude: 74.3587, timeZoneId: "Asia/Karachi", method: .karachi),
        .init(name: "Delhi", latitude: 28.6139, longitude: 77.2090, timeZoneId: "Asia/Kolkata", method: .karachi),
        .init(name: "Dhaka", latitude: 23.8103, longitude: 90.4125, timeZoneId: "Asia/Dhaka", method: .karachi),
        .init(name: "Kuala Lumpur", latitude: 3.1390, longitude: 101.6869, timeZoneId: "Asia/Kuala_Lumpur", method: .malaysia),
        .init(name: "Singapore", latitude: 1.3521, longitude: 103.8198, timeZoneId: "Asia/Singapore", method: .singapore),
        .init(name: "Jakarta", latitude: -6.2088, longitude: 106.8456, timeZoneId: "Asia/Jakarta", method: .indonesia),
        .init(name: "Bandung", latitude: -6.9175, longitude: 107.6191, timeZoneId: "Asia/Jakarta", method: .indonesia),
        .init(name: "Surabaya", latitude: -7.2575, longitude: 112.7521, timeZoneId: "Asia/Jakarta", method: .indonesia),
        .init(name: "Makassar", latitude: -5.1477, longitude: 119.4327, timeZoneId: "Asia/Makassar", method: .indonesia),
        .init(name: "New York", latitude: 40.7128, longitude: -74.0060, timeZoneId: "America/New_York", method: .northAmerica),
        .init(name: "Chicago", latitude: 41.8781, longitude: -87.6298, timeZoneId: "America/Chicago", method: .northAmerica),
        .init(name: "Los Angeles", latitude: 34.0522, longitude: -118.2437, timeZoneId: "America/Los_Angeles", method: .northAmerica),
        .init(name: "Toronto", latitude: 43.6532, longitude: -79.3832, timeZoneId: "America/Toronto", method: .northAmerica),
        .init(name: "Montreal", latitude: 45.5019, longitude: -73.5674, timeZoneId: "America/Toronto", method: .northAmerica),
        .init(name: "Sydney", latitude: -33.8688, longitude: 151.2093, timeZoneId: "Australia/Sydney", method: .muslimWorldLeague),
    ]

    static func named(_ name: String) -> PrayerCity? { all.first { $0.name == name } }

    /// The first city in this time zone: a starting point that needs no setup.
    static func matching(timeZoneId id: String) -> PrayerCity? { all.first { $0.timeZoneId == id } }
}

// MARK: - Times of one day

struct PrayerConfig: Equatable, Sendable {
    var method: PrayerMethod
    var asr: AsrSchool = .standard
    var highLatitude: HighLatitudeRule = .angleBased
    /// The user's own offsets in minutes, to match a mosque's timetable.
    var adjustments: [Prayer: Int] = [:]
}

/// The times of one calendar day at one place. A time the sun cannot give (polar day or night) is missing.
struct PrayerDay: Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    let times: [Prayer: Date]

    func time(_ prayer: Prayer) -> Date? { times[prayer] }
}

/// The moment a reminder or a prayer comes.
struct PrayerEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case reminder, adhan }
    let prayer: Prayer
    let kind: Kind
    let at: Date
    /// The prayer's own time (the same as `at` for the adhan).
    let prayerTime: Date
}

/// The astronomy. Pure: no clock of its own, no defaults, no pill.
/// The sun's position follows the PrayTimes.org algorithm (two refinement passes);
/// times are rounded to the minute.
enum PrayerTimesEngine {
    static let kaabaLatitude = 21.422487
    static let kaabaLongitude = 39.826206
    /// Sunrise and sunset: the top of the sun on the horizon, with refraction.
    static let riseSetAngle = 0.833

    /// The times of the calendar day that contains `date` where `location` is.
    static func day(containing date: Date, location: PrayerLocation, config: PrayerConfig) -> PrayerDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        return day(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1,
                   location: location, config: config,
                   ramadan: isRamadan(noon, timeZone: location.timeZone))
    }

    /// The day after the one that contains `date`.
    static func dayAfter(_ date: Date, location: PrayerLocation, config: PrayerConfig) -> PrayerDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86_400)
        return day(containing: next.addingTimeInterval(3600), location: location, config: config)
    }

    static func isRamadan(_ date: Date, timeZone: TimeZone) -> Bool {
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = timeZone
        return hijri.component(.month, from: date) == 9
    }

    /// The times of a calendar day. The day is the one in the location's time zone.
    static func day(year: Int, month: Int, day: Int, location: PrayerLocation,
                    config: PrayerConfig, ramadan: Bool = false) -> PrayerDay {
        let hours = hoursUTC(year: year, month: month, day: day,
                             latitude: location.latitude, longitude: location.longitude,
                             config: config, ramadan: ramadan)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
        var times: [Prayer: Date] = [:]
        for (prayer, h) in hours where h.isFinite {
            // Rounded to the nearest minute, half a minute up.
            let minutes = (h * 60 + 0.5).rounded(.down)
            times[prayer] = midnight.addingTimeInterval(minutes * 60)
        }
        return PrayerDay(year: year, month: month, day: day, times: times)
    }

    /// Hours after 00:00 UTC of the calendar day, offsets included. Can be below 0 or past 24
    /// far from Greenwich. NaN when the sun never reaches the angle and no rule applies.
    static func hoursUTC(year: Int, month: Int, day: Int, latitude lat: Double, longitude lng: Double,
                         config: PrayerConfig, ramadan: Bool) -> [Prayer: Double] {
        let p = config.method.parameters
        let jDate = julian(year: year, month: month, day: day) - lng / (15 * 24)

        func midDay(_ t: Double) -> Double {
            fixHour(12 - sunPosition(jDate + t).equation)
        }
        func sunAngleTime(_ angle: Double, _ t: Double, ccw: Bool = false) -> Double {
            let decl = sunPosition(jDate + t).declination
            let noon = midDay(t)
            let cosine = (-dsin(angle) - dsin(decl) * dsin(lat)) / (dcos(decl) * dcos(lat))
            guard (-1...1).contains(cosine) else { return .nan }
            let span = darccos(cosine) / 15
            return noon + (ccw ? -span : span)
        }
        func asrTime(_ factor: Double, _ t: Double) -> Double {
            let decl = sunPosition(jDate + t).declination
            let angle = -darccot(factor + dtan(abs(lat - decl)))
            return sunAngleTime(angle, t)
        }

        // First guesses in hours, then refined with the sun at those times.
        var guess: [String: Double] = ["fajr": 5, "sunrise": 6, "dhuhr": 12, "asr": 13,
                                       "sunset": 18, "maghrib": 18, "isha": 18]
        var raw: [String: Double] = [:]
        for _ in 0..<2 {
            let t = guess.mapValues { $0 / 24 }
            let ishaAngle: Double? = { if case .angle(let a) = p.isha { return a }; return nil }()
            raw = [
                "fajr": sunAngleTime(p.fajrAngle, t["fajr"]!, ccw: true),
                "sunrise": sunAngleTime(riseSetAngle, t["sunrise"]!, ccw: true),
                "dhuhr": midDay(t["dhuhr"]!),
                "asr": asrTime(config.asr.shadowFactor, t["asr"]!),
                "sunset": sunAngleTime(riseSetAngle, t["sunset"]!),
                "maghrib": sunAngleTime(p.maghribAngle ?? riseSetAngle, t["maghrib"]!),
                "isha": ishaAngle.map { sunAngleTime($0, t["isha"]!) } ?? .nan,
            ]
            // A time the sun could not give keeps a plain guess for the next pass.
            for (key, value) in raw {
                guess[key] = value.isFinite ? value : (key == "isha" || key == "maghrib" ? 18 : 5)
            }
        }

        // To UTC.
        var h = raw.mapValues { $0 - lng / 15 }

        // Keep Fajr and Isha inside the night where the sun stays too high.
        let night = fixHour(h["sunrise"]! - h["sunset"]!)
        func keepInNight(_ time: Double, base: Double, angle: Double, ccw: Bool) -> Double {
            guard base.isFinite, night.isFinite else { return time }
            let portion = config.highLatitude.portion(angle: angle) * night
            if !time.isFinite || (ccw ? fixHour(base - time) : fixHour(time - base)) > portion {
                return base + (ccw ? -portion : portion)
            }
            return time
        }
        h["fajr"] = keepInNight(h["fajr"]!, base: h["sunrise"]!, angle: p.fajrAngle, ccw: true)
        if case .angle(let a) = p.isha {
            h["isha"] = keepInNight(h["isha"]!, base: h["sunset"]!, angle: a, ccw: false)
        }
        if let a = p.maghribAngle {
            h["maghrib"] = keepInNight(h["maghrib"]!, base: h["sunset"]!, angle: a, ccw: false)
        }
        if case .minutesAfterMaghrib(let m) = p.isha {
            h["isha"] = h["maghrib"]! + (m + (ramadan ? p.ramadanIshaExtra : 0)) / 60
        }

        var result: [Prayer: Double] = [:]
        for prayer in Prayer.allCases {
            let base = h[prayer.rawValue] ?? .nan
            let offset = (p.adjustments[prayer] ?? 0) + Double(config.adjustments[prayer] ?? 0)
            result[prayer] = base + offset / 60
        }
        return result
    }

    // MARK: - Next prayer

    /// The next of the five prayers strictly after `now`, from today's and tomorrow's times.
    static func next(after now: Date, in days: [PrayerDay]) -> (prayer: Prayer, at: Date)? {
        days.flatMap { day in Prayer.obligatory.compactMap { p in day.time(p).map { (p, $0) } } }
            .filter { $0.1 > now }
            .min { $0.1 < $1.1 }
            .map { (prayer: $0.0, at: $0.1) }
    }

    /// The prayer whose time has come and not yet passed to the next one (sunrise ends Fajr).
    static func current(at now: Date, in days: [PrayerDay]) -> (prayer: Prayer, at: Date)? {
        let all = days.flatMap { day in Prayer.allCases.compactMap { p in day.time(p).map { (p, $0) } } }
            .filter { $0.1 <= now }
            .max { $0.1 < $1.1 }
        guard let found = all, found.0.isObligatory else { return nil }
        return (prayer: found.0, at: found.1)
    }

    // MARK: - Reminders

    /// Every reminder and adhan in these days, in order. `reminderMinutes` 0 means no reminder.
    static func events(in days: [PrayerDay], reminderMinutes: Int) -> [PrayerEvent] {
        var out: [PrayerEvent] = []
        for day in days {
            for prayer in Prayer.obligatory {
                guard let time = day.time(prayer) else { continue }
                if reminderMinutes > 0 {
                    out.append(PrayerEvent(prayer: prayer, kind: .reminder,
                                           at: time.addingTimeInterval(-Double(reminderMinutes) * 60),
                                           prayerTime: time))
                }
                out.append(PrayerEvent(prayer: prayer, kind: .adhan, at: time, prayerTime: time))
            }
        }
        return out.sorted { $0.at < $1.at }
    }

    /// The events that came after `last` and by `now`, and the newest of them worth announcing.
    /// After a sleep, an event older than `staleAfter` is not announced any more.
    static func due(in events: [PrayerEvent], after last: Date, now: Date,
                    staleAfter: TimeInterval = 10 * 60) -> PrayerEvent? {
        guard let newest = events.filter({ $0.at > last && $0.at <= now }).max(by: { $0.at < $1.at }) else {
            return nil
        }
        // A reminder whose prayer has already come is no use any more.
        if newest.kind == .reminder, newest.prayerTime <= now { return nil }
        return now.timeIntervalSince(newest.at) <= staleAfter ? newest : nil
    }

    // MARK: - Qibla

    /// The direction of the Kaaba, in degrees clockwise from true north.
    static func qibla(latitude: Double, longitude: Double) -> Double {
        let dLng = kaabaLongitude - longitude
        let y = dsin(dLng)
        let x = dcos(latitude) * dtan(kaabaLatitude) - dsin(latitude) * dcos(dLng)
        return fixAngle(datan2(y, x))
    }

    /// "N", "NE", "E"… for a bearing.
    static func compassPoint(_ bearing: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((fixAngle(bearing) / 45).rounded()) % 8
        return points[index]
    }

    // MARK: - Sun

    /// Where the sun stands in the sky between sunrise and sunset, 0 to 1; nil at night.
    static func sunProgress(at now: Date, day: PrayerDay) -> Double? {
        guard let rise = day.time(.sunrise), let set = day.time(.maghrib), set > rise else { return nil }
        guard now >= rise, now <= set else { return nil }
        return now.timeIntervalSince(rise) / set.timeIntervalSince(rise)
    }

    static func julian(year: Int, month: Int, day: Int) -> Double {
        var y = Double(year), m = Double(month)
        if m <= 2 { y -= 1; m += 12 }
        let a = (y / 100).rounded(.down)
        let b = 2 - a + (a / 4).rounded(.down)
        return (365.25 * (y + 4716)).rounded(.down) + (30.6001 * (m + 1)).rounded(.down) + Double(day) + b - 1524.5
    }

    /// The sun's declination and the equation of time (hours) at a Julian date.
    static func sunPosition(_ jd: Double) -> (declination: Double, equation: Double) {
        let d = jd - 2_451_545.0
        let g = fixAngle(357.529 + 0.98560028 * d)
        let q = fixAngle(280.459 + 0.98564736 * d)
        let l = fixAngle(q + 1.915 * dsin(g) + 0.020 * dsin(2 * g))
        let e = 23.439 - 0.00000036 * d
        let ra = fixHour(datan2(dcos(e) * dsin(l), dcos(l)) / 15)
        return (darcsin(dsin(e) * dsin(l)), q / 15 - ra)
    }

    private static func dsin(_ d: Double) -> Double { sin(d * .pi / 180) }
    private static func dcos(_ d: Double) -> Double { cos(d * .pi / 180) }
    private static func dtan(_ d: Double) -> Double { tan(d * .pi / 180) }
    private static func darcsin(_ x: Double) -> Double { asin(x) * 180 / .pi }
    private static func darccos(_ x: Double) -> Double { acos(x) * 180 / .pi }
    private static func datan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180 / .pi }
    private static func darccot(_ x: Double) -> Double { atan(1 / x) * 180 / .pi }

    private static func fix(_ a: Double, _ b: Double) -> Double {
        let r = a - b * (a / b).rounded(.down)
        return r < 0 ? r + b : r
    }
    static func fixAngle(_ a: Double) -> Double { fix(a, 360) }
    static func fixHour(_ a: Double) -> Double { a.isFinite ? fix(a, 24) : a }
}

// MARK: - Stored settings

/// The prayer settings, in UserDefaults like the other integrations.
enum PrayerSettings {
    static let pillId = "integration_prayer"

    static let cityKey = "prayerCity"                 // a PrayerCities name, or "custom"
    static let customNameKey = "prayerCustomName"
    static let latitudeKey = "prayerLatitude"
    static let longitudeKey = "prayerLongitude"
    static let methodKey = "prayerMethod"             // a PrayerMethod raw value, or "" for the city's
    static let asrKey = "prayerAsr"
    static let highLatitudeKey = "prayerHighLatitude"
    static let reminderKey = "prayerReminderMinutes"
    static let pauseMusicKey = "prayerPauseMusic"
    static let adhanKey = "prayerPlayAdhan"
    static let prayedKey = "prayerPrayed"             // "2026-11-11": ["fajr", "dhuhr"]
    static func adjustmentKey(_ prayer: Prayer) -> String { "prayerAdjust.\(prayer.rawValue)" }

    static let custom = "custom"
    static let defaultReminder = 10
    static let reminderBounds = 0...60
    static let adjustmentBounds = -30...30

    static func clampReminder(_ minutes: Int) -> Int {
        min(max(minutes, reminderBounds.lowerBound), reminderBounds.upperBound)
    }

    static func clampAdjustment(_ minutes: Int) -> Int {
        min(max(minutes, adjustmentBounds.lowerBound), adjustmentBounds.upperBound)
    }

    private static var defaults: UserDefaults { .standard }

    /// The city picked in Settings, else the first city in the Mac's time zone, else none.
    static var city: PrayerCity? {
        let stored = defaults.string(forKey: cityKey) ?? ""
        if stored == custom { return nil }
        return PrayerCities.named(stored) ?? PrayerCities.matching(timeZoneId: TimeZone.current.identifier)
    }

    static var location: PrayerLocation? {
        if defaults.string(forKey: cityKey) == custom {
            guard defaults.object(forKey: latitudeKey) != nil, defaults.object(forKey: longitudeKey) != nil else { return nil }
            let name = defaults.string(forKey: customNameKey) ?? ""
            let loc = PrayerLocation(name: name,
                                     latitude: defaults.double(forKey: latitudeKey),
                                     longitude: defaults.double(forKey: longitudeKey),
                                     timeZoneId: TimeZone.current.identifier)
            return loc.isValid ? loc : nil
        }
        return city?.location
    }

    /// The method picked in Settings, else the one used where the city is.
    static var method: PrayerMethod {
        if let raw = defaults.string(forKey: methodKey), let m = PrayerMethod(rawValue: raw) { return m }
        return city?.method ?? PrayerMethod.recommended(forTimeZone: TimeZone.current.identifier)
    }

    static var config: PrayerConfig {
        var adjustments: [Prayer: Int] = [:]
        for prayer in Prayer.allCases {
            let v = clampAdjustment(defaults.integer(forKey: adjustmentKey(prayer)))
            if v != 0 { adjustments[prayer] = v }
        }
        return PrayerConfig(method: method,
                            asr: AsrSchool(rawValue: defaults.string(forKey: asrKey) ?? "") ?? .standard,
                            highLatitude: HighLatitudeRule(rawValue: defaults.string(forKey: highLatitudeKey) ?? "") ?? .angleBased,
                            adjustments: adjustments)
    }

    static var reminderMinutes: Int {
        defaults.object(forKey: reminderKey) == nil ? defaultReminder : clampReminder(defaults.integer(forKey: reminderKey))
    }

    /// On unless turned off.
    static var pauseMusic: Bool { defaults.object(forKey: pauseMusicKey) == nil ? true : defaults.bool(forKey: pauseMusicKey) }

    static var playAdhan: Bool { defaults.bool(forKey: adhanKey) }

    /// "2026-11-11" in the location's time zone: the key of the prayed list.
    static func dayKey(_ day: PrayerDay) -> String {
        String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }

    static func prayed(on day: PrayerDay) -> Set<Prayer> {
        let all = defaults.dictionary(forKey: prayedKey) as? [String: [String]] ?? [:]
        return Set((all[dayKey(day)] ?? []).compactMap(Prayer.init(rawValue:)))
    }

    /// Saves the day's list and forgets the days older than a week.
    static func setPrayed(_ prayed: Set<Prayer>, on day: PrayerDay) {
        var all = defaults.dictionary(forKey: prayedKey) as? [String: [String]] ?? [:]
        all[dayKey(day)] = Prayer.obligatory.filter(prayed.contains).map(\.rawValue)
        let keep = all.keys.sorted().suffix(7)
        all = all.filter { keep.contains($0.key) }
        defaults.set(all, forKey: prayedKey)
    }
}
