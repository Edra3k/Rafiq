#if !APPSTORE
import AppKit
import CoreAudio
import IOKit.pwr_mgt

// MARK: - Audio devices: outputs, inputs, their volume and mute

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let isOutput: Bool
    let transport: UInt32

    var isHeadphones: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
            || name.lowercased().contains("airpods") || name.lowercased().contains("headphone") || name.lowercased().contains("casque")
    }
    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
}

enum AudioSystem {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func devices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        var list: [AudioDevice] = []
        for id in ids {
            let name = string(id, kAudioObjectPropertyName) ?? "?"
            let uid = string(id, kAudioDevicePropertyDeviceUID) ?? ""
            let transport = uint(id, kAudioDevicePropertyTransportType) ?? 0
            if channels(id, scope: kAudioObjectPropertyScopeOutput) > 0 {
                list.append(AudioDevice(id: id, name: name, uid: uid, isOutput: true, transport: transport))
            }
            if channels(id, scope: kAudioObjectPropertyScopeInput) > 0 {
                list.append(AudioDevice(id: id, name: name, uid: uid, isOutput: false, transport: transport))
            }
        }
        return list.filter { $0.transport != kAudioDeviceTransportTypeAggregate && $0.transport != kAudioDeviceTransportTypeVirtual }
    }

    static func defaultDevice(output: Bool) -> AudioDeviceID {
        var addr = address(output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func setDefault(_ id: AudioDeviceID, output: Bool) {
        var addr = address(output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice)
        var value = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        if output {
            var system = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &system, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        }
    }

    /// 0…1, from the device's main control or its first channel; nil when it has none.
    static func volume(_ id: AudioDeviceID, output: Bool) -> Float? {
        let scope = output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
        for element in [kAudioObjectPropertyElementMain, 1] {
            var addr = address(kAudioDevicePropertyVolumeScalar, scope, element)
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr { return value }
        }
        return nil
    }

    static func setVolume(_ id: AudioDeviceID, output: Bool, _ value: Float) {
        let scope = output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
        var value = max(0, min(1, value))
        var done = false
        var main = address(kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(id, &main) {
            done = AudioObjectSetPropertyData(id, &main, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
        }
        if !done {
            for element: UInt32 in [1, 2] {
                var addr = address(kAudioDevicePropertyVolumeScalar, scope, element)
                if AudioObjectHasProperty(id, &addr) {
                    AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
                }
            }
        }
    }

    static func isMuted(_ id: AudioDeviceID, output: Bool) -> Bool {
        var addr = address(kAudioDevicePropertyMute, output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput)
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return value != 0
    }

    @discardableResult
    static func setMuted(_ id: AudioDeviceID, output: Bool, _ muted: Bool) -> Bool {
        var addr = address(kAudioDevicePropertyMute, output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput)
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func uint(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = address(selector)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func channels(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

// MARK: - Sound: what the Son page shows, and the watchers it can turn on

@MainActor
final class SoundCenter: ObservableObject {
    static let shared = SoundCenter()
    static let headphonesKey = "sound.lowerOnUnplug"

    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var inputs: [AudioDevice] = []
    @Published private(set) var output: AudioDeviceID = 0
    @Published private(set) var input: AudioDeviceID = 0
    @Published var outputVolume: Float = 0
    @Published var inputVolume: Float = 0
    @Published private(set) var micMuted = false

    private var listening = false
    private var lastOutputWasHeadphones = false
    private var musicObserver: NSObjectProtocol?

    func refresh() {
        let all = AudioSystem.devices()
        outputs = all.filter(\.isOutput)
        inputs = all.filter { !$0.isOutput }
        output = AudioSystem.defaultDevice(output: true)
        input = AudioSystem.defaultDevice(output: false)
        outputVolume = AudioSystem.volume(output, output: true) ?? 0
        inputVolume = AudioSystem.volume(input, output: false) ?? 0
        micMuted = AudioSystem.isMuted(input, output: false) || inputVolume == 0
        lastOutputWasHeadphones = outputs.first { $0.id == output }?.isHeadphones ?? false
    }

    func choose(_ device: AudioDevice) {
        AudioSystem.setDefault(device.id, output: device.isOutput)
        refresh()
    }

    func setOutputVolume(_ v: Float) { outputVolume = v; AudioSystem.setVolume(output, output: true, v) }
    func setInputVolume(_ v: Float) { inputVolume = v; AudioSystem.setVolume(input, output: false, v); micMuted = v == 0 }

    private var savedInputVolume: Float = 0.7

    /// Mutes the microphone (the device's mute, else its input volume at zero).
    func toggleMic() {
        refresh()
        if micMuted {
            if !AudioSystem.setMuted(input, output: false, false) || AudioSystem.volume(input, output: false) == 0 {
                AudioSystem.setVolume(input, output: false, savedInputVolume)
            }
        } else {
            savedInputVolume = max(inputVolume, 0.3)
            if !AudioSystem.setMuted(input, output: false, true) { AudioSystem.setVolume(input, output: false, 0) }
        }
        refresh()
    }

    /// Called at launch and when a sound feature changes.
    func featureChanged() {
        let hub = FeatureHub.shared
        if hub.isOn(.outputSwitcher) && !listening {
            listening = true
            var addr = AudioSystem.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
                MainActor.assumeIsolated { SoundCenter.shared.outputChanged() }
            }
            refresh()
        }
        if hub.isOn(.musicBlocker) {
            if musicObserver == nil {
                musicObserver = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    guard app?.bundleIdentifier == "com.apple.Music" else { return }
                    MainActor.assumeIsolated {
                        guard FeatureHub.shared.isOn(.musicBlocker) else { return }
                        app?.forceTerminate()
                    }
                }
            }
        } else if let observer = musicObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            musicObserver = nil
        }
    }

    /// Headphones left: the speakers start low instead of at the headphones' volume.
    private func outputChanged() {
        let wasHeadphones = lastOutputWasHeadphones
        refresh()
        guard FeatureHub.shared.isOn(.outputSwitcher), UserDefaults.standard.object(forKey: Self.headphonesKey) as? Bool ?? true else { return }
        let now = outputs.first { $0.id == output }
        if wasHeadphones, now?.isBuiltIn == true, outputVolume > 0.25 { setOutputVolume(0.25) }
    }
}

// MARK: - Bluetooth off while the Mac sleeps

@MainActor
final class BluetoothSleep {
    static let shared = BluetoothSleep()
    private var observers: [NSObjectProtocol] = []
    private var turnedOff = false

    private typealias GetPower = @convention(c) () -> Int32
    private typealias SetPower = @convention(c) (Int32) -> Void
    private let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)

    private var power: Bool? {
        guard let handle, let symbol = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") else { return nil }
        return unsafeBitCast(symbol, to: GetPower.self)() != 0
    }

    private func setPower(_ on: Bool) {
        guard let handle, let symbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") else { return }
        unsafeBitCast(symbol, to: SetPower.self)(on ? 1 : 0)
    }

    func featureChanged() {
        let center = NSWorkspace.shared.notificationCenter
        if FeatureHub.shared.isOn(.bluetoothSleep) {
            guard observers.isEmpty else { return }
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { BluetoothSleep.shared.willSleep() }
            })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { BluetoothSleep.shared.didWake() }
            })
        } else {
            observers.forEach(center.removeObserver)
            observers = []
        }
    }

    private func willSleep() {
        guard power == true else { return }
        setPower(false)
        turnedOff = true
    }

    /// Back on only if Rafiq turned it off.
    private func didWake() {
        guard turnedOff else { return }
        turnedOff = false
        setPower(true)
    }
}

