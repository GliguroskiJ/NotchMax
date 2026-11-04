import AppKit

/// Otevírání konkrétních panelů Nastavení systému.
///
/// URL schémata (macOS 13 Ventura – 26 Tahoe):
///  • Soukromí: `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_<Klíč>`
///    (Accessibility, AllFiles, Camera, Calendars, …)
///  • Starší tvar (macOS ≤ 12, na novějších často funguje jen částečně):
///    `x-apple.systempreferences:com.apple.preference.security?Privacy_<Klíč>`
///  • Oznámení: `com.apple.Notifications-Settings.extension` (dříve `com.apple.preference.notifications`)
///  • Bluetooth: `com.apple.BluetoothSettings` (dříve `com.apple.preferences.Bluetooth`)
///  • Účty: `com.apple.Internet-Accounts-Settings.extension` (dříve `com.apple.preferences.internetaccounts`)
///
/// Postup: moderní URL → starší URL → `/usr/bin/open` → samotná aplikace Nastavení systému.
/// Nakonec se Nastavení systému přenese do popředí (NotchMax je „accessory“ aplikace
/// s neaktivujícím panelem, takže by se okno jinak mohlo otevřít až za ostatními).
enum SystemSettingsLink {
    enum Pane {
        case accessibility
        case fullDiskAccess
        case camera
        case calendars
        case notifications
        case bluetooth
        case internetAccounts

        /// URL v pořadí, v jakém se zkoušejí.
        var urlStrings: [String] {
            let scheme = "x-apple.systempreferences:"
            let privacy = scheme + "com.apple.settings.PrivacySecurity.extension"
            let legacyPrivacy = scheme + "com.apple.preference.security"
            switch self {
            case .accessibility:
                return [privacy + "?Privacy_Accessibility", legacyPrivacy + "?Privacy_Accessibility"]
            case .fullDiskAccess:
                return [privacy + "?Privacy_AllFiles", legacyPrivacy + "?Privacy_AllFiles"]
            case .camera:
                return [privacy + "?Privacy_Camera", legacyPrivacy + "?Privacy_Camera"]
            case .calendars:
                return [privacy + "?Privacy_Calendars", legacyPrivacy + "?Privacy_Calendars"]
            case .notifications:
                return [scheme + "com.apple.Notifications-Settings.extension",
                        scheme + "com.apple.preference.notifications"]
            case .bluetooth:
                return [scheme + "com.apple.BluetoothSettings",
                        scheme + "com.apple.preferences.Bluetooth"]
            case .internetAccounts:
                return [scheme + "com.apple.Internet-Accounts-Settings.extension",
                        scheme + "com.apple.preferences.internetaccounts"]
            }
        }
    }

    static let settingsBundleID = "com.apple.systempreferences"
    static let settingsAppPath = "/System/Applications/System Settings.app"

    /// Otevře daný panel a přenese Nastavení systému do popředí.
    @MainActor
    static func open(_ pane: Pane) {
        let urls = pane.urlStrings.compactMap { URL(string: $0) }

        var opened = false
        for url in urls where NSWorkspace.shared.open(url) {
            opened = true
            break
        }

        if !opened, let first = urls.first {
            opened = openWithCommandLine(first)
        }

        if !opened {
            openSettingsApp()
        }

        bringSettingsToFront()
    }

    /// Záložní cesta přes `/usr/bin/open` (běží mimo sandbox, chová se jako Terminál).
    private static func openWithCommandLine(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    @MainActor
    private static func openSettingsApp() {
        let appURL = URL(fileURLWithPath: settingsAppPath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration, completionHandler: nil)
    }

    /// Nastavení systému se spouští asynchronně – zkusíme ho aktivovat několikrát.
    @MainActor
    private static func bringSettingsToFront() {
        Task { @MainActor in
            for delay: UInt64 in [250_000_000, 600_000_000, 900_000_000] {
                try? await Task.sleep(nanoseconds: delay)
                guard let app = NSRunningApplication
                    .runningApplications(withBundleIdentifier: settingsBundleID).first else { continue }
                if app.isActive { return }
                // macOS 14+: kooperativní aktivace – nejdřív aktivaci „předáme“.
                NSApp.yieldActivation(to: app)
                _ = app.activate(options: [.activateAllWindows])
            }
            // Pořád vzadu (nebo se vůbec nespustilo)? LaunchServices s `activates = true`
            // aplikaci spustí/aktivuje; běžící instance zůstane na právě otevřeném panelu.
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleID).first
            if running?.isActive != true {
                openSettingsApp()
            }
        }
    }
}
