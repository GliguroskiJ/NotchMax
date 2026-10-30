import SwiftUI

enum LiveActivity: Equatable {
    case timer
    case music
    case meeting(Int)
    case privacy
}

/// Kořen notche: černý tvar, glow, live activity vedle notche, rozbalený panel.
struct NotchRootView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var media: MediaMonitor
    @EnvironmentObject private var calendar: CalendarMonitor
    @EnvironmentObject private var timer: FocusTimer
    @ObservedObject private var privacy = PrivacyMonitor.shared

    private let spring = Animation.spring(response: 0.52, dampingFraction: 0.84)

    private var activity: LiveActivity? {
        if settings.liveTimer, timer.isRunning { return .timer }
        if settings.liveMusic, media.isPlaying { return .music }
        if settings.liveCalendar, let m = calendar.minutesToNextMeeting, m <= 10 { return .meeting(m) }
        if privacy.micActive || privacy.cameraActive { return .privacy }
        return nil
    }

    private var size: CGSize {
        let n = vm.geometry.notchSize
        if vm.isOpen { return NotchLayout.openSize }
        // Tvar vždy kousek přesahuje pod fyzický notch (lip), aby byl obrys vidět.
        let h = n.height + CGFloat(settings.notchOverhang)
        if vm.banner != nil { return CGSize(width: n.width + 12 + 22, height: h + 4) }
        // Hudba potřebuje po stranách jen malou ikonu; časovač a schůzka víc místa na text.
        var extra: CGFloat = 0
        if let a = activity {
            var side = (a == .music || a == .privacy) ? NotchLayout.sideActivity : NotchLayout.sideActivityText
            if a != .privacy, privacy.micActive || privacy.cameraActive { side += 12 }
            extra = side * 2
        }
        return CGSize(width: n.width + 12 + extra, height: h)
    }

    private var radii: (top: CGFloat, bottom: CGFloat) {
        if vm.isOpen { return (NotchLayout.openTopRadius, NotchLayout.openBottomRadius) }
        if vm.banner != nil { return (8, 16) }
        return (6, 14)
    }

    private struct GlowSpec {
        let color: Color
        let style: GlowStyle
        let progress: Double?
    }

    private var glow: GlowSpec? {
        guard settings.glowStyle != .off, !vm.isOpen else { return nil }
        let style = settings.glowStyle
        if timer.isRunning { return GlowSpec(color: settings.accent.color, style: style, progress: timer.progress) }
        if media.isPlaying { return GlowSpec(color: settings.accent.color, style: style, progress: nil) }
        if let m = calendar.minutesToNextMeeting, m <= 5 { return GlowSpec(color: .orange, style: .pulse, progress: nil) }
        if battery.hasBattery, battery.isCharging, settings.liveBattery {
            return GlowSpec(color: .green, style: .pulse, progress: nil)
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
                    .fill(Color.black)

                content
                    .clipShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))

                if vm.isOpen {
                    NotchOutline(topRadius: radii.top, bottomRadius: radii.bottom)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .allowsHitTesting(false)
                }

                if let g = glow {
                    GlowBar(top: radii.top, bottom: radii.bottom, color: g.color, style: g.style, progress: g.progress)
                }
                ChargeSweep(top: radii.top, bottom: radii.bottom)
            }
            .frame(width: size.width, height: size.height)
            .animation(spring, value: vm.isOpen)
            .animation(spring, value: vm.banner)
            .animation(spring, value: activity)
        }
        .frame(width: NotchLayout.panelSize.width, height: NotchLayout.panelSize.height, alignment: .top)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isOpen {
            OpenPanel()
                .transition(.asymmetric(
                    insertion: AnyTransition.opacity
                        .combined(with: .scale(scale: 0.94, anchor: .top))
                        .animation(.smooth(duration: 0.38).delay(0.1)),
                    removal: AnyTransition.opacity.animation(.easeOut(duration: 0.12))
                ))
        } else if vm.banner == nil, let a = activity {
            CompactActivity(activity: a)
                .frame(height: vm.geometry.notchSize.height)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        }
    }
}

// MARK: - Live activity vedle notche

struct CompactActivity: View {
    let activity: LiveActivity
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var media: MediaMonitor
    @EnvironmentObject private var timer: FocusTimer

    var body: some View {
        HStack {
            left
            Spacer(minLength: 0)
            right
        }
        .padding(.horizontal, 9)
    }

    @ViewBuilder private var left: some View {
        switch activity {
        case .music:
            if let art = media.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
            } else {
                Image(systemName: "music.note").font(.system(size: 12, weight: .semibold)).foregroundStyle(settings.accent.color)
            }
        case .timer:
            Image(systemName: "timer").font(.system(size: 12, weight: .semibold)).foregroundStyle(settings.accent.color)
        case .meeting:
            Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.orange)
        case .privacy:
            EmptyView()
        }
    }

    private var right: some View {
        HStack(spacing: 5) {
            PrivacyDots()
            rightContent
        }
    }

    @ViewBuilder private var rightContent: some View {
        switch activity {
        case .music:
            EqualizerBars(color: settings.accent.color, active: media.isPlaying)
        case .timer:
            Text(timer.display)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Color.white)
        case .meeting(let m):
            Text("\(m) min")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Color.orange)
        case .privacy:
            EmptyView()
        }
    }
}

