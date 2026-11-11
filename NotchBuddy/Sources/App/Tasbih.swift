import SwiftUI

// MARK: - Tasbih: the adhkar after the prayer, counted in the notch
// SubhanAllah 33, Alhamdulillah 33, Allahu akbar 34 (100 in all). Opened from the prayer
// strip's beads or the card after a prayer. A click anywhere on the card counts one; a soft
// sound marks each completed phrase. Nothing is stored: it starts again from zero each time.

@MainActor
final class TasbihCounter: ObservableObject {
    static let shared = TasbihCounter()

    struct Phrase {
        let arabic: String
        let meaning: String
        let target: Int
    }

    static var phrases: [Phrase] {
        [
            Phrase(arabic: "سُبْحَانَ ٱللَّٰهِ",
                   meaning: String(localized: "tasbih.subhanallah", defaultValue: "Glory be to God"), target: 33),
            Phrase(arabic: "ٱلْحَمْدُ لِلَّٰهِ",
                   meaning: String(localized: "tasbih.alhamdulillah", defaultValue: "Praise be to God"), target: 33),
            Phrase(arabic: "ٱللَّٰهُ أَكْبَرُ",
                   meaning: String(localized: "tasbih.allahuakbar", defaultValue: "God is the Greatest"), target: 34),
        ]
    }

    @Published private(set) var phase = 0
    @Published private(set) var count = 0

    var isDone: Bool { phase >= Self.phrases.count }
    var phrase: Phrase? { isDone ? nil : Self.phrases[phase] }
    var total: Int { Self.phrases.prefix(phase).reduce(0) { $0 + $1.target } + count }

    func open() {
        phase = 0
        count = 0
        let state = AppState.shared
        if state.mode != .expanded {
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.tasbih)
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .tasbih }
        }
    }

    func tap() {
        guard let phrase else { return }
        count += 1
        if count >= phrase.target {
            phase += 1
            count = 0
            SoundEngine.shared.play(isDone ? "finish" : "pop")
        } else {
            SoundEngine.shared.play("tick")
        }
    }

    func reset() {
        phase = 0
        count = 0
    }

    func close() {
        let state = AppState.shared
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .overview }
    }
}

struct TasbihView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var tasbih = TasbihCounter.shared

    var body: some View {
        ZStack {
            CardBackground(wash: .amber)
            HStack(spacing: 16) {
                ring
                VStack(alignment: .leading, spacing: 4) {
                    if let phrase = tasbih.phrase {
                        Text(verbatim: phrase.arabic)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(RafiqLook.gold)
                            .environment(\.layoutDirection, .rightToLeft)
                        Text(verbatim: phrase.meaning)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#9398A1"))
                        Text(verbatim: "\(tasbih.count) / \(phrase.target) · \(tasbih.total) / 100")
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundColor(Color(hex: "#6B7079"))
                    } else {
                        Text(verbatim: "تَقَبَّلَ ٱللَّٰهُ")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(RafiqLook.gold)
                        Text(String(localized: "tasbih.done", defaultValue: "100 · May God accept it from you"))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#9398A1"))
                    }
                    HStack(spacing: 8) {
                        if tasbih.isDone {
                            PrimaryButton(verbatim: String(localized: "digest.got-it", defaultValue: "Got it")) { tasbih.close() }
                        } else {
                            PrimaryButton(verbatim: String(localized: "tasbih.count", defaultValue: "Count")) { tasbih.tap() }
                        }
                        SecondaryButton(verbatim: String(localized: "tasbih.reset", defaultValue: "Start again")) { tasbih.reset() }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
        }
        .contentShape(Rectangle())
        // Anywhere on the card counts, like a bead under the thumb.
        .onTapGesture { tasbih.tap() }
    }

    private var ring: some View {
        let target = tasbih.phrase?.target ?? 1
        let progress = tasbih.isDone ? 1 : Double(tasbih.count) / Double(target)
        return ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(RafiqLook.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress)
            Text(verbatim: tasbih.isDone ? "✓" : "\(tasbih.count)")
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundColor(Color(hex: "#F5F6F8"))
        }
        .frame(width: 62, height: 62)
    }
}