// MARK: - Displays: brightness (built-in) and software dimming (any display)

struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let builtIn: Bool
}

@MainActor
final class DisplayCenter: ObservableObject {
    static let shared = DisplayCenter()
    @Published private(set) var displays: [DisplayInfo] = []
    @Published var levels: [CGDirectDisplayID: Float] = [:]

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    func refresh() {
        displays = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return DisplayInfo(id: id, name: screen.localizedName, builtIn: CGDisplayIsBuiltin(id) != 0)
        }
        for d in displays where levels[d.id] == nil {
            levels[d.id] = brightness(d) ?? 1
        }
    }

    func brightness(_ d: DisplayInfo) -> Float? {
        guard d.builtIn, let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        var value: Float = 0
        return unsafeBitCast(symbol, to: GetBrightness.self)(d.id, &value) == 0 ? value : nil
    }

    /// The built-in screen through its own backlight; an external one dimmed in software.
    func set(_ d: DisplayInfo, _ value: Float) {
        levels[d.id] = value
        if d.builtIn, let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
            _ = unsafeBitCast(symbol, to: SetBrightness.self)(d.id, max(0.02, value))
        } else {
            let v = max(0.15, value)
            CGSetDisplayTransferByFormula(d.id, 0, v, 1, 0, v, 1, 0, v, 1)
        }
    }

    func resetSoftware() {
        CGDisplayRestoreColorSyncSettings()
        refresh()
    }
}
#endif
