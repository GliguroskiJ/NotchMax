import Foundation
import Combine
import CoreAudio
import CoreMediaIO
import SwiftUI

/// Sleduje, zda běží mikrofon / kamera (jen stav „běží“, nečte se zvuk ani obraz, žádná oprávnění).
@MainActor
final class PrivacyMonitor: ObservableObject {
    static let shared = PrivacyMonitor()

    @Published private(set) var micActive = false
    @Published private(set) var cameraActive = false

    private var timer: Timer?

    private init() {
        refresh()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let mic = Self.isMicRunning()
        let cam = Self.isCameraRunning()
        // Přiřazovat jen při změně.
        if micActive != mic { micActive = mic }
        if cameraActive != cam { cameraActive = cam }
    }

    // MARK: - Mikrofon (CoreAudio)

    nonisolated private static func isMicRunning() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return false }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr
        else { return false }

        for device in devices where hasInputChannels(device) {
            var running: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddr = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceIsRunningSomewhere),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            )
            let status = AudioObjectGetPropertyData(device, &runAddr, 0, nil, &runSize, &running)
            if status == noErr && running != 0 { return true }
        }
        return false
    }

    nonisolated private static func hasInputChannels(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyStreamConfiguration),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeInput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: max(Int(size), MemoryLayout<AudioBufferList>.size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return false }

        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        var channels = 0
        for buffer in list { channels += Int(buffer.mNumberChannels) }
        return channels > 0
    }

    // MARK: - Kamera (CoreMediaIO)

    nonisolated private static func isCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0,
              size > 0 else { return false }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        let status = devices.withUnsafeMutableBytes { buf -> OSStatus in
            CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, buf.baseAddress!)
        }
        guard status == 0 else { return false }

        for device in devices {
            var running: UInt32 = 0
            var runUsed: UInt32 = 0
            var runAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            let st = CMIOObjectGetPropertyData(device, &runAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &runUsed, &running)
            if st == 0 && running != 0 { return true }
        }
        return false
    }
}

/// Malé tečky vedle notche: oranžová = mikrofon, zelená = kamera. Když nic neběží, nezobrazí se nic.
struct PrivacyDots: View {
    @ObservedObject private var monitor = PrivacyMonitor.shared

    var body: some View {
        if monitor.micActive || monitor.cameraActive {
            HStack(spacing: 4) {
                if monitor.micActive {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                }
                if monitor.cameraActive {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                }
            }
        }
    }
}
