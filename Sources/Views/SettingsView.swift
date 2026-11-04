import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Sekce

/// Sekce okna nastavení. Raw value slouží k navigaci zvenku
/// (`openNotchMaxSettings(section: "calendar")`) – hodnoty neměnit.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, notch, panel, focus, calendar, permissions, agents, updates

    var id: String { rawValue }

    /// Navigace podle textového klíče; přijímá i klíče dřívějších sekcí.
    init?(navigationKey: String) {
        if let section = SettingsSection(rawValue: navigationKey) {
            self = section
            return
        }
        switch navigationKey {
        case "activities", "hud": self = .notch
        case "modules", "tabs": self = .panel
        case "timer": self = .focus
        case "privacy", "notifications": self = .permissions
        case "claude": self = .agents
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .general: return L("Obecné")
        case .appearance: return L("Vzhled")
        case .notch: return L("Notch")
        case .panel: return L("Panel")
        case .focus: return L("Časovač a soustředění")
        case .calendar: return L("Kalendář")
        case .permissions: return L("Oprávnění")
        case .agents: return L("Agenti")
        case .updates: return L("Aktualizace")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .notch: return "rectangle.topthird.inset.filled"
        case .panel: return "square.grid.2x2"
        case .focus: return "timer"
        case .calendar: return "calendar"
        case .permissions: return "lock.shield"
        case .agents: return "sparkles"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }
}

