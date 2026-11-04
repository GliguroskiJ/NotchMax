import Foundation
import Combine
import IOBluetooth

/// Sleduje připojení Bluetooth sluchátek (AirPods, Beats, …) a ukazuje v notchi
/// HUD podobný systémovému okénku AirPods – model, baterie sluchátek a pouzdra.
@MainActor
final class HeadphonesMonitor: NSObject, ObservableObject {
    static let shared = HeadphonesMonitor()

    /// Jména aktuálně připojených sluchátek.
    @Published private(set) var connected: [String] = []

    private struct Tracked: Equatable {
        var name: String
        var model: HeadphoneModel
        var left: Int?
        var right: Int?
        var caseLevel: Int?
    }

    private var started = false
    private var startDate = Date()
    private var connectNotification: IOBluetoothUserNotification?
    /// Klíč = normalizovaná adresa zařízení.
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var tracked: [String: Tracked] = [:]
    /// Zvyšuje se při každém připojení/odpojení – zahodí opožděné výsledky dotazů.
    private var generation: [String: Int] = [:]

    /// Po spuštění aplikace IOBluetooth ohlásí všechna už připojená zařízení – ty ignorujeme.
    private let startupGrace: TimeInterval = 3

    private override init() {
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        startDate = Date()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    // MARK: - IOBluetooth callbacky (chodí na hlavním run loopu)

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        guard let device else { return }
        guard Self.isHeadphones(device) else { return }

        let rawName: String = device.name ?? ""
        let name = rawName.isEmpty ? "Sluchátka" : rawName
        let rawAddress: String = device.addressString ?? ""
        let key = BluetoothProfiler.normalize(rawAddress.isEmpty ? name : rawAddress)

        if disconnectNotifications[key] == nil {
            let n: IOBluetoothUserNotification? = device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDisconnected(_:device:))
            )
            disconnectNotifications[key] = n
        }

        let gen = (generation[key] ?? 0) + 1
        generation[key] = gen

        // Opakované ohlášení téhož připojení (bez odpojení) nesmí zahodit už načtené baterie.
        let previous = tracked[key]
        let info = Tracked(
            name: name,
            model: previous?.model ?? BluetoothProfiler.guessModel(name: name, productID: nil),
            left: previous?.left, right: previous?.right, caseLevel: previous?.caseLevel
        )
        tracked[key] = info
        publishConnected()

        // Zařízení připojená už při startu aplikace nehlásíme.
        guard Date().timeIntervalSince(startDate) >= startupGrace else { return }
        guard AppSettings.shared.hudHeadphones else { return }

        show(info, connected: true)

        // Model a baterie z system_profileru: hned a znovu po ~2,5 s
        // (AirPods hlásí baterii až chvíli po připojení).
        Task { @MainActor in
            await self.refresh(key: key, gen: gen, name: name)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await self.refresh(key: key, gen: gen, name: name)
        }
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        note?.unregister()
        guard let device else { return }

        let rawName: String = device.name ?? ""
        let rawAddress: String = device.addressString ?? ""
        let key = BluetoothProfiler.normalize(rawAddress.isEmpty ? rawName : rawAddress)

        disconnectNotifications.removeValue(forKey: key)
        generation[key] = (generation[key] ?? 0) + 1
        let info = tracked.removeValue(forKey: key)
        publishConnected()

        guard info != nil || Self.isHeadphones(device) else { return }
        guard AppSettings.shared.hudHeadphones else { return }

        let name = info?.name ?? (rawName.isEmpty ? "Sluchátka" : rawName)
        let model = info?.model ?? BluetoothProfiler.guessModel(name: name, productID: nil)
        let event = HUDEvent.headphones(name: name, model: model, left: nil, right: nil,
                                        caseLevel: nil, connected: false)
        HUDCenter.shared.show(event)

        // Odpojení ukážeme jen krátce.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if HUDCenter.shared.current == event {
                HUDCenter.shared.dismiss()
            }
        }
    }

    // MARK: - Pomocné

    private func refresh(key: String, gen: Int, name: String) async {
        let devices = await BluetoothProfiler.query()
        guard generation[key] == gen, let info = tracked[key] else { return }

        let match = devices.first(where: { $0.address == key })
            ?? devices.first(where: { $0.name == name })
            ?? devices.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        guard let match else { return }

        let model = BluetoothProfiler.guessModel(name: match.name.isEmpty ? name : match.name,
                                                 productID: match.productID)
        // Zařízení s jednou baterií (AirPods Max, běžná sluchátka) → hodnota v `left`.
        let left = match.left ?? match.main
        let updated = Tracked(
            name: info.name,
            model: model,
            left: left ?? info.left,
            right: match.right ?? info.right,
            caseLevel: match.caseLevel ?? info.caseLevel
        )
        guard updated != info else { return }
        tracked[key] = updated
        publishConnected()

        guard AppSettings.shared.hudHeadphones else { return }
        // Aktualizujeme HUD, který ještě svítí. Když už zmizel, znovu ho ukážeme jen
        // tehdy, když jsme dosud baterii neznali – jinak by HUD vyskočil dvakrát.
        var isShowing = false
        if case .headphones(let shownName, _, _, _, _, true)? = HUDCenter.shared.current,
           shownName == info.name {
            isShowing = true
        }
        let hadBattery = info.left != nil || info.right != nil || info.caseLevel != nil
        guard isShowing || !hadBattery else { return }
        show(updated, connected: true)
    }

    private func show(_ info: Tracked, connected: Bool) {
        HUDCenter.shared.show(.headphones(
            name: info.name,
            model: info.model,
            left: info.left,
            right: info.right,
            caseLevel: info.caseLevel,
            connected: connected
        ))
    }

    private func publishConnected() {
        let names = tracked.values.map(\.name).sorted()
        if names != connected { connected = names }
    }

    private static func isHeadphones(_ device: IOBluetoothDevice) -> Bool {
        // kBluetoothDeviceClassMajorAudio = 0x04
        if device.deviceClassMajor == 0x04 { return true }
        let n = (device.name ?? "").lowercased()
        return n.contains("airpods") || n.contains("beats")
    }
}

