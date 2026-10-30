import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Sekce

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, modules, calendar, updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Obecné"
        case .appearance: return "Vzhled"
        case .modules: return "Moduly"
        case .calendar: return "Kalendář"
        case .updates: return "Aktualizace"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "sparkles"
        case .modules: return "square.grid.2x2"
        case .calendar: return "calendar"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Skutečné frosted glass pro sidebar

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = Self.roundedMask(radius: 20)
        return view
    }

    /// Roztažitelná maska se zaoblenými rohy, aby rozmazání respektovalo tvar okna.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Kořenové okno nastavení

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var selection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)
                .frame(width: 232)

            VStack(alignment: .leading, spacing: 0) {
                Text(selection.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 32)
                    .padding(.top, 34)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(.vertical, showsIndicators: false) {
                    sectionContent
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .id(selection)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.11))
        }
        .frame(width: 900, height: 620)
        .background(VisualEffectBackground())
        .ignoresSafeArea()
        .animation(.smooth, value: selection)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selection {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .modules: ModulesSettings()
        case .calendar: CalendarSettings()
        case .updates: UpdateSettings()
        }
    }
}

// MARK: - Postranní panel

private struct SidebarGroupTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.4))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    @EnvironmentObject private var settings: AppSettings

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // místo pro semafor
            Color.clear.frame(height: 52)

            SidebarGroupTitle(title: "Obecné")
            SidebarItem(section: .general, isSelected: selection == .general) { selection = .general }
            SidebarItem(section: .appearance, isSelected: selection == .appearance) { selection = .appearance }
            SidebarItem(section: .modules, isSelected: selection == .modules) { selection = .modules }
            SidebarItem(section: .calendar, isSelected: selection == .calendar) { selection = .calendar }

            SidebarGroupTitle(title: "Aplikace")
            SidebarItem(section: .updates, isSelected: selection == .updates) { selection = .updates }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(settings.accent.color.opacity(0.2))
                    Image(systemName: "capsule.fill")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(settings.accent.color)
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("NotchMax")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("Verze \(shortVersion)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SidebarItem: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject private var settings: AppSettings
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(settings.accent.color)
                    .frame(width: 20)
                Text(section.title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Color.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.13 : (hovering ? 0.06 : 0)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
    }
}

// MARK: - Sdílené stavební prvky

private struct SettingsCard<Content: View>: View {
    var header: String?
    let content: () -> Content

    init(header: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header.uppercased())
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75)
            )
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(settings.accent.color)
        }
    }
}

private struct SettingsNote: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Obecné

