#if !APPSTORE
import AppKit
import AudioToolbox
import CoreAudio

// MARK: - Per-app volume and output (Core Audio process taps)
//
// An app the user turns down, up (to 200 %) or sends elsewhere gets a private tap that mutes it
// at the source and hands its sound to Rafiq, which plays it back on the chosen output at the
// chosen level. Apps left at 100 % on the default output are not touched at all. macOS asks once
// for System Audio Recording.

struct AudioApp: Identifiable, Equatable {
    let object: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let name: String
    var id: String { bundleID.isEmpty ? "pid:\(pid)" : bundleID }
}

/// One app routed through Rafiq: its tap, the aggregate device that plays it, the gain.
final class AppRoute: @unchecked Sendable {
    let tap: AudioObjectID
    let aggregate: AudioObjectID
    var proc: AudioDeviceIOProcID?
    var gain: Float
    let outputUID: String

    init(tap: AudioObjectID, aggregate: AudioObjectID, gain: Float, outputUID: String) {
        self.tap = tap
        self.aggregate = aggregate
        self.gain = gain
        self.outputUID = outputUID
    }
}

@MainActor
final class AppMixer: ObservableObject {
    static let shared = AppMixer()
    private static let levelsKey = "mixer.levels"
    private static let outputsKey = "mixer.outputs"

    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var levels: [String: Float] = (UserDefaults.standard.dictionary(forKey: AppMixer.levelsKey) as? [String: Float]) ?? [:]
    @Published private(set) var outputs: [String: String] = (UserDefaults.standard.dictionary(forKey: AppMixer.outputsKey) as? [String: String]) ?? [:]
    @Published private(set) var failure: String?

    private var routes: [String: AppRoute] = [:]

    func refresh() {
        var addr = AudioSystem.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return }
        let own = getpid()
        var found: [AudioApp] = []
        for id in ids {
            let pid = Self.pid(of: id)
            guard pid > 0, pid != own else { continue }
            let running = Self.uint(id, kAudioProcessPropertyIsRunningOutput) == 1
            let bundle = Self.bundleID(of: id) ?? ""
            let known = levels[bundle] != nil || outputs[bundle] != nil || routes[bundle] != nil
            guard running || known else { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName ?? (bundle.isEmpty ? MacMonitor.name(of: pid) : bundle.split(separator: ".").last.map(String.init) ?? "\(pid)")
            if found.contains(where: { $0.id == (bundle.isEmpty ? "pid:\(pid)" : bundle) }) { continue }
            found.append(AudioApp(object: id, pid: pid, bundleID: bundle, name: name))
        }
        apps = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // A process without a bundle (a command-line player) is only known by its pid: its route
        // ends with it.
        for key in routes.keys where key.hasPrefix("pid:") && !apps.contains(where: { $0.id == key }) { remove(key) }
    }

    func level(_ app: AudioApp) -> Float { levels[app.id] ?? 1 }
    func output(_ app: AudioApp) -> String? { outputs[app.id] }

    func setLevel(_ app: AudioApp, _ value: Float) {
        levels[app.id] = value
        UserDefaults.standard.set(levels.filter { !$0.key.hasPrefix("pid:") }, forKey: Self.levelsKey)
        apply(app)
    }

    func setOutput(_ app: AudioApp, uid: String?) {
        outputs[app.id] = uid
        UserDefaults.standard.set(outputs.filter { !$0.key.hasPrefix("pid:") }, forKey: Self.outputsKey)
        apply(app, rebuild: true)
    }

    func reset(_ app: AudioApp) {
        levels[app.id] = nil
        outputs[app.id] = nil
        UserDefaults.standard.set(levels, forKey: Self.levelsKey)
        UserDefaults.standard.set(outputs, forKey: Self.outputsKey)
        remove(app.id)
    }

    /// Re-applies the saved levels to the apps playing now (at launch and when the page opens).
    func restore() {
        guard FeatureHub.shared.isOn(.appMixer) else { return }
        refresh()
        for app in apps where levels[app.id] != nil || outputs[app.id] != nil { apply(app) }
    }

