import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics
import Darwin

/// Přímé ovládání systémové hlasitosti, jasu displeje a podsvícení klávesnice.
/// Používá CoreAudio a (pro jas) soukromé frameworky DisplayServices / CoreBrightness
/// načtené dynamicky – pokud nejsou k dispozici, funkce vrací nil/false a volající
/// nechá událost projít systému.
enum SystemControls {

    // MARK: - Hlasitost (CoreAudio)

    /// Aktuální výstupní zařízení.
    static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    private static func outputAddress(_ selector: AudioObjectPropertySelector,
                                      element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: element)
    }

    private static func hasProperty(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Bool {
        var addr = address
        return AudioObjectHasProperty(device, &addr)
    }

    private static func isSettable(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Bool {
        var addr = address
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &addr, &settable) == noErr else { return false }
        return settable.boolValue
    }

    private static func getFloat(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Float32? {
        var addr = address
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func setFloat(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress, _ value: Float32) -> Bool {
        var addr = address
        var v = value
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &addr, 0, nil, size, &v) == noErr
    }

    /// Kanály, přes které se dá nastavit hlasitost, když zařízení nemá „virtual main volume“.
    private static func settableChannels(_ device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        [1, 2].filter { isSettable(device, outputAddress(kAudioDevicePropertyVolumeScalar, element: $0)) }
    }

    private static func readVolume(_ device: AudioDeviceID) -> Float32? {
        if let v = getFloat(device, outputAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)) {
            return v
        }
        if let v = getFloat(device, outputAddress(kAudioDevicePropertyVolumeScalar)) {
            return v
        }
        let values = [AudioObjectPropertyElement(1), 2].compactMap {
            getFloat(device, outputAddress(kAudioDevicePropertyVolumeScalar, element: $0))
        }
        guard !values.isEmpty else { return nil }
        return values.max()
    }

    private static func readMuted(_ device: AudioDeviceID) -> Bool {
        var addr = outputAddress(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    /// Lze hlasitost aktuálního zařízení měnit? (HDMI/DisplayPort výstupy často ne.)
    static func canSetOutputVolume() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        if isSettable(device, outputAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)) { return true }
        if isSettable(device, outputAddress(kAudioDevicePropertyVolumeScalar)) { return true }
        return !settableChannels(device).isEmpty
    }

    /// Hlasitost 0…1 a stav ztlumení.
    static func outputVolume() -> (level: Double, muted: Bool)? {
        guard let device = defaultOutputDevice(), let v = readVolume(device) else { return nil }
        return (Double(v), readMuted(device))
    }

    @discardableResult
    static func setOutputVolume(_ level: Double) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        let value = Float32(min(max(level, 0), 1))
        let mainAddr = outputAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        if isSettable(device, mainAddr) {
            return setFloat(device, mainAddr, value)
        }
        let scalarMain = outputAddress(kAudioDevicePropertyVolumeScalar)
        if isSettable(device, scalarMain) {
            return setFloat(device, scalarMain, value)
        }
        let channels = settableChannels(device)
        guard !channels.isEmpty else { return false }
        var ok = true
        for ch in channels {
            ok = setFloat(device, outputAddress(kAudioDevicePropertyVolumeScalar, element: ch), value) && ok
        }
        return ok
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        let addr = outputAddress(kAudioDevicePropertyMute)
        guard isSettable(device, addr) else { return false }
        var a = addr
        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &a, 0, nil, size, &value) == noErr
    }

    /// Změní hlasitost o `steps` kroků velikosti `step` (zarovná na mřížku kroků).
    /// Při zesilování automaticky zruší ztlumení. Vrací nový stav, nebo nil při neúspěchu.
    static func adjustVolume(steps: Int, step: Double) -> (level: Double, muted: Bool)? {
        guard let device = defaultOutputDevice(), canSetOutputVolume(),
              let current = readVolume(device) else { return nil }
        let newLevel = steppedValue(Double(current), steps: steps, step: step)
        guard setOutputVolume(newLevel) else { return nil }
        var muted = readMuted(device)
        if steps > 0, muted, newLevel > 0 {
            if setMuted(false) { muted = false }
        }
        let level = Double(readVolume(device) ?? Float32(newLevel))
        return (level, muted || level <= 0.0001)
    }

    /// Přepne ztlumení. Vrací nový stav, nebo nil při neúspěchu.
    static func toggleMute() -> (level: Double, muted: Bool)? {
        guard let device = defaultOutputDevice() else { return nil }
        let wasMuted = readMuted(device)
        guard setMuted(!wasMuted) else { return nil }
        let level = Double(readVolume(device) ?? 0)
        return (level, !wasMuted)
    }

    // MARK: - Jas displeje (DisplayServices, soukromé)

    private typealias DSGetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias DSBrightnessChanged = @convention(c) (CGDirectDisplayID, Double) -> Void

    private static let displayServicesHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static let dsGetBrightness: DSGetBrightness? = {
        guard let h = displayServicesHandle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: DSGetBrightness.self)
    }()

    private static let dsSetBrightness: DSSetBrightness? = {
        guard let h = displayServicesHandle, let sym = dlsym(h, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: DSSetBrightness.self)
    }()

    private static let dsBrightnessChanged: DSBrightnessChanged? = {
        guard let h = displayServicesHandle, let sym = dlsym(h, "DisplayServicesBrightnessChanged") else { return nil }
        return unsafeBitCast(sym, to: DSBrightnessChanged.self)
    }()

    /// Vestavěný displej (je-li online), jinak hlavní displej.
    static func brightnessDisplayID() -> CGDirectDisplayID {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return CGMainDisplayID() }
        let capacity = count
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
        guard CGGetOnlineDisplayList(capacity, &displays, &count) == .success else { return CGMainDisplayID() }
        for id in displays.prefix(Int(min(count, capacity))) where CGDisplayIsBuiltin(id) != 0 {
            // Vestavěný displej při zavřeném víku je „online“, ale neaktivní.
            if CGDisplayIsActive(id) != 0 { return id }
        }
        return CGMainDisplayID()
    }

    /// Jas 0…1, nil pokud displej jas přes DisplayServices nepodporuje.
    static func displayBrightness() -> Double? {
        guard let get = dsGetBrightness else { return nil }
        var value: Float = 0
        guard get(brightnessDisplayID(), &value) == 0 else { return nil }
        return Double(value)
    }

    @discardableResult
    static func setDisplayBrightness(_ level: Double) -> Bool {
        guard let set = dsSetBrightness else { return false }
        let id = brightnessDisplayID()
        let value = min(max(level, 0), 1)
        guard set(id, Float(value)) == 0 else { return false }
        dsBrightnessChanged?(id, value)
        return true
    }

    /// Změní jas o `steps` kroků. Vrací nový jas, nebo nil při neúspěchu.
    static func adjustDisplayBrightness(steps: Int, step: Double) -> Double? {
        guard dsSetBrightness != nil, let current = displayBrightness() else { return nil }
        let newLevel = steppedValue(current, steps: steps, step: step)
        guard setDisplayBrightness(newLevel) else { return nil }
        return displayBrightness() ?? newLevel
    }

    // MARK: - Podsvícení klávesnice (CoreBrightness, soukromé)

    private typealias KBCopyIDs = @convention(c) (AnyObject, Selector) -> AnyObject?
    private typealias KBGetBrightness = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias KBSetBrightness = @convention(c) (AnyObject, Selector, Float, UInt64) -> ObjCBool

    private static let coreBrightnessHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)

    private static let keyboardClient: NSObject? = {
        guard coreBrightnessHandle != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()

    private static let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
    private static let idsSelector = NSSelectorFromString("copyKeyboardBackLightIDs")

    /// ID klávesnice s podsvícením (první nalezená).
    private static let keyboardID: UInt64? = {
        guard let client = keyboardClient else { return nil }
        guard client.responds(to: idsSelector) else {
            // Starší/novější varianta bez seznamu – vestavěná klávesnice mívá ID 1.
            return 1
        }
        let imp = client.method(for: idsSelector)
        guard let imp else { return nil }
        let fn = unsafeBitCast(imp, to: KBCopyIDs.self)
        // Metoda „copy…“ vrací +1; Swift výsledek bere jako +0 → nejhůř jednorázový drobný leak.
        guard let array = fn(client, idsSelector) as? NSArray else { return nil }
        for item in array {
            if let n = item as? NSNumber { return n.uint64Value }
        }
        return nil
    }()

    /// Podsvícení klávesnice 0…1, nil pokud není k dispozici.
    static func keyboardBrightness() -> Double? {
        guard let client = keyboardClient, let kb = keyboardID,
              client.responds(to: getSelector),
              let imp = client.method(for: getSelector) else { return nil }
        let fn = unsafeBitCast(imp, to: KBGetBrightness.self)
        let value = fn(client, getSelector, kb)
        guard value.isFinite else { return nil }
        return Double(min(max(value, 0), 1))
    }

    @discardableResult
    static func setKeyboardBrightness(_ level: Double) -> Bool {
        guard let client = keyboardClient, let kb = keyboardID,
              client.responds(to: setSelector),
              let imp = client.method(for: setSelector) else { return false }
        let fn = unsafeBitCast(imp, to: KBSetBrightness.self)
        return fn(client, setSelector, Float(min(max(level, 0), 1)), kb).boolValue
    }

    /// Změní podsvícení klávesnice o `steps` kroků. Vrací novou úroveň, nebo nil.
    static func adjustKeyboardBrightness(steps: Int, step: Double) -> Double? {
        guard let current = keyboardBrightness() else { return nil }
        let newLevel = steppedValue(current, steps: steps, step: step)
        guard setKeyboardBrightness(newLevel) else { return nil }
        return newLevel
    }

    // MARK: - Pomocné

    /// Zarovná hodnotu na mřížku kroků a posune o `steps`.
    private static func steppedValue(_ current: Double, steps: Int, step: Double) -> Double {
        guard step > 0 else { return current }
        let index = (current / step).rounded()
        return min(max((index + Double(steps)) * step, 0), 1)
    }
}