private struct GeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "NotchMax \(v) (\(b))"
    }

    private var launchBinding: Binding<Bool> {
        Binding<Bool>(
            get: { launchAtLogin },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("NotchMax login item: \(error.localizedDescription)")
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                SettingsToggleRow(title: "Spouštět při přihlášení",
                                  subtitle: "NotchMax se spustí automaticky po přihlášení k Macu.",
                                  isOn: launchBinding)
                SettingsDivider()
                SettingsToggleRow(title: "Globální zkratka ⌥⌘N",
                                  subtitle: "Otevře a zavře notch z klávesnice.",
                                  isOn: $settings.hotkeyEnabled)
                SettingsDivider()
                SettingsRow(title: "Zobrazit na") {
                    Picker("", selection: $settings.display) {
                        ForEach(DisplayChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsCard(header: "Chování") {
                SettingsRow(title: "Zpoždění rozbalení",
                            subtitle: "Jak dlouho musí myš zůstat na notchi, než se rozbalí.") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.hoverDelay, in: 0...0.6)
                            .tint(settings.accent.color)
                            .frame(width: 130)
                        Text(String(format: "%.2f s", settings.hoverDelay))
                            .font(.system(size: 13.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.7))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Mazat odkladiště po") {
                    Picker("", selection: $settings.shelfTTLHours) {
                        Text("1 hodině").tag(1)
                        Text("24 hodinách").tag(24)
                        Text("7 dnech").tag(168)
                        Text("Nikdy").tag(0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            HStack {
                GlassPill(title: "Ukončit NotchMax", symbol: "power") {
                    NSApp.terminate(nil)
                }
                Spacer()
                Text(versionText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Vzhled

private struct AccentTile: View {
    let choice: AccentChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(choice.color)
                    .frame(width: 22, height: 22)
                    .shadow(color: choice.color.opacity(isSelected ? 0.6 : 0), radius: 6)
                Text(choice.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? choice.color : Color.white.opacity(0.08),
                                  lineWidth: isSelected ? 1.5 : 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct GlowPreview: View {
    let style: GlowStyle
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black)
            outline
        }
        .frame(width: 48, height: 24)
    }

    @ViewBuilder
    private var outline: some View {
        switch style {
        case .off:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18),
                              style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        case .pulse:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(color, lineWidth: 1.5)
                .shadow(color: color.opacity(0.8), radius: 4)
        case .aurora:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    AngularGradient(colors: [color, Color.purple, Color.blue, color], center: .center),
                    lineWidth: 1.5
                )
        case .minimal:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(color.opacity(0.55), lineWidth: 0.75)
        }
    }
}

private struct GlowTile: View {
    let style: GlowStyle
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                GlowPreview(style: style, color: accent)
                Text(style.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? accent : Color.white.opacity(0.08),
                                  lineWidth: isSelected ? 1.5 : 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AppearanceSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: "Akcentní barva") {
                HStack(spacing: 8) {
                    ForEach(AccentChoice.allCases) { choice in
                        AccentTile(choice: choice, isSelected: settings.accent == choice) {
                            withAnimation(.smooth(duration: 0.25)) { settings.accent = choice }
                        }
                    }
                }
                .padding(.vertical, 12)
            }

            SettingsCard(header: "Svítící obrys kolem notche") {
                HStack(spacing: 8) {
                    ForEach(GlowStyle.allCases) { style in
                        GlowTile(style: style, accent: settings.accent.color,
                                 isSelected: settings.glowStyle == style) {
                            withAnimation(.smooth(duration: 0.25)) { settings.glowStyle = style }
                        }
                    }
                }
                .padding(.vertical, 12)
            }

            SettingsCard(header: "Poloha a velikost notche") {
                SettingsRow(title: "Posun nahoru / dolů",
                            subtitle: "Doladění, aby tvar přesně seděl na fyzický notch. Kladná hodnota posune nahoru.") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.notchOffsetY, in: -12...12, step: 1)
                            .tint(settings.accent.color)
                            .frame(width: 130)
                        Text(String(format: "%+.0f px", settings.notchOffsetY))
                            .font(.system(size: 13.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.7))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Přesah pod notch",
                            subtitle: "O kolik tvar vyčnívá pod fyzický notch. 0 = přesně na jeho výšku.") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.notchOverhang, in: 0...10, step: 1)
                            .tint(settings.accent.color)
                            .frame(width: 130)
                        Text(String(format: "%.0f px", settings.notchOverhang))
                            .font(.system(size: 13.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.7))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Výchozí hodnoty") {
                    GlassPill(title: "Obnovit") {
                        settings.notchOffsetY = 2
                        settings.notchOverhang = 2
                    }
                }
            }

            SettingsCard(header: "Nabíjení") {
                SettingsToggleRow(title: "Animace při zapojení nabíječky",
                                  isOn: $settings.chargingAnimation)
                SettingsDivider()
                SettingsRow(title: "Vyzkoušet animaci") {
                    GlassPill(title: "Přehrát", symbol: "play.fill") {
                        AppServices.shared.viewModel?.runChargeAnimation()
                    }
                }
            }

            SettingsCard {
                SettingsNote(
                    symbol: "moon.fill",
                    text: "Aplikace je záměrně jen v tmavém režimu, aby splynula s černým notchem. Prvky Liquid Glass se používají na macOS 26 a novějších, na starších systémech je náhrada ze skleněného materiálu."
                )
            }
        }
    }
}

// MARK: - Moduly