/// Přepne otevřené okno nastavení na danou sekci.
@MainActor
func showSettingsSection(_ section: SettingsSection) {
    SettingsNavigator.shared.requestedSection = section.rawValue
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
    @ObservedObject private var navigator = SettingsNavigator.shared

    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init() {}

    private func applyRequestedSection() {
        guard let raw = navigator.requestedSection else { return }
        if let section = SettingsSection(navigationKey: raw) { selection = section }
        navigator.requestedSection = nil
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)
                .frame(width: 232)

            VStack(alignment: .leading, spacing: 0) {
                Text(selection.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
        // Změna jazyka: celý obsah okna se sestaví znovu, aby se přeložily všechny texty.
        .id(settings.language)
        .frame(width: 900, height: 620)
        .background(VisualEffectBackground())
        .onAppear {
            applyRequestedSection()
            PermissionCenter.shared.refresh()
        }
        .onReceive(navigator.$requestedSection) { value in
            if value != nil { DispatchQueue.main.async { applyRequestedSection() } }
        }
        .onReceive(permissionTimer) { _ in
            // Stav oprávnění kontrolovat jen při otevřeném okně.
            if SettingsWindowController.shared.isVisible { PermissionCenter.shared.refresh() }
        }
        .ignoresSafeArea()
        .animation(.smooth, value: selection)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selection {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .notch: NotchSettings()
        case .panel: PanelSettings()
        case .focus: FocusSettingsSection()
        case .calendar: CalendarSettings()
        case .permissions: PermissionsSettingsSection()
        case .agents: ClaudeSettingsSection()
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

    init(selection: Binding<SettingsSection>) {
        self._selection = selection
    }

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        SidebarItem(section: section, isSelected: selection == section) { selection = section }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // místo pro semafor
            Color.clear.frame(height: 52)

            sidebarItem(.general)
            sidebarItem(.appearance)

            SidebarGroupTitle(title: L("Funkce"))
            sidebarItem(.notch)
            sidebarItem(.panel)
            sidebarItem(.focus)
            sidebarItem(.calendar)
            sidebarItem(.agents)

            SidebarGroupTitle(title: L("Aplikace"))
            sidebarItem(.permissions)
            sidebarItem(.updates)

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
                    Text(L("Verze %@", shortVersion))
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
    @ObservedObject private var permissions = PermissionCenter.shared
    @State private var hovering = false

    init(section: SettingsSection, isSelected: Bool, action: @escaping () -> Void) {
        self.section = section
        self.isSelected = isSelected
        self.action = action
    }

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
                    .lineLimit(1)
                Spacer(minLength: 0)
                if section == .permissions && permissions.missingCount > 0 {
                    Text("\(permissions.missingCount)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Color.orange))
                        .help(L("Chybějící oprávnění"))
                }
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

struct SettingsCard<Content: View>: View {
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

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }
}

struct SettingsRow<Trailing: View>: View {
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

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    @EnvironmentObject private var settings: AppSettings

    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(settings.accent.color)
        }
    }
}

/// Přepínač záložky v rozbaleném notchi – hlídá limit 5 záložek (Domů + 4 volitelné).
struct TabToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    @EnvironmentObject private var settings: AppSettings

    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    private var isLocked: Bool { !isOn && !settings.canEnableMoreTabs }

    var body: some View {
        SettingsRow(title: title, subtitle: isLocked ? AppSettings.tabLimitNote : subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(settings.accent.color)
                .disabled(isLocked)
        }
        .opacity(isLocked ? 0.6 : 1)
        .help(isLocked ? AppSettings.tabLimitNote : "")
    }
}

struct SettingsNote: View {
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

/// Řádek s popisem nahoře a tlačítky na vlastním řádku pod ním – tlačítka se nikdy neořežou.
struct SettingsActionRow<Actions: View>: View {
    let title: String
    var subtitle: String?
    let actions: () -> Actions

    init(title: String, subtitle: String? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            SettingsButtonRow { actions() }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Řada tlačítek, která se při nedostatku místa složí pod sebe.
/// Tlačítka uvnitř by měla mít `.fixedSize()`, aby se jejich text nezkracoval.
struct SettingsButtonRow<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content() }
            VStack(alignment: .leading, spacing: 8) { content() }
        }
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
            SettingsCard(header: L("Jazyk")) {
                SettingsRow(title: L("Jazyk / Language"),
                            subtitle: L("Jazyk rozhraní NotchMaxu.")) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            SettingsCard(header: L("Spuštění")) {
                SettingsToggleRow(title: L("Spouštět při přihlášení"),
                                  subtitle: L("NotchMax se spustí automaticky po přihlášení k Macu."),
                                  isOn: launchBinding)
                SettingsDivider()
                SettingsToggleRow(title: L("Globální zkratka ⌥⌘N"),
                                  subtitle: L("Otevře a zavře notch z klávesnice."),
                                  isOn: $settings.hotkeyEnabled)
            }

            SettingsCard(header: L("Chování")) {
                SettingsRow(title: L("Prodleva při najetí"),
                            subtitle: L("Jak dlouho musí myš zůstat na notchi, než se rozbalí.")) {
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
                SettingsRow(title: L("Zobrazit na"),
                            subtitle: L("Na kterém displeji se notch zobrazí.")) {
                    Picker("", selection: $settings.display) {
                        ForEach(DisplayChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            HStack {
                GlassPill(title: L("Ukončit NotchMax"), symbol: "power") {
                    NSApp.terminate(nil)
                }
                .fixedSize()
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

/// Posuvník odstínu přes celé barevné spektrum (duhová dráha).
private struct HueSlider: View {
    @Binding var hue: Double
    let isDimmed: Bool
    let onEdit: () -> Void

    private let trackHeight: CGFloat = 14
    private let thumbSize: CGFloat = 22

    init(hue: Binding<Double>, isDimmed: Bool, onEdit: @escaping () -> Void) {
        self._hue = hue
        self.isDimmed = isDimmed
        self.onEdit = onEdit
    }

    private static let spectrum: [Color] = (0...12).map { NotchAccent.color(forHue: Double($0) / 12) }

    private func setHue(_ value: Double) {
        hue = min(max(value, 0), 1)
        onEdit()
    }

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumbSize, 1)
            let thumbX = CGFloat(hue) * usable + thumbSize / 2
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: HueSlider.spectrum, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
                    .frame(width: geo.size.width, height: trackHeight)
                    .opacity(isDimmed ? 0.45 : 1)
                Circle()
                    .fill(NotchAccent.color(forHue: hue))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
                    .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: thumbX, y: geo.size.height / 2)
                    .opacity(isDimmed ? 0.6 : 1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(
                // Myš chytá NSView: okno je posuvné za pozadí, SwiftUI DragGesture by mohl posouvat okno.
                HueDragCatcher { x in
                    setHue(Double((x - thumbSize / 2) / usable))
                }
            )
        }
        .frame(height: thumbSize + 6)
        .accessibilityElement()
        .accessibilityLabel(L("Odstín akcentní barvy"))
        .accessibilityValue(L("%ld stupňů", Int((hue * 360).rounded())))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setHue(hue + 1.0 / 72)
            case .decrement: setHue(hue - 1.0 / 72)
            @unknown default: break
            }
        }
    }
}

/// Průhledné NSView nad posuvníkem odstínu: zachytí klik a tažení (a nedovolí tím posunout okno).
private struct HueDragCatcher: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    init(onChange: @escaping (CGFloat) -> Void) {
        self.onChange = onChange
    }

    func makeNSView(context: Context) -> HueDragView {
        let view = HueDragView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: HueDragView, context: Context) {
        nsView.onChange = onChange
    }
}

private final class HueDragView: NSView {
    var onChange: ((CGFloat) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        report(event)
    }

    override func mouseDragged(with event: NSEvent) {
        report(event)
    }

    private func report(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onChange?(point.x)
    }
}

/// Malé kolečko rychlé předvolby barvy.
private struct AccentPresetDot: View {
    let choice: AccentChoice
    let isSelected: Bool
    let action: () -> Void

    init(choice: AccentChoice, isSelected: Bool, action: @escaping () -> Void) {
        self.choice = choice
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(choice.color)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0.15), lineWidth: isSelected ? 2 : 0.75)
                        .padding(-3)
                )
                .padding(4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(choice.title)
    }
}

private struct AccentColorCard: View {
    @EnvironmentObject private var settings: AppSettings

    private var hueBinding: Binding<Double> {
        Binding<Double>(
            get: { settings.accentHue },
            set: { settings.accentHue = $0 }
        )
    }

    private var hueDescription: String {
        if settings.accentWhite { return L("Bílá") }
        return L("Odstín %ld°", Int((settings.accentHue * 360).rounded()))
    }

    private func isPresetSelected(_ choice: AccentChoice) -> Bool {
        if choice == .white { return settings.accentWhite }
        return !settings.accentWhite && abs(settings.accentHue - choice.hue) < 0.005
    }

    var body: some View {
        SettingsCard(header: L("Barva zvýraznění")) {
            HStack(alignment: .center, spacing: 16) {
                // Náhled
                ZStack {
                    Circle()
                        .fill(settings.accent.color)
                        .shadow(color: settings.accent.color.opacity(0.55), radius: 8)
                    Image(systemName: "capsule.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(hueDescription)
                            .font(.system(size: 13.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.8))
                        Spacer(minLength: 8)
                        HStack(spacing: 2) {
                            ForEach(AccentChoice.allCases) { choice in
                                AccentPresetDot(choice: choice, isSelected: isPresetSelected(choice)) {
                                    withAnimation(.smooth(duration: 0.25)) {
                                        if choice == .white {
                                            settings.accentWhite = true
                                        } else {
                                            settings.accentHue = choice.hue
                                            settings.accentWhite = false
                                        }
                                    }
                                }
                            }
                        }
                        .fixedSize()
                    }
                    HueSlider(hue: hueBinding, isDimmed: settings.accentWhite) {
                        if settings.accentWhite { settings.accentWhite = false }
                    }
                }
            }
            .padding(.vertical, 14)
            SettingsDivider()
            SettingsToggleRow(title: L("Bílá"),
                              subtitle: L("Neutrální bílé zvýraznění místo barevného odstínu."),
                              isOn: $settings.accentWhite)
        }
    }
}

private struct AppearanceSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AccentColorCard()

            SettingsCard(header: L("Poloha a velikost notche")) {
                SettingsRow(title: L("Posun nahoru / dolů"),
                            subtitle: L("Doladění, aby tvar přesně seděl na fyzický notch. Kladná hodnota posune nahoru.")) {
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
                SettingsRow(title: L("Přesah pod notch"),
                            subtitle: L("O kolik tvar vyčnívá pod fyzický notch. 0 = přesně na jeho výšku.")) {
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
                SettingsRow(title: L("Výchozí hodnoty"),
                            subtitle: L("Posun %+.0f px, přesah %.0f px.",
                                        AppSettings.defaultNotchOffsetY, AppSettings.defaultNotchOverhang)) {
                    GlassPill(title: L("Obnovit"), symbol: "arrow.counterclockwise") {
                        settings.resetNotchGeometry()
                    }
                    .fixedSize()
                }
            }

            SettingsCard(header: L("Animace nabíjení")) {
                SettingsToggleRow(title: L("Animace při zapojení nabíječky"),
                                  isOn: $settings.chargingAnimation)
                SettingsDivider()
                ChargeInsetRow(title: L("Levá strana"), value: $settings.chargeInsetLeft)
                SettingsDivider()
                ChargeInsetRow(title: L("Pravá strana"), value: $settings.chargeInsetRight)
                SettingsDivider()
                SettingsNote(symbol: "info.circle",
                             text: L("Zúží (+) nebo rozšíří (−) obrys nabíjení. Po změně se animace přehraje."))
                SettingsDivider()
                SettingsRow(title: L("Vyzkoušet animaci")) {
                    HStack(spacing: 8) {
                        GlassPill(title: L("Obnovit"), symbol: "arrow.counterclockwise") {
                            settings.resetChargeInsets()
                        }
                        .fixedSize()
                        GlassPill(title: L("Přehrát"), symbol: "play.fill") {
                            AppServices.shared.viewModel?.runChargeAnimation()
                        }
                        .fixedSize()
                    }
                    .fixedSize()
                }
            }

            SettingsCard {
                SettingsNote(
                    symbol: "moon.fill",
                    text: L("Aplikace je záměrně jen v tmavém režimu, aby splynula s černým notchem. Skleněné prvky vypadají stejně, ať je panel aktivní, nebo ne.")
                )
            }
        }
    }
}