    func stopAll() {
        for key in routes.keys { remove(key) }
    }

    private func apply(_ app: AudioApp, rebuild: Bool = false) {
        let gain = level(app)
        let targetUID = outputs[app.id] ?? Self.defaultOutputUID()
        let needsRoute = abs(gain - 1) > 0.01 || outputs[app.id] != nil
        if let route = routes[app.id] {
            if !needsRoute { remove(app.id); return }
            if !rebuild && route.outputUID == targetUID { route.gain = gain; return }
            remove(app.id)
        }
        guard needsRoute else { return }
        do {
            routes[app.id] = try Self.makeRoute(for: app.object, outputUID: targetUID, gain: gain)
            failure = nil
        } catch {
            failure = String(localized: "mixer.failed", defaultValue: "macOS refused: allow Rafiq in Screen & System Audio Recording (System Audio Recording Only).")
        }
    }

    private func remove(_ key: String) {
        guard let route = routes.removeValue(forKey: key) else { return }
        if let proc = route.proc {
            AudioDeviceStop(route.aggregate, proc)
            AudioDeviceDestroyIOProcID(route.aggregate, proc)
        }
        AudioHardwareDestroyAggregateDevice(route.aggregate)
        AudioHardwareDestroyProcessTap(route.tap)
    }

    // MARK: Core Audio plumbing

    struct MixerError: Error {}

    nonisolated static func makeRoute(for process: AudioObjectID, outputUID: String, gain: Float) throws -> AppRoute {
        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { throw MixerError() }

        let aggregateUID = "com.edra3k.rafiq.mixer.\(UUID().uuidString)"
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Rafiq mixer",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate) == noErr else {
            AudioHardwareDestroyProcessTap(tap)
            throw MixerError()
        }
        let route = AppRoute(tap: tap, aggregate: aggregate, gain: gain, outputUID: outputUID)
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, output, _ in
            let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outList = UnsafeMutableAudioBufferListPointer(output)
            let g = route.gain
            for (index, outBuffer) in outList.enumerated() {
                guard let outData = outBuffer.mData else { continue }
                let outCount = Int(outBuffer.mDataByteSize) / MemoryLayout<Float>.size
                let out = outData.assumingMemoryBound(to: Float.self)
                guard index < inList.count, let inData = inList[index].mData else {
                    out.update(repeating: 0, count: outCount)
                    continue
                }
                let inCount = Int(inList[index].mDataByteSize) / MemoryLayout<Float>.size
                let src = inData.assumingMemoryBound(to: Float.self)
                let n = min(outCount, inCount)
                for i in 0..<n { out[i] = max(-1, min(1, src[i] * g)) }
                if outCount > n { (out + n).update(repeating: 0, count: outCount - n) }
            }
        }
        guard status == noErr, let proc else {
            AudioHardwareDestroyAggregateDevice(aggregate)
            AudioHardwareDestroyProcessTap(tap)
            throw MixerError()
        }
        route.proc = proc
        guard AudioDeviceStart(aggregate, proc) == noErr else {
            AudioDeviceDestroyIOProcID(aggregate, proc)
            AudioHardwareDestroyAggregateDevice(aggregate)
            AudioHardwareDestroyProcessTap(tap)
            throw MixerError()
        }
        return route
    }

    nonisolated static func defaultOutputUID() -> String {
        let id = AudioSystem.defaultDevice(output: true)
        var addr = AudioSystem.address(kAudioDevicePropertyDeviceUID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return (value?.takeRetainedValue() as String?) ?? ""
    }

    nonisolated private static func pid(of object: AudioObjectID) -> pid_t {
        var addr = AudioSystem.address(kAudioProcessPropertyPID)
        var value = pid_t(0)
        var size = UInt32(MemoryLayout<pid_t>.size)
        AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
        return value
    }

    nonisolated private static func bundleID(of object: AudioObjectID) -> String? {
        var addr = AudioSystem.address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    nonisolated private static func uint(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var addr = AudioSystem.address(selector)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
        return value
    }
}
#endif
