import Foundation
import IOKit

/// Stav baterie z AppleSmartBattery.
struct SensorsBatteryInfo: Sendable, Equatable {
    /// Okamžitý příkon/odběr ve wattech (vždy kladný).
    var powerWatts: Double
    /// Proud teče do baterie (nabíjí se).
    var isCharging: Bool
    /// Připojený adaptér.
    var externalConnected: Bool
    /// Zdraví baterie v % (aktuální maximální kapacita / návrhová).
    var healthPercent: Int?
    var cycleCount: Int?
}

/// Jeden vzorek senzorů (SMC, GPU, baterie, doba běhu).
struct SensorsSnapshot: Sendable {
    /// Teplota CPU v °C, `nil` = nedostupné.
    var cpuTemperature: Double?
    /// Počet ventilátorů, `nil` = SMC nedostupné.
    var fanCount: Int?
    /// Průměrné otáčky ventilátorů (RPM), `nil` = nedostupné.
    var fanRPM: Double?
    /// Vytížení GPU 0…1, `nil` = nedostupné.
    var gpuUtilization: Double?
    /// `nil` = počítač bez baterie (desktop).
    var battery: SensorsBatteryInfo?
    /// Doba od spuštění systému v sekundách.
    var uptime: TimeInterval
}

/// Čte senzory přes IOKit. Volat výhradně z jedné sériové fronty (není thread-safe).
final class SensorsSampler: @unchecked Sendable {
    private var smc: SMCClient?
    private var smcOpenAttempted = false
    /// Klíče teplot CPU; `nil` = ještě nezjištěno.
    private var temperatureKeys: [String]?

    init() {}

    func sample() -> SensorsSnapshot {
        var temperature: Double?
        var fanCount: Int?
        var fanRPM: Double?
        if let client = smcClient() {
            temperature = readCPUTemperature(client)
            fanCount = readFanCount(client)
            if let count = fanCount, count > 0 {
                fanRPM = readFanRPM(client, count: count)
            }
        }
        return SensorsSnapshot(
            cpuTemperature: temperature,
            fanCount: fanCount,
            fanRPM: fanRPM,
            gpuUtilization: SensorsSampler.readGPUUtilization(),
            battery: SensorsSampler.readBattery(),
            uptime: SensorsSampler.readUptime()
        )
    }

    private func smcClient() -> SMCClient? {
        if !smcOpenAttempted {
            smcOpenAttempted = true
            smc = SMCClient()
        }
        return smc
    }

    // MARK: Teplota CPU

    private static func isPlausibleTemperature(_ value: Double?) -> Bool {
        guard let value = value else { return false }
        return value >= 10 && value <= 120
    }

    private func readCPUTemperature(_ smc: SMCClient) -> Double? {
        if temperatureKeys == nil {
            temperatureKeys = discoverTemperatureKeys(smc)
        }
        guard let keys = temperatureKeys, !keys.isEmpty else { return nil }
        let values = keys.compactMap { smc.readValue($0) }.filter { SensorsSampler.isPlausibleTemperature($0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Intel: TC0P/TC0D/TC0E/TC0F (sp78). Apple Silicon: výčet klíčů "Tp*"/"Te*" (flt), záložně "Tf*".
    private func discoverTemperatureKeys(_ smc: SMCClient) -> [String] {
        let intelKeys = ["TC0P", "TC0D", "TC0E", "TC0F"].filter {
            SensorsSampler.isPlausibleTemperature(smc.readValue($0))
        }
        if !intelKeys.isEmpty { return intelKeys }

        let count = min(smc.keyCount(), 10_000)
        guard count > 0 else { return [] }
        var primary: [String] = []
        var fallback: [String] = []
        for index in 0..<count {
            guard let key = smc.key(at: index) else { continue }
            let isPrimary = key.hasPrefix("Tp") || key.hasPrefix("Te")
            let isFallback = key.hasPrefix("Tf")
            guard isPrimary || isFallback else { continue }
            guard smc.dataType(of: key) == "flt " else { continue }
            guard SensorsSampler.isPlausibleTemperature(smc.readValue(key)) else { continue }
            if isPrimary {
                primary.append(key)
            } else {
                fallback.append(key)
            }
        }
        return primary.isEmpty ? fallback : primary
    }

    // MARK: Ventilátory

    private func readFanCount(_ smc: SMCClient) -> Int? {
        guard let value = smc.readValue("FNum") else {
            // Některé Macy bez ventilátoru klíč FNum vůbec nemají.
            return smc.readValue("F0Ac") == nil ? 0 : 1
        }
        return max(0, Int(value))
    }

    private func readFanRPM(_ smc: SMCClient, count: Int) -> Double? {
        let speeds = (0..<min(count, 8)).compactMap { smc.readValue("F\($0)Ac") }
            .filter { $0.isFinite && $0 >= 0 && $0 < 20_000 }
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    // MARK: GPU

    static func readGPUUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
        guard result == kIOReturnSuccess, iterator != 0 else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let unmanaged = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0) else {
                continue
            }
            guard let stats = unmanaged.takeRetainedValue() as? [String: Any] else { continue }
            let raw = (stats["Device Utilization %"] as? NSNumber) ?? (stats["GPU Activity(%)"] as? NSNumber)
            guard let number = raw else { continue }
            let fraction = min(max(number.doubleValue / 100.0, 0), 1)
            best = max(best ?? 0, fraction)
        }
        return best
    }

    // MARK: Baterie

    static func readBattery() -> SensorsBatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        if let installed = props["BatteryInstalled"] as? Bool, !installed {
            return nil
        }

        func number(_ key: String) -> NSNumber? { props[key] as? NSNumber }

        let voltage = number("Voltage")?.doubleValue ?? 0
        // Amperage bývá uložená jako UInt64 s bitovým vzorem záporného čísla.
        let amperage: Double = {
            guard let n = number("InstantAmperage") ?? number("Amperage") else { return 0 }
            return Double(Int64(bitPattern: n.uint64Value))
        }()
        let watts = abs(voltage * amperage) / 1_000_000.0

        let design = number("DesignCapacity")?.doubleValue ?? 0
        let maxCapacity = number("AppleRawMaxCapacity")?.doubleValue
            ?? number("NominalChargeCapacity")?.doubleValue
            ?? 0
        var health: Int?
        if design > 0, maxCapacity > 0 {
            health = Int((min(maxCapacity / design, 1.0) * 100).rounded())
        }

        return SensorsBatteryInfo(
            powerWatts: watts.isFinite ? watts : 0,
            isCharging: amperage > 0,
            externalConnected: (props["ExternalConnected"] as? Bool) ?? false,
            healthPercent: health,
            cycleCount: number("CycleCount")?.intValue
        )
    }

    // MARK: Doba běhu

    static func readUptime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        let result = sysctl(&mib, 2, &boot, &size, nil, 0)
        guard result == 0, boot.tv_sec > 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        let bootTime = Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000.0
        return max(0, Date().timeIntervalSince1970 - bootTime)
    }
}