/// Řádek s posuvníkem pro zúžení / rozšíření jedné strany obrysu nabíjení.
private struct ChargeInsetRow: View {
    let title: String
    @Binding var value: Double
    @EnvironmentObject private var settings: AppSettings

    init(title: String, value: Binding<Double>) {
        self.title = title
        self._value = value
    }

    var body: some View {
        SettingsRow(title: title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: -12...12, step: 0.5)
                    .tint(settings.accent.color)
                    .frame(width: 130)
                Text(String(format: "%+.1f px", value))
                    .font(.system(size: 13.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 60, alignment: .trailing)
                Button {
                    value = AppSettings.defaultChargeInset
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(value == AppSettings.defaultChargeInset ? 0.25 : 0.7))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(value == AppSettings.defaultChargeInset)
                .help(L("Vrátit na výchozí hodnotu"))
            }
        }
    }
}

/// Dlaždice pro výběr možnosti se symbolem.
struct SettingsChipTile: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject private var settings: AppSettings

    init(title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? settings.accent.color : Color.white.opacity(0.6))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? settings.accent.color : Color.white.opacity(0.08),
                                  lineWidth: isSelected ? 1.5 : 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notch

private struct NotchSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: L("Živé aktivity vedle notche")) {
                SettingsToggleRow(title: L("Hudba"), subtitle: L("Obal alba a ekvalizér."),
                                  isOn: $settings.liveMusic)
                SettingsDivider()
                SettingsToggleRow(title: L("Časovač"), isOn: $settings.liveTimer)
                SettingsDivider()
                SettingsToggleRow(title: L("Blížící se schůzka"), subtitle: L("Zobrazí se 10 minut předem."),
                                  isOn: $settings.liveCalendar)
                SettingsDivider()
                SettingsToggleRow(title: L("Claude agenti"), subtitle: L("Stav běžících Claude agentů."),
                                  isOn: $settings.liveClaude)
                SettingsDivider()
                SettingsNote(symbol: "rectangle.split.2x1",
                             text: L("Dvě aktivity naráz se řeší automaticky: když běží víc aktivit (třeba hudba a časovač), notch ukáže dvě naposledy spuštěné – jednu vlevo a jednu vpravo od notche. Nic dalšího nastavovat nemusíš."))
            }

            HUDSettingsSection()
        }
    }
}

