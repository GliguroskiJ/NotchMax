import Foundation
import IOKit.ps

/// Stav baterie přes IOKit. Událost zapojení/odpojení nabíječky spouští animaci.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var level: Int = 0
    @Published private(set) var isCharging = false
    @Published private(set) var onAC = false
    @Published private(set) var hasBattery = false
    /// Minuty do plného nabití (nil = neznámé)
    @Published private(set) var minutesToFull: Int?

    var onPlugIn: (() -> Void)?
    var onUnplug: (() -> Void)?

    private var source: CFRunLoopSource?
    private var pollTimer: Timer?

    init() {
        refresh(initial: true)
        start()
    }

    private func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }
        guard let unmanaged = IOPSNotificationCreateRunLoopSource(callback, context) else { return }
        let src = unmanaged.takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        source = src

        // Záloha: systémové notifikace o napájení se občas sloučí nebo zmeškají.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func refresh(initial: Bool = false) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }

        var found = false
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            found = true

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCap = max(desc[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let newLevel = Int((Double(current) / Double(maxCap) * 100).rounded())
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let newOnAC = state == kIOPSACPowerValue
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let ttf = desc[kIOPSTimeToFullChargeKey] as? Int

            let wasOnAC = onAC
            let newTTF = (ttf ?? -1) > 0 ? ttf : nil
            // Přiřazovat jen při změně, ať se root view zbytečně nepřekresluje.
            if level != newLevel { level = newLevel }
            if isCharging != charging { isCharging = charging }
            if onAC != newOnAC { onAC = newOnAC }
            if minutesToFull != newTTF { minutesToFull = newTTF }

            if !initial {
                if newOnAC && !wasOnAC { onPlugIn?() }
                if !newOnAC && wasOnAC { onUnplug?() }
            }
        }
        if hasBattery != found { hasBattery = found }
    }
}
