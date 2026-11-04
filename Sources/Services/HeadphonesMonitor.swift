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
        var color: HeadphoneColor?
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
        let name = rawName.isEmpty ? L("Sluchátka") : rawName
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
        let model = previous?.model ?? BluetoothProfiler.guessModel(name: name, productID: nil)
        let info = Tracked(
            name: name,
            model: model,
            color: previous?.color ?? BluetoothProfiler.cachedColor(address: key) ?? BluetoothProfiler.defaultColor(for: model),
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

        let name = info?.name ?? (rawName.isEmpty ? L("Sluchátka") : rawName)
        let model = info?.model ?? BluetoothProfiler.guessModel(name: name, productID: nil)
        let color = info?.color ?? BluetoothProfiler.defaultColor(for: model)
        let event = HUDEvent.headphones(name: name, model: model, color: color, left: nil, right: nil,
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
            color: match.color ?? info.color ?? BluetoothProfiler.defaultColor(for: model),
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
        if case .headphones(let shownName, _, _, _, _, _, true)? = HUDCenter.shared.current,
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
            color: info.color,
            left: info.left,
            right: info.right,
            caseLevel: info.caseLevel,
            connected: connected
        ))
    }

    // MARK: - Test

    /// Ukázka HUD sluchátek (tlačítko v Nastavení). Když jsou nějaká sluchátka připojená,
    /// ukáže jejich HUD (baterie se znovu načtou ze system_profileru), jinak ukázková AirPods Pro.
    func showTestAnimation() {
        if let first = tracked.min(by: { $0.key < $1.key }) {
            let key = first.key
            let info = first.value
            show(info, connected: true)
            let gen = generation[key] ?? 0
            Task { @MainActor in
                let devices = await BluetoothProfiler.query()
                guard (self.generation[key] ?? 0) == gen, let current = self.tracked[key] else { return }
                guard let match = devices.first(where: { $0.address == key })
                    ?? devices.first(where: { $0.name == current.name }) else { return }
                let model = BluetoothProfiler.guessModel(name: match.name.isEmpty ? current.name : match.name,
                                                         productID: match.productID)
                let updated = Tracked(
                    name: current.name,
                    model: model,
                    color: match.color ?? current.color ?? BluetoothProfiler.defaultColor(for: model),
                    left: (match.left ?? match.main) ?? current.left,
                    right: match.right ?? current.right,
                    caseLevel: match.caseLevel ?? current.caseLevel
                )
                self.tracked[key] = updated
                self.publishConnected()
                if updated != current { self.show(updated, connected: true) }
            }
            return
        }

        // Nic sledovaného – zkusit system_profiler (sluchátka připojená ještě před spuštěním
        // sledování), jinak ukázka.
        Task { @MainActor in
            let devices = await BluetoothProfiler.query()
            let candidate = devices.first { device in
                let model = BluetoothProfiler.guessModel(name: device.name, productID: device.productID)
                return model != .generic || device.left != nil || device.right != nil || device.caseLevel != nil
            }
            if let device = candidate {
                let model = BluetoothProfiler.guessModel(name: device.name, productID: device.productID)
                self.show(Tracked(
                    name: device.name.isEmpty ? L("Sluchátka") : device.name,
                    model: model,
                    color: device.color ?? BluetoothProfiler.defaultColor(for: model),
                    left: device.left ?? device.main,
                    right: device.right,
                    caseLevel: device.caseLevel
                ), connected: true)
            } else {
                HUDCenter.shared.show(.headphones(name: "AirPods Pro", model: .airpodsPro, color: .white,
                                                  left: 80, right: 75, caseLevel: 60, connected: true))
            }
        }
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
    /// Barva, pokud ji system_profiler / mezipaměť Bluetooth prozradí.
    let color: HeadphoneColor?
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
                    let color = colorValue(in: props) ?? cachedColor(address: address)
                    result.append(BluetoothProfilerDevice(
                        name: name,
                        address: address,
                        productID: hex(props["device_productID"]),
                        left: percent(props["device_batteryLevelLeft"]),
                        right: percent(props["device_batteryLevelRight"]),
                        caseLevel: percent(props["device_batteryLevelCase"]),
                        main: percent(props["device_batteryLevelMain"]),
                        color: color
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

    // MARK: Barva

    /// Výchozí barva podle modelu (AirPods / Pro jsou jen bílé; Max a Beats mají víc barev).
    static func defaultColor(for model: HeadphoneModel) -> HeadphoneColor? {
        switch model {
        case .airpods, .airpods3, .airpodsPro: return .white
        case .airpodsMax, .beats, .generic: return nil
        }
    }

    /// Hledá v údajích o zařízení klíč s barvou („device_color“, „Color“, „DeviceColor“, …).
    /// system_profiler ani mezipaměť Bluetooth barvu oficiálně nedokumentují – čte se jen
    /// pokud tam nějaký takový klíč je.
    static func colorValue(in props: [String: Any]) -> HeadphoneColor? {
        for (key, value) in props {
            let k = key.lowercased()
            guard k.contains("color") || k.contains("colour") else { continue }
            if let c = color(from: value) { return c }
        }
        return nil
    }

    /// Barva z mezipaměti Bluetooth (/Library/Preferences/com.apple.Bluetooth.plist → DeviceCache),
    /// pokud tam záznam zařízení nějaký klíč s barvou má.
    static func cachedColor(address: String) -> HeadphoneColor? {
        guard !address.isEmpty else { return nil }
        let cache = deviceCache()
        for (rawKey, value) in cache where normalize(rawKey) == address {
            guard let props = value as? [String: Any] else { continue }
            return colorValue(in: props)
        }
        return nil
    }

    private static func deviceCache() -> [String: Any] {
        guard let root = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.Bluetooth.plist") as? [String: Any],
              let cache = root["DeviceCache"] as? [String: Any] else { return [:] }
        return cache
    }

    /// Převede hodnotu (číselný kód nebo název) na barvu.
    /// Číselné kódy odpovídají bajtu „device color“ z Apple Continuity (proximity pairing):
    /// 0 bílá, 1 černá, 2 červená, 3 modrá, 4 růžová, 5 šedá, 6 stříbrná, 7 zlatá,
    /// 8 růžově zlatá, 9 vesmírně šedá, 10 tmavě modrá, 11 světle modrá, 12 žlutá.
    static func color(from value: Any) -> HeadphoneColor? {
        if let number = value as? NSNumber {
            return color(code: number.intValue)
        }
        guard let raw = value as? String else { return nil }
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.isEmpty { return nil }
        if s.hasPrefix("0x"), let code = Int(s.dropFirst(2), radix: 16) { return color(code: code) }
        if let code = Int(s) { return color(code: code) }
        let compact = s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        let names: [(String, HeadphoneColor)] = [
            ("spacegray", .spaceGray), ("spacegrey", .spaceGray), ("skyblue", .skyBlue), ("lightblue", .skyBlue),
            ("midnight", .midnight), ("darkblue", .midnight), ("starlight", .starlight), ("silver", .silver),
            ("white", .white), ("black", .black), ("pink", .pink), ("rosegold", .pink), ("green", .green),
            ("orange", .orange), ("purple", .purple), ("blue", .blue), ("red", .red), ("gray", .spaceGray),
            ("grey", .spaceGray), ("gold", .starlight),
        ]
        for (name, match) in names where compact.contains(name) {
            return match
        }
        return nil
    }

    private static func color(code: Int) -> HeadphoneColor? {
        switch code {
        case 0x00: return .white
        case 0x01: return .black
        case 0x02: return .red
        case 0x03: return .blue
        case 0x04: return .pink
        case 0x05: return .spaceGray
        case 0x06: return .silver
        case 0x07: return .starlight
        case 0x08: return .pink
        case 0x09: return .spaceGray
        case 0x0A: return .midnight
        case 0x0B: return .skyBlue
        case 0x0C: return .orange
        default: return nil
        }
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