// MARK: - Panel

private struct PanelSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: L("Záložky v rozbaleném notchi")) {
                TabToggleRow(title: L("Kalendář"), isOn: $settings.tabCalendar)
                SettingsDivider()
                TabToggleRow(title: L("Odkladiště souborů"), isOn: $settings.tabShelf)
                SettingsDivider()
                TabToggleRow(title: L("Nástroje"), subtitle: L("Časovač a další rychlé nástroje."), isOn: $settings.tabTools)
                SettingsDivider()
                TabToggleRow(title: L("Systém"), subtitle: L("Statistiky CPU, paměti a sítě."), isOn: $settings.tabSystem)
                SettingsDivider()
                TabToggleRow(title: L("Agenti"), subtitle: L("Přehled Claude agentů."), isOn: $settings.tabAgents)
                SettingsDivider()
                SettingsNote(symbol: "info.circle",
                             text: L("V notchi se vejde nejvýš 5 záložek včetně Domů – víc by se schovalo za fyzický notch."))
            }

            SettingsCard(header: L("Zrcátko")) {
                SettingsToggleRow(title: L("Tlačítko kamery v notchi"),
                                  subtitle: L("Rychlý náhled z kamery – zkontroluj se před hovorem."),
                                  isOn: $settings.mirrorButton)
                if settings.mirrorButton {
                    SettingsDivider()
                    PermissionRow(kind: .camera, compact: true)
                }
            }

            SettingsCard(header: L("Odkladiště")) {
                SettingsRow(title: L("Mazat odkladiště po"),
                            subtitle: L("Soubory v odkladišti se po této době samy odeberou.")) {
                    Picker("", selection: $settings.shelfTTLHours) {
                        Text(L("1 hodině")).tag(1)
                        Text(L("24 hodinách")).tag(24)
                        Text(L("7 dnech")).tag(168)
                        Text(L("Nikdy")).tag(0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }
}

// Kalendář: `CalendarSettings` je definováno v samostatném souboru.
// Oprávnění: `PermissionsSettingsSection` v HUDSettingsSection.swift.

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
            SettingsCard(header: L("Verze")) {
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
                        Text(L("Sestavení %@", buildNumber))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    Spacer(minLength: 8)
                    GlassPill(title: L("Zkontrolovat"), symbol: "arrow.clockwise") {
                        updates.checkNow()
                    }
                    .fixedSize()
                }
                .padding(.vertical, 14)
                SettingsDivider()
                SettingsRow(title: L("Poslední kontrola")) {
                    Text(lastCheckText)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }

            SettingsCard(header: L("Automatické kontroly")) {
                SettingsToggleRow(
                    title: L("Kontrolovat automaticky"),
                    subtitle: L("Kontrola probíhá při startu, po probuzení Macu a jednou denně. Aktualizace se nainstaluje vždy až po tvém potvrzení."),
                    isOn: autoBinding
                )
            }

            SettingsCard(header: L("Po aktualizaci")) {
                SettingsActionRow(title: L("Zkontroluj oprávnění"),
                                  subtitle: L("Po aktualizaci nepodepsaného sestavení může macOS zapomenout udělená oprávnění.")) {
                    GlassPill(title: L("Zobrazit oprávnění"), symbol: "lock.shield") {
                        showSettingsSection(.permissions)
                    }
                    .fixedSize()
                }
            }
        }
    }

    private var lastCheckText: String {
        if let last = updates.lastCheckDate {
            return last.formatted(date: .abbreviated, time: .shortened)
        }
        return L("Zatím neproběhla")
    }
}
