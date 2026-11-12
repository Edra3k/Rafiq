#if !APPSTORE
import Foundation
import FluidAudio
import NaturalLanguage
import SwiftUI

// MARK: - NeuralTTS: a natural voice that runs on the Mac
//
// Supertonic 3 (through FluidAudio, the package Flow already uses), on the Neural Engine:
// 31 languages, ten voices (F1–F5, M1–M5), no account, nothing leaves the Mac. The model
// (~200 MB, FluidInference/supertonic-3-coreml on Hugging Face, OpenRAIL-M) is downloaded
// only when the user clicks Download in Settings → Voice. A sentence in a language it doesn't
// speak (Bengali, Thai, Chinese…), or any failure, falls back to the Mac voice.

@MainActor
final class NeuralTTS: ObservableObject {
    static let shared = NeuralTTS()

    enum Status: Equatable { case notDownloaded, downloading, ready, failed(String) }
    @Published private(set) var status: Status = .notDownloaded

    nonisolated static let voiceKey = "voiceNeuralVoice"
    nonisolated static let readyKey = "voiceNeuralDownloaded"
    nonisolated static var voiceName: String { UserDefaults.standard.string(forKey: voiceKey) ?? "F1" }

    /// Rafiq speaks with it: chosen in Settings and downloaded.
    nonisolated static var isActive: Bool {
        VoiceSettings.ttsEngine == "neural" && UserDefaults.standard.bool(forKey: readyKey)
    }

    private var manager: Supertonic3Manager?
    private var styles: [String: Supertonic3VoiceStyle] = [:]
    private var loading: Task<Supertonic3Manager?, Never>?

    private init() {
        if UserDefaults.standard.bool(forKey: Self.readyKey) { status = .ready }
    }

    /// Settings → Voice → Download: the model and the chosen voice, then ready.
    func download() {
        guard status != .downloading else { return }
        status = .downloading
        Task {
            do {
                let m = try await Supertonic3Manager.downloadAndCreate()
                _ = try await Supertonic3ResourceDownloader.loadVoiceStyle(Supertonic3Voice(name: Self.voiceName) ?? .f1)
                manager = m
                UserDefaults.standard.set(true, forKey: Self.readyKey)
                status = .ready
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    /// WAV audio of `text` in the chosen voice, or nil (unsupported language, not ready, error).
    func audio(for text: String, locale: Locale?) async -> Data? {
        guard Self.isActive, let language = Self.language(of: text, locale: locale) else { return nil }
        guard let manager = await loadedManager() else { return nil }
        let name = Self.voiceName
        do {
            let style: Supertonic3VoiceStyle
            if let cached = styles[name] {
                style = cached
            } else {
                style = try await Supertonic3ResourceDownloader.loadVoiceStyle(Supertonic3Voice(name: name) ?? .f1)
                styles[name] = style
            }
            let speed = Float(VoiceSettings.rate) * Supertonic3Constants.defaultSpeed / 1.1
            let started = Date()
            let out = try await manager.synthesize(text: text, language: language, style: style, speed: speed)
            appendAppLog("nb.log", String(format: "[Voice] neural %@ %@: %.1f s of speech in %.1f s",
                                          name, language, Double(out.duration), Date().timeIntervalSince(started)))
            return Self.wav(out.samples, sampleRate: Supertonic3Constants.sampleRate)
        } catch {
            appendAppLog("nb.log", "[Voice] neural failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The model, loaded once (from the cache after the first download).
    private func loadedManager() async -> Supertonic3Manager? {
        if let manager { return manager }
        if let loading { return await loading.value }
        let task = Task<Supertonic3Manager?, Never> { try? await Supertonic3Manager.downloadAndCreate() }
        loading = task
        let m = await task.value
        loading = nil
        manager = m
        return m
    }

    /// Settings changed the voice: the next sentence uses it.
    func voiceChanged() { styles.removeAll() }

    // MARK: Helpers

    /// The sentence's language if Supertonic speaks it: the locale given, else what the text is.
    nonisolated static func language(of text: String, locale: Locale?) -> String? {
        let supported = Set(Supertonic3Constants.availableLanguages)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let detected = recognizer.dominantLanguage?.rawValue.split(separator: "-").first.map(String.init)
        for candidate in [detected, locale?.language.languageCode?.identifier] {
            if let c = candidate, supported.contains(c), c != "na" { return c }
        }
        return nil
    }

    /// 16-bit PCM WAV of mono Float32 samples.
    nonisolated static func wav(_ samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        func le<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); le(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); le(UInt32(16)); le(UInt16(1)); le(UInt16(1))
        le(UInt32(sampleRate)); le(UInt32(sampleRate * 2)); le(UInt16(2)); le(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); le(UInt32(bytes))
        data.reserveCapacity(44 + bytes)
        for s in samples { le(Int16(max(-1, min(1, s)) * Float(Int16.max))) }
        return data
    }
}

/// Settings → Voice, with "Neural voice (on this Mac)" chosen: download, then pick one of the
/// five voices of the gender above, its speed, and hear it.
struct NeuralVoiceSettings: View {
    let gender: String
    let sample: () -> Void
    @ObservedObject private var neural = NeuralTTS.shared
    @AppStorage(NeuralTTS.voiceKey) private var voice = "F1"
    @AppStorage(VoiceSettings.rateKey) private var rate: Double = VoiceSettings.defaultRate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch neural.status {
            case .ready:
                let prefix = gender == "male" ? "M" : "F"
                Picker(String(localized: "voice.neural.voice"), selection: $voice) {
                    ForEach(1...5, id: \.self) { n in Text(verbatim: "\(n)").tag("\(prefix)\(n)") }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .onAppear { if !voice.hasPrefix(prefix) { voice = "\(prefix)1" } }
                .onChange(of: gender) { _, g in voice = (g == "male" ? "M" : "F") + "1" }
                .onChange(of: voice) { _, _ in NeuralTTS.shared.voiceChanged(); sample() }
                HStack(spacing: 8) {
                    Text(String(localized: "voice.tts-speed"))
                    Slider(value: $rate, in: 0.7...1.5, step: 0.05, onEditingChanged: { if !$0 { sample() } })
                        .frame(maxWidth: 180)
                    Button(String(localized: "voice.neural.listen")) { sample() }
                }
            case .downloading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "voice.neural.downloading")).font(.system(size: 12))
                }
            case .notDownloaded, .failed:
                Button(String(localized: "voice.neural.download")) { NeuralTTS.shared.download() }
                if case .failed(let why) = neural.status {
                    Text(verbatim: why).font(.system(size: 11)).foregroundColor(.red).lineLimit(2)
                }
            }
            Text(String(localized: "voice.neural.help"))
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
