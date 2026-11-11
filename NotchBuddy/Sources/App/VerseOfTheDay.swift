import Foundation

// MARK: - Verse of the day
// One short verse a day, from a list kept in the app (nothing is fetched), shown the first
// time the island opens on its home view that day, from 4 a.m. It never holds the island
// open: it goes away with it, or with "Got it". Settings → General → Rafiq watches.

struct Verse: Sendable {
    let arabic: String
    let reference: String
    let en: String
    let fr: String
}

@MainActor
enum VerseOfTheDay {
    static let enabledKey = "verseOfTheDay"
    private static let lastDayKey = "verseOfTheDayLastDay"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    static let verses: [Verse] = [
        Verse(arabic: "إِنَّ مَعَ ٱلْعُسْرِ يُسْرًا", reference: "Ash-Sharh 94:6",
              en: "Indeed, with hardship comes ease.", fr: "Certes, avec la difficulté vient la facilité."),
        Verse(arabic: "لَا يُكَلِّفُ ٱللَّهُ نَفْسًا إِلَّا وُسْعَهَا", reference: "Al-Baqarah 2:286",
              en: "God does not burden a soul beyond what it can bear.", fr: "Dieu n'impose à aucune âme une charge au-delà de sa capacité."),
        Verse(arabic: "أَلَا بِذِكْرِ ٱللَّهِ تَطْمَئِنُّ ٱلْقُلُوبُ", reference: "Ar-Ra'd 13:28",
              en: "Surely in the remembrance of God do hearts find rest.", fr: "C'est par le rappel de Dieu que les cœurs s'apaisent."),
        Verse(arabic: "فَٱذْكُرُونِىٓ أَذْكُرْكُمْ", reference: "Al-Baqarah 2:152",
              en: "So remember Me; I will remember you.", fr: "Souvenez-vous de Moi, Je Me souviendrai de vous."),
        Verse(arabic: "وَقُل رَّبِّ زِدْنِى عِلْمًا", reference: "Ta-Ha 20:114",
              en: "And say: My Lord, increase me in knowledge.", fr: "Et dis : Seigneur, accrois mon savoir."),
        Verse(arabic: "وَمَن يَتَوَكَّلْ عَلَى ٱللَّهِ فَهُوَ حَسْبُهُۥٓ", reference: "At-Talaq 65:3",
              en: "Whoever puts their trust in God, He is enough for them.", fr: "Quiconque place sa confiance en Dieu, Il lui suffit."),
        Verse(arabic: "إِنَّ ٱللَّهَ مَعَ ٱلصَّٰبِرِينَ", reference: "Al-Baqarah 2:153",
              en: "Indeed, God is with the patient.", fr: "Dieu est avec ceux qui patientent."),
        Verse(arabic: "لَا تَقْنَطُوا۟ مِن رَّحْمَةِ ٱللَّهِ", reference: "Az-Zumar 39:53",
              en: "Do not despair of the mercy of God.", fr: "Ne désespérez pas de la miséricorde de Dieu."),
        Verse(arabic: "فَإِذَا عَزَمْتَ فَتَوَكَّلْ عَلَى ٱللَّهِ", reference: "Al Imran 3:159",
              en: "Once you have decided, put your trust in God.", fr: "Une fois décidé, place ta confiance en Dieu."),
        Verse(arabic: "إِنَّ أَكْرَمَكُمْ عِندَ ٱللَّهِ أَتْقَىٰكُمْ", reference: "Al-Hujurat 49:13",
              en: "The most noble of you before God is the most mindful of Him.", fr: "Le plus noble d'entre vous auprès de Dieu est le plus pieux."),
        Verse(arabic: "رَّبِّ ٱرْحَمْهُمَا كَمَا رَبَّيَانِى صَغِيرًا", reference: "Al-Isra 17:24",
              en: "My Lord, have mercy on them as they raised me when I was small.", fr: "Seigneur, fais-leur miséricorde comme ils m'ont élevé tout petit."),
        Verse(arabic: "وَلَسَوْفَ يُعْطِيكَ رَبُّكَ فَتَرْضَىٰٓ", reference: "Ad-Duha 93:5",
              en: "Your Lord will give to you, and you will be content.", fr: "Ton Seigneur te donnera, et tu seras satisfait."),
        Verse(arabic: "وَأَن لَّيْسَ لِلْإِنسَٰنِ إِلَّا مَا سَعَىٰ", reference: "An-Najm 53:39",
              en: "A person has only what they strive for.", fr: "L'homme n'obtient que le fruit de ses efforts."),
        Verse(arabic: "رَبِّ إِنِّى لِمَآ أَنزَلْتَ إِلَىَّ مِنْ خَيْرٍ فَقِيرٌ", reference: "Al-Qasas 28:24",
              en: "My Lord, I am in need of whatever good You send down to me.", fr: "Seigneur, j'ai besoin du bien que Tu feras descendre vers moi."),
        Verse(arabic: "وَإِذَا سَأَلَكَ عِبَادِى عَنِّى فَإِنِّى قَرِيبٌ", reference: "Al-Baqarah 2:186",
              en: "When My servants ask you about Me, I am near.", fr: "Quand Mes serviteurs t'interrogent sur Moi, Je suis tout proche."),
        Verse(arabic: "إِنَّ ٱللَّهَ مَعَ ٱلَّذِينَ ٱتَّقَوا۟ وَّٱلَّذِينَ هُم مُّحْسِنُونَ", reference: "An-Nahl 16:128",
              en: "God is with those who are mindful of Him and who do good.", fr: "Dieu est avec ceux qui Le craignent et qui font le bien."),
        Verse(arabic: "فَبِأَىِّ ءَالَآءِ رَبِّكُمَا تُكَذِّبَانِ", reference: "Ar-Rahman 55:13",
              en: "So which of the favours of your Lord would you deny?", fr: "Lequel donc des bienfaits de votre Seigneur nierez-vous ?"),
        Verse(arabic: "وَعِبَادُ ٱلرَّحْمَٰنِ ٱلَّذِينَ يَمْشُونَ عَلَى ٱلْأَرْضِ هَوْنًا", reference: "Al-Furqan 25:63",
              en: "The servants of the Most Merciful walk humbly on the earth.", fr: "Les serviteurs du Tout Miséricordieux marchent humblement sur terre."),
        Verse(arabic: "يُرِيدُ ٱللَّهُ أَن يُخَفِّفَ عَنكُمْ", reference: "An-Nisa 4:28",
              en: "God wants to lighten your burden.", fr: "Dieu veut vous alléger."),
        Verse(arabic: "رَبَّنَآ ءَاتِنَا فِى ٱلدُّنْيَا حَسَنَةً وَفِى ٱلْءَاخِرَةِ حَسَنَةً", reference: "Al-Baqarah 2:201",
              en: "Our Lord, give us good in this world and good in the Hereafter.", fr: "Seigneur, accorde-nous une belle part ici-bas et une belle part dans l'au-delà."),
    ]

    static func verse(on date: Date) -> Verse {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return verses[day % verses.count]
    }

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
        show(verse(on: now))
    }

    static func show(_ v: Verse) {
        let french = Locale.preferredLanguages.first?.hasPrefix("fr") == true
        DigestCenter.shared.show(Digest(
            kind: .verse,
            title: v.arabic,
            subtitle: french ? v.fr : v.en,
            lines: [v.reference]
        ))
    }
}
