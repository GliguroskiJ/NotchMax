import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Obecné", systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label("Vzhled", systemImage: "sparkles") }
            ModulesSettings()
                .tabItem { Label("Moduly", systemImage: "square.grid.2x2") }
            CalendarSettings()
                .tabItem { Label("Kalendář", systemImage: "calendar") }
            UpdateSettings()
                .tabItem { Label("Aktualizace", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 520, height: 420)
        .preferredColorScheme(.dark)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Spouštět při přihlášení", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSLog("NotchMax login item: \(error.localizedDescription)")
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
                Picker("Zobrazit na", selection: $settings.display) {
                    ForEach(DisplayChoice.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Chování") {
                VStack(alignment: .leading) {
                    Text("Zpoždění rozbalení při najetí myší: \(settings.hoverDelay, specifier: "%.2f") s")
                    Slider(value: $settings.hoverDelay, in: 0...0.6)
                }
                Picker("Mazat odkladiště po", selection: $settings.shelfTTLHours) {
                    Text("1 hodině").tag(1)
                    Text("24 hodinách").tag(24)
                    Text("7 dnech").tag(168)
                    Text("Nikdy").tag(0)
                }
            }
            Section {
                Button("Ukončit NotchMax") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Barvy a záře") {
                Picker("Akcentní barva", selection: $settings.accent) {
                    ForEach(AccentChoice.allCases) { choice in
                        Label {
                            Text(choice.title)
                        } icon: {
                            Circle().fill(choice.color).frame(width: 10, height: 10)
                        }
                        .tag(choice)
                    }
                }
                Picker("Svítící obrys kolem notche", selection: $settings.glowStyle) {
                    ForEach(GlowStyle.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Nabíjení") {
                Toggle("Animace při zapojení nabíječky", isOn: $settings.chargingAnimation)
                Button("Vyzkoušet animaci") {
                    AppServices.shared.viewModel?.runChargeAnimation()
                }
            }
            Section {
                Text("Aplikace je záměrně jen v tmavém režimu, aby splynula s černým notchem. Prvky Liquid Glass se používají na macOS 26 a novějších, na starších systémech je náhrada ze skleněného materiálu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModulesSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Živé aktivity vedle notche") {
                Toggle("Hudba (obal + ekvalizér)", isOn: $settings.liveMusic)
                Toggle("Časovač", isOn: $settings.liveTimer)
                Toggle("Blížící se schůzka (do 10 min)", isOn: $settings.liveCalendar)
                Toggle("Nabíjení", isOn: $settings.liveBattery)
            }
            Section("Záložky v rozbaleném notchi") {
                Toggle("Kalendář", isOn: $settings.tabCalendar)
                Toggle("Odkladiště souborů", isOn: $settings.tabShelf)
                Toggle("Nástroje", isOn: $settings.tabTools)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CalendarSettings: View {
    @EnvironmentObject private var calendar: CalendarMonitor

    var body: some View {
        Form {
            Section("Přístup") {
                HStack {
                    Text("Stav")
                    Spacer()
                    Text(statusText).foregroundStyle(.secondary)
                }
                if calendar.access == .unknown {
                    Button("Povolit přístup ke kalendáři") { calendar.requestAccess() }
                }
                if calendar.access == .denied {
                    Button("Otevřít Soukromí a zabezpečení") {
                        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
                    }
                }
            }
            Section("Google Kalendář") {
                Text("Přidej Google účet v Nastavení systému → Internetové účty a zapni u něj Kalendáře. Události se pak objeví v NotchMax, bez dalšího přihlašování.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Otevřít Internetové účty") {
                    open("x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
                }
                Text("Přímé přihlášení k Googlu (OAuth) je v plánu jako další krok.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .onAppear { calendar.refreshAccess() }
    }

    private var statusText: String {
        switch calendar.access {
        case .granted: return "Povoleno"
        case .denied: return "Zamítnuto"
        case .unknown: return "Zatím nepovoleno"
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

private struct UpdateSettings: View {
    @EnvironmentObject private var updates: UpdateManager

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Verze")
                    Spacer()
                    Text(version).foregroundStyle(.secondary)
                }
                if let last = updates.lastCheckDate {
                    HStack {
                        Text("Poslední kontrola")
                        Spacer()
                        Text(last.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    }
                }
                Button("Zkontrolovat aktualizace…") { updates.checkNow() }
            }
            Section {
                Toggle("Kontrolovat automaticky", isOn: Binding(
                    get: { updates.automaticChecks },
                    set: { updates.automaticChecks = $0 }
                ))
                Text("Kontrola probíhá při startu, po probuzení Macu a jednou denně. Aktualizace se nainstaluje vždy až po tvém potvrzení.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
