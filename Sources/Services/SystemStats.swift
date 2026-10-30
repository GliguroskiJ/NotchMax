import Foundation
import Combine
import Darwin

/// Živé systémové statistiky (CPU, paměť, síť, disk). Vzorkuje jen mezi `start()` a `stop()`.
@MainActor
final class SystemStats: ObservableObject {
    static let shared = SystemStats()

    /// Počet uchovávaných vzorků historie pro sparkline.
    static let historyLength = 40

    // MARK: Publikované hodnoty
    @Published private(set) var cpu: Double = 0
    @Published private(set) var memoryUsedFraction: Double = 0
    @Published private(set) var memoryUsedGB: Double = 0
    @Published private(set) var memoryTotalGB: Double = 0
    @Published private(set) var netDownBytesPerSec: Double = 0
    @Published private(set) var netUpBytesPerSec: Double = 0
    @Published private(set) var diskFreeGB: Double = 0
    @Published private(set) var diskTotalGB: Double = 0

    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var netDownHistory: [Double] = []
    @Published private(set) var netUpHistory: [Double] = []

    // MARK: Interní stav
    private var timer: Timer?
    private var prevCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var prevNet: (down: UInt64, up: UInt64, time: TimeInterval)?

    private init() {}

    // MARK: Ovládání

    func start() {
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        // Při dalším startu se rozdíly počítají znovu od nuly (žádný falešný skok).
        prevCPUTicks = nil
        prevNet = nil
    }

    // MARK: Vzorkování

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()
        sampleDisk()
    }

    private func append(_ value: Double, to array: inout [Double]) {
        array.append(value)
        if array.count > SystemStats.historyLength {
            array.removeFirst(array.count - SystemStats.historyLength)
        }
    }

    // MARK: CPU

    private func readCPUTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3))
    }

    private func sampleCPU() {
        guard let now = readCPUTicks() else { return }
        var load: Double = cpu
        if let prev = prevCPUTicks {
            let user = now.user >= prev.user ? now.user - prev.user : 0
            let system = now.system >= prev.system ? now.system - prev.system : 0
            let idle = now.idle >= prev.idle ? now.idle - prev.idle : 0
            let nice = now.nice >= prev.nice ? now.nice - prev.nice : 0
            let busy = user + system + nice
            let total = busy + idle
            load = total > 0 ? Double(busy) / Double(total) : 0
        } else {
            load = 0
        }
        prevCPUTicks = now
        let clamped = min(max(load, 0), 1)
        cpu = clamped
        append(clamped, to: &cpuHistory)
    }

    // MARK: Paměť

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) { statsPtr in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS, total > 0 else { return }
        let pageSize = Double(getpagesize())
        let usedPages = Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        let used = min(usedPages * pageSize, total)
        let gb = 1_073_741_824.0
        memoryUsedGB = used / gb
        memoryTotalGB = total / gb
        memoryUsedFraction = min(max(used / total, 0), 1)
    }

    // MARK: Síť

    private func readNetworkTotals() -> (down: UInt64, up: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var down: UInt64 = 0
        var up: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let ifa = current.pointee
            cursor = ifa.ifa_next

            let flags = ifa.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let rawData = ifa.ifa_data else { continue }

            let name = String(cString: ifa.ifa_name)
            // Tunely a pomocná rozhraní by počítala provoz dvakrát.
            if name.hasPrefix("utun") || name.hasPrefix("awdl") || name.hasPrefix("llw") || name.hasPrefix("ap") {
                continue
            }

            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            down += UInt64(data.ifi_ibytes)
            up += UInt64(data.ifi_obytes)
        }
        return (down, up)
    }

    private func sampleNetwork() {
        guard let totals = readNetworkTotals() else { return }
        let nowTime = ProcessInfo.processInfo.systemUptime
        var downRate: Double = 0
        var upRate: Double = 0
        if let prev = prevNet {
            let dt = nowTime - prev.time
            if dt > 0 {
                let dDown = totals.down >= prev.down ? totals.down - prev.down : 0
                let dUp = totals.up >= prev.up ? totals.up - prev.up : 0
                downRate = Double(dDown) / dt
                upRate = Double(dUp) / dt
            }
        }
        prevNet = (totals.down, totals.up, nowTime)
        netDownBytesPerSec = downRate
        netUpBytesPerSec = upRate
        append(downRate, to: &netDownHistory)
        append(upRate, to: &netUpHistory)
    }

    // MARK: Disk

    private func sampleDisk() {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) else { return }
        let gb = 1_000_000_000.0
        if let total = values.volumeTotalCapacity {
            diskTotalGB = Double(total) / gb
        }
        if let free = values.volumeAvailableCapacityForImportantUsage {
            diskFreeGB = Double(free) / gb
        }
    }
}