// MARK: - Rozbalený panel

struct OpenPanel: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var media: MediaMonitor
    @Namespace private var tabNamespace

    /// Horní rohy tvaru se rozšiřují ven, takže tělo je užší o poloměr na každé straně.
    private var sideInset: CGFloat { NotchLayout.sideInset }

    
    private var cardTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: NotchLayout.spacingM) {
                tabBar
                Spacer(minLength: vm.geometry.notchSize.width + 16)
                statusCluster
            }
            .frame(height: NotchLayout.controlHeight)
            .padding(.top, NotchLayout.margin)
            .padding(.horizontal, sideInset)

            ZStack {
                tabContent
            }
            .animation(.smooth(duration: 0.3), value: vm.tab)
            .padding(.horizontal, sideInset)
            .padding(.top, NotchLayout.spacingS)
            .padding(.bottom, NotchLayout.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ambient)
        .onChange(of: settings.visibleTabs) { _, tabs in
            // Když uživatel vypne právě zobrazenou záložku, vrátit se na Přehled.
            if !tabs.contains(vm.tab) { vm.tab = .home }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch vm.tab {
        case .home: HomeView().transition(cardTransition)
        case .calendar: CalendarView().transition(cardTransition)
        case .shelf: ShelfView().transition(cardTransition)
        case .tools: ToolsHubView().transition(cardTransition)
        case .system: SystemHubView().transition(cardTransition)
        }
    }

    /// Tlumené barevné světlo za skleněnými kartami (sklo na čisté černé není vidět),
    /// ale dost tmavé, aby karty měly kontrast.
    private var ambient: some View {
        let hasArt = media.artwork != nil && media.isPlaying
        return GeometryReader { geo in
            ZStack {
                Color.black
                if hasArt, let art = media.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 40)
                        .saturation(0.7)
                        .opacity(0.32)
                        .clipped()
                    Color.black.opacity(0.35)
                } else {
                    RadialGradient(colors: [settings.accent.color.opacity(0.2), Color.clear],
                                   center: .bottomLeading, startRadius: 0, endRadius: 300)
                    RadialGradient(colors: [Color.purple.opacity(0.12), Color.clear],
                                   center: .bottomTrailing, startRadius: 0, endRadius: 260)
                }
                // Hlavička zůstává na čisté černé (splývá s notchem), světlo sílí směrem dolů.
                LinearGradient(colors: [Color.black, Color.black.opacity(0)],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .animation(.smooth(duration: 0.6), value: hasArt)
    }

    private var tabBar: some View {
        GlassContainer(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(settings.visibleTabs) { tab in
                    TabButton(tab: tab,
                              active: vm.tab == tab,
                              accent: settings.accent.color,
                              namespace: tabNamespace) {
                        withAnimation(.smooth(duration: 0.3)) { vm.tab = tab }
                    }
                }
            }
            .padding(3)
            .notchGlass(in: Capsule(), tint: Color.white.opacity(0.05))
        }
    }

    private var statusCluster: some View {
        GlassContainer(spacing: NotchLayout.spacingS) {
            HStack(spacing: NotchLayout.spacingS) {
                if battery.hasBattery {
                    batteryPill
                }
                GlassIconButton(symbol: "gearshape.fill", size: NotchLayout.controlHeight) {
                    openNotchMaxSettings()
                }
                .help("Nastavení")
            }
        }
    }

    private var batteryPill: some View {
        HStack(spacing: 4) {
            Image(systemName: BatteryIcon.name(level: battery.level, charging: battery.isCharging))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(battery.isCharging ? Color.green : Color.white.opacity(0.8))
            Text("\(battery.level) %")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .frame(height: NotchLayout.controlHeight)
        .notchGlass(in: Capsule(), tint: battery.isCharging ? Color.green.opacity(0.14) : Color.white.opacity(0.05))
    }
}

/// Záložka s plynule přesouvaným indikátorem; aktivní záložka ukazuje i název.
private struct TabButton: View {
    let tab: NotchTab
    let active: Bool
    let accent: Color
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32)
                .foregroundStyle(foreground)
                .frame(height: NotchLayout.controlHeight - 6)
                .background { indicator }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.15), value: hovering)
        .help(tab.title)
    }

    private var foreground: Color {
        if active { return Color.white }
        return Color.white.opacity(hovering ? 0.9 : 0.62)
    }

    @ViewBuilder
    private var indicator: some View {
        if active {
            Capsule()
                .fill(accent.opacity(0.3))
                .overlay(Capsule().strokeBorder(accent.opacity(0.55), lineWidth: 0.75))
                .matchedGeometryEffect(id: "tabIndicator", in: namespace)
        } else if hovering {
            Capsule().fill(Color.white.opacity(0.08))
        }
    }
}
