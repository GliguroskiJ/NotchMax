import AVFoundation
import AppKit
import Combine

// MARK: - Zrcátko (kamera)
//
// Živý náhled z kamery, aby se uživatel mohl zkontrolovat před hovorem.
// Session běží jen po dobu, kdy je zrcátko zobrazené – při zmizení se zastaví,
// aby zhasla kontrolka kamery. Spouštění/zastavování a konfigurace probíhá na
// vlastní sériové frontě (startRunning je blokující), @Published vlastnosti
// se mění jen na hlavním vlákně.

@MainActor
final class CameraMirror: ObservableObject {
    static let shared = CameraMirror()

    enum State: Equatable {
        case idle
        case requesting
        case denied
        case noCamera
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var currentDeviceID: String?
    /// Zvýší se po každé změně konfigurace session (nový vstup → nové spojení náhledu).
    @Published private(set) var configurationToken = 0

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "cz.notchmax.camera-mirror", qos: .userInitiated)
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []
    private static let deviceKey = "mirror.deviceID"

    private init() {
        let center = NotificationCenter.default
        let names = [
            NSNotification.Name("AVCaptureDeviceWasConnectedNotification"),
            NSNotification.Name("AVCaptureDeviceWasDisconnectedNotification")
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    CameraMirror.shared.devicesChanged()
                }
            }
            observers.append(token)
        }
    }

    var currentDevice: AVCaptureDevice? {
        guard let currentDeviceID else { return nil }
        return devices.first { $0.uniqueID == currentDeviceID }
    }

    // MARK: Životní cyklus

    /// Volá se při zobrazení zrcátka.
    func start() {
        wantsRunning = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            state = .requesting
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    CameraMirror.shared.handleAccess(granted: granted)
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    /// Volá se při zmizení zrcátka – zastaví session (zhasne kontrolka kamery).
    func stop() {
        wantsRunning = false
        let session = self.session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
        switch state {
        case .running, .starting, .requesting, .failed:
            state = .idle
        default:
            break
        }
    }

    func retry() {
        stop()
        start()
    }

    /// Přepne na další dostupnou kameru.
    func selectNextDevice() {
        refreshDevices()
        guard devices.count > 1 else { return }
        let index = devices.firstIndex { $0.uniqueID == currentDeviceID } ?? -1
        let next = devices[(index + 1) % devices.count]
        select(next)
    }

    func select(_ device: AVCaptureDevice) {
        guard device.uniqueID != currentDeviceID else { return }
        UserDefaults.standard.set(device.uniqueID, forKey: Self.deviceKey)
        if wantsRunning {
            if state != .running { state = .starting }
            apply(device, thenStart: true)
        } else {
            currentDeviceID = device.uniqueID
        }
    }

    // MARK: Interní

    private func handleAccess(granted: Bool) {
        guard wantsRunning else {
            if !granted { state = .denied }
            return
        }
        if granted {
            configureAndRun()
        } else {
            state = .denied
        }
    }

    private func configureAndRun() {
        refreshDevices()
        guard let device = preferredDevice() else {
            state = .noCamera
            stopSessionOnly()
            return
        }
        if state != .running { state = .starting }
        apply(device, thenStart: true)
    }

    private func apply(_ device: AVCaptureDevice, thenStart: Bool) {
        currentDeviceID = device.uniqueID
        let session = self.session
        sessionQueue.async {
            var errorText: String?
            session.beginConfiguration()
            if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
            }
            for input in session.inputs {
                session.removeInput(input)
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    errorText = L("Tuto kameru teď nelze použít.")
                }
            } catch {
                errorText = error.localizedDescription
            }
            session.commitConfiguration()
            if errorText == nil, thenStart, !session.isRunning {
                session.startRunning()
            }
            let failure = errorText
            Task { @MainActor in
                CameraMirror.shared.sessionDidConfigure(error: failure)
            }
        }
    }

    private func sessionDidConfigure(error: String?) {
        configurationToken &+= 1
        guard wantsRunning else { return }
        if let error {
            state = .failed(error)
            stopSessionOnly()
        } else {
            state = .running
        }
    }

    private func stopSessionOnly() {
        let session = self.session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func devicesChanged() {
        refreshDevices()
        guard wantsRunning else { return }
        switch state {
        case .denied, .requesting:
            return
        default:
            break
        }
        if devices.isEmpty {
            state = .noCamera
            stopSessionOnly()
        } else if currentDevice == nil || state == .noCamera {
            configureAndRun()
        }
    }

    private func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        var seen = Set<String>()
        var result: [AVCaptureDevice] = []
        for device in discovery.devices where device.isConnected {
            if seen.insert(device.uniqueID).inserted {
                result.append(device)
            }
        }
        devices = result
    }

    private func preferredDevice() -> AVCaptureDevice? {
        if let saved = UserDefaults.standard.string(forKey: Self.deviceKey),
           let device = devices.first(where: { $0.uniqueID == saved }) {
            return device
        }
        if let current = currentDevice {
            return current
        }
        if let builtIn = devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
            return builtIn
        }
        return devices.first
    }
}
