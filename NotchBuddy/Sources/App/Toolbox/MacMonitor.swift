#if !APPSTORE
import AppKit
import Darwin
import IOKit
import IOKit.ps

// MARK: - MacMonitor: the Mac page of the Tools tab
//
// Reads the processor, memory, disk, network, battery and temperatures every two seconds, and
// only while the Mac page is on screen (start/stop from the view): at rest it reads nothing.

@MainActor
final class MacMonitor: ObservableObject {
    static let shared = MacMonitor()

    struct Proc: Identifiable, Equatable {
        let pid: pid_t
        let name: String
        let percent: Double
        var id: pid_t { pid }
    }

    struct Battery: Equatable {
        var percent: Int
        var onPower: Bool
        var health: Int?
        var cycles: Int?
        var minutesLeft: Int?
    }

    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: Double = 0
    @Published private(set) var memoryTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var memoryPressure = 1   // 1 normal, 2 warning, 4 critical
    @Published private(set) var diskFree: Double = 0
    @Published private(set) var diskTotal: Double = 0
    @Published private(set) var downRate: Double = 0
    @Published private(set) var upRate: Double = 0
    @Published private(set) var battery: Battery?
    @Published private(set) var cpuTemperature: Double?
    @Published private(set) var top: [Proc] = []
    @Published private(set) var uptime: TimeInterval = 0

    private var timer: Timer?
    private var viewers = 0
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastNet: (down: UInt64, up: UInt64, at: Date)?
    private var lastProcTimes: [pid_t: UInt64] = [:]
    private var lastProcAt: Date?

    private init() {}

    /// The Mac page appeared: read now and every two seconds.
    func start() {
        viewers += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    /// The Mac page left: stop reading.
    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    /// One reading for the voice or the brief, without the page.
    func readOnce() {
        sample()
    }

    private func sample() {
        if let t = Self.cpuTicks() {
            if let last = lastTicks, t.total > last.total {
                cpu = Double(t.busy - last.busy) / Double(t.total - last.total) * 100
                cpuHistory.append(cpu)
                if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
            }
            lastTicks = t
        }
        memoryUsed = Self.memoryUsed()
        memoryPressure = Self.pressureLevel()
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
            diskTotal = Double(values.volumeTotalCapacity ?? 0)
        }
        let now = Date()
        if let net = Self.networkBytes() {
            if let last = lastNet, now.timeIntervalSince(last.at) > 0.5, net.down >= last.down, net.up >= last.up {
                let dt = now.timeIntervalSince(last.at)
                downRate = Double(net.down - last.down) / dt
                upRate = Double(net.up - last.up) / dt
            }
            lastNet = (net.down, net.up, now)
        }
        battery = Self.readBattery()
        cpuTemperature = Thermals.cpuCelsius()
        top = topProcesses(now: now)
        uptime = ProcessInfo.processInfo.systemUptime
    }

    var diskUsedShare: Double { diskTotal > 0 ? 1 - diskFree / diskTotal : 0 }

    // MARK: Readings

    nonisolated static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    nonisolated static func memoryUsed() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = Double(sysconf(_SC_PAGESIZE))
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        return (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
    }

    nonisolated static func pressureLevel() -> Int {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return Int(level)
    }

    nonisolated static func networkBytes() -> (down: UInt64, up: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var down: UInt64 = 0, up: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let name = String(cString: entry.pointee.ifa_name)
            if let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               name.hasPrefix("en"), let data = entry.pointee.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(stats.ifi_ibytes)
                up += UInt64(stats.ifi_obytes)
            }
            cursor = entry.pointee.ifa_next
        }
        return (down, up)
    }

    nonisolated static func readBattery() -> Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            var battery = Battery(percent: current * 100 / max,
                                  onPower: desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
            if let left = desc[kIOPSTimeToEmptyKey] as? Int, left > 0 { battery.minutesLeft = left }
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                defer { IOObjectRelease(service) }
                func int(_ key: String) -> Int? {
                    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
                }
                battery.cycles = int("CycleCount")
                let data = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
                func capacity(_ key: String) -> Int? { int(key) ?? (data?[key] as? Int) }
                if let full = capacity("NominalChargeCapacity") ?? capacity("AppleRawMaxCapacity"),
                   let design = capacity("DesignCapacity"), design > 0 {
                    battery.health = min(100, full * 100 / design)
                }
            }
            return battery
        }
        return nil
    }

    /// The processes that used the processor the most since the last reading.
    private func topProcesses(now: Date) -> [Proc] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard found > 0 else { return [] }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let elapsed = lastProcAt.map { now.timeIntervalSince($0) } ?? 0
        var times: [pid_t: UInt64] = [:]
        var results: [Proc] = []
        for pid in pids.prefix(Int(found)) where pid > 0 {
            var usage = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard ok == 0 else { continue }
            let total = usage.ri_user_time + usage.ri_system_time
            times[pid] = total
            if elapsed > 0, let before = lastProcTimes[pid], total > before {
                let nanos = Double(total - before) * Double(timebase.numer) / Double(timebase.denom)
                let percent = nanos / (elapsed * 1e9) * 100
                if percent >= 1 { results.append(Proc(pid: pid, name: Self.name(of: pid), percent: percent)) }
            }
        }
        lastProcTimes = times
        lastProcAt = now
        return Array(results.sorted { $0.percent > $1.percent }.prefix(4))
    }

    nonisolated static func name(of pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName { return name }
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, 256)
        return String(cString: buffer)
    }

    // MARK: Formatting

    static func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    static func rate(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) + "/s"
    }
}

// MARK: - Temperatures (Apple silicon sensors through IOHIDEventSystem)

enum Thermals {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double

    nonisolated(unsafe) private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    /// The hottest processor die sensor, in °C; nil where the Mac does not expose one.
    static func cpuCelsius() -> Double? {
        guard let create = symbol("IOHIDEventSystemClientCreate", as: CreateClient.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatching.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServices.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyProperty.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEvent.self),
              let getFloat = symbol("IOHIDEventGetFloatValue", as: GetFloat.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return nil }
        let temperatureEvent: Int64 = 15
        var best: Double?
        for service in services {
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  name.lowercased().contains("tdie") || name.hasPrefix("pACC") || name.hasPrefix("eACC"),
                  let event = copyEvent(service, temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            let value = getFloat(event, Int32(temperatureEvent << 16))
            if value > 0, value < 130 { best = max(best ?? 0, value) }
        }
        return best
    }
}
#endif