// MARK: - system_profiler

/// Jedno připojené zařízení z `system_profiler SPBluetoothDataType -json`.
struct BluetoothProfilerDevice: Sendable {
    let name: String
    /// Normalizovaná adresa (malá písmena, bez oddělovačů).
    let address: String
    let productID: Int?
    let left: Int?
    let right: Int?
    let caseLevel: Int?
    let main: Int?
}

/// Pomocník pro čtení údajů o Bluetooth zařízeních (mimo hlavní vlákno).
enum BluetoothProfiler {
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    /// Spustí system_profiler na pozadí (timeout ~5 s).
    static func query() async -> [BluetoothProfilerDevice] {
        await withCheckedContinuation { (cont: CheckedContinuation<[BluetoothProfilerDevice], Never>) in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: BluetoothProfiler.run())
            }
        }
    }

    private static func run() -> [BluetoothProfilerDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let box = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        if group.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            return []
        }
        process.waitUntilExit()
        return parse(box.data)
    }

    static func parse(_ data: Data) -> [BluetoothProfilerDevice] {
        guard !data.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        var result: [BluetoothProfilerDevice] = []
        for section in sections {
            guard let list = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in list {
                for (name, value) in entry {
                    guard let props = value as? [String: Any] else { continue }
                    let address = normalize((props["device_address"] as? String) ?? "")
                    result.append(BluetoothProfilerDevice(
                        name: name,
                        address: address,
                        productID: hex(props["device_productID"]),
                        left: percent(props["device_batteryLevelLeft"]),
                        right: percent(props["device_batteryLevelRight"]),
                        caseLevel: percent(props["device_batteryLevelCase"]),
                        main: percent(props["device_batteryLevelMain"])
                    ))
                }
            }
        }
        return result
    }

    static func normalize(_ address: String) -> String {
        address.lowercased().filter { $0 != ":" && $0 != "-" && $0 != " " }
    }

    private static func hex(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        guard var s = value as? String else { return nil }
        s = s.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        return Int(s, radix: 16)
    }

    private static func percent(_ value: Any?) -> Int? {
        if let n = value as? Int { return max(0, min(100, n)) }
        guard let s = value as? String else { return nil }
        let digits = s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let n = Int(digits) else { return nil }
        return max(0, min(100, n))
    }

    /// Product ID Beats sluchátek (Apple vendor 0x004C).
    private static let beatsProductIDs: Set<Int> = [
        0x2003, 0x2005, 0x2006, 0x2009, 0x200B, 0x200C, 0x200D,
        0x2010, 0x2011, 0x2012, 0x2016, 0x2017, 0x201D, 0x2025, 0x2026
    ]

    static func guessModel(name: String, productID: Int?) -> HeadphoneModel {
        if let pid = productID {
            switch pid {
            case 0x2002, 0x200F: return .airpods
            case 0x2013, 0x2019, 0x201B: return .airpods3
            case 0x200E, 0x2014, 0x2024: return .airpodsPro
            case 0x200A, 0x201F: return .airpodsMax
            default:
                if beatsProductIDs.contains(pid) { return .beats }
            }
        }
        let n = name.lowercased()
        if n.contains("beats") { return .beats }
        if n.contains("airpods") {
            if n.contains("max") { return .airpodsMax }
            if n.contains("pro") { return .airpodsPro }
            return .airpods
        }
        return .generic
    }
}