private struct ModulesSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: "Živé aktivity vedle notche") {
                SettingsToggleRow(title: "Hudba", subtitle: "Obal alba a ekvalizér.",
                                  isOn: $settings.liveMusic)
                SettingsDivider()
                SettingsToggleRow(title: "Časovač", isOn: $settings.liveTimer)
                SettingsDivider()
                SettingsToggleRow(title: "Blížící se schůzka", subtitle: "Zobrazí se 10 minut předem.",
                                  isOn: $settings.liveCalendar)
                SettingsDivider()
                SettingsToggleRow(title: "Nabíjení", isOn: $settings.liveBattery)
            }

            SettingsCard(header: "Záložky v rozbaleném notchi") {
                SettingsToggleRow(title: "Kalendář", isOn: $settings.tabCalendar)
                SettingsDivider()
                SettingsToggleRow(title: "Odkladiště souborů", isOn: $settings.tabShelf)
                SettingsDivider()
                SettingsToggleRow(title: "Nástroje", subtitle: "Časovač, Zkratky a rychlé poznámky.", isOn: $settings.tabTools)
                SettingsDivider()
                SettingsToggleRow(title: "Systém", subtitle: "Statistiky CPU, paměti, sítě a počasí.", isOn: $settings.tabSystem)
            }
        }
    }
}

// MARK: - Kalendář

private struct CalendarSettings: View {
    @EnvironmentObject private var calendar: CalendarMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: "Přístup") {
                SettingsRow(title: "Stav") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
                if calendar.access == .unknown {
                    SettingsDivider()
                    SettingsRow(title: "Přístup ke kalendáři") {
                        GlassPill(title: "Povolit", symbol: "checkmark") {
                            calendar.requestAccess()
                        }
                    }
                }
                if calendar.access == .denied {
                    SettingsDivider()
                    SettingsRow(title: "Soukromí a zabezpečení",
                                subtitle: "Přístup ke kalendáři povol v Nastavení systému.") {
                        GlassPill(title: "Otevřít", symbol: "arrow.up.forward") {
                            openSystemURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
                        }
                    }
                }
            }

            SettingsCard(header: "Google Kalendář") {
                SettingsRow(title: "Internetové účty",
                            subtitle: "Přidej Google účet v Nastavení systému → Internetové účty a zapni u něj Kalendáře. Události se pak objeví v NotchMax, bez dalšího přihlašování.") {
                    GlassPill(title: "Otevřít", symbol: "arrow.up.forward") {
                        openSystemURL("x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
                    }
                }
                SettingsDivider()
                SettingsNote(symbol: "clock",
                             text: "Přímé přihlášení k Googlu (OAuth) je v plánu jako další krok.")
            }
        }
        .onAppear { calendar.refreshAccess() }
    }

    private var statusText: String {
        switch calendar.access {
        case .granted: return "Povoleno"
        case .denied: return "Zamítnuto"
        case .unknown: return "Zatím nepovoleno"
        }
    }

    private var statusColor: Color {
        switch calendar.access {
        case .granted: return Color.green
        case .denied: return Color.red
        case .unknown: return Color.orange
        }
    }

    private func openSystemURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Aktualizace

private struct UpdateSettings: View {
    @EnvironmentObject private var updates: UpdateManager
    @EnvironmentObject private var settings: AppSettings

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var autoBinding: Binding<Bool> {
        Binding<Bool>(
            get: { updates.automaticChecks },
            set: { updates.automaticChecks = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: "Verze") {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(settings.accent.color.opacity(0.18))
                        Image(systemName: "capsule.fill")
                            .font(.system(size: 19.5, weight: .bold))
                            .foregroundStyle(settings.accent.color)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("NotchMax \(shortVersion)")
                            .font(.system(size: 16.5, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Text("Sestavení \(buildNumber)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    Spacer(minLength: 8)
                    GlassPill(title: "Zkontrolovat", symbol: "arrow.clockwise") {
                        updates.checkNow()
                    }
                }
                .padding(.vertical, 14)
                SettingsDivider()
                SettingsRow(title: "Poslední kontrola") {
                    Text(lastCheckText)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }

            SettingsCard(header: "Automatické kontroly") {
                SettingsToggleRow(
                    title: "Kontrolovat automaticky",
                    subtitle: "Kontrola probíhá při startu, po probuzení Macu a jednou denně. Aktualizace se nainstaluje vždy až po tvém potvrzení.",
                    isOn: autoBinding
                )
            }
        }
    }

    private var lastCheckText: String {
        if let last = updates.lastCheckDate {
            return last.formatted(date: .abbreviated, time: .shortened)
        }
        return "Zatím neproběhla"
    }
}
