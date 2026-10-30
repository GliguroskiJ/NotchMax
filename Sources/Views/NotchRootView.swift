import SwiftUI

enum LiveActivity: Equatable {
    case timer
    case music
    case meeting(Int)
}

/// Kořen notche: černý tvar, glow, live activity vedle notche, rozbalený panel.
struct NotchRootView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var media: MediaMonitor
    @EnvironmentObject private var calendar: CalendarMonitor
    @EnvironmentObject private var timer: FocusTimer

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)

    private var activity: LiveActivity? {
        if settings.liveTimer, timer.isRunning { return .timer }
        if settings.liveMusic, media.isPlaying { return .music }
        if settings.liveCalendar, let m = calendar.minutesToNext, m <= 10 { return .meeting(m) }
        return nil
    }

    private var size: CGSize {
        let n = vm.geometry.notchSize
        if vm.isOpen { return NotchLayout.openSize }
        // Tvar vždy kousek přesahuje pod fyzický notch (lip), aby byl obrys vidět.
        let h = n.height + NotchLayout.lip
        if vm.banner != nil { return CGSize(width: n.width + 12 + 22, height: h + 5) }
        let extra: CGFloat = activity == nil ? 0 : NotchLayout.sideActivity * 2
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
        if let m = calendar.minutesToNext, m <= 5 { return GlowSpec(color: .orange, style: .pulse, progress: nil) }
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
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        } else if vm.banner == nil, let a = activity {
            CompactActivity(activity: a)
                .frame(height: vm.geometry.notchSize.height)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
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
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var left: some View {
        switch activity {
        case .music:
            if let art = media.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "music.note").font(.system(size: 12, weight: .semibold)).foregroundStyle(settings.accent.color)
            }
        case .timer:
            Image(systemName: "timer").font(.system(size: 12, weight: .semibold)).foregroundStyle(settings.accent.color)
        case .meeting:
            Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.orange)
        }
    }

    @ViewBuilder private var right: some View {
        switch activity {
        case .music:
            EqualizerBars(color: settings.accent.color, active: media.isPlaying)
        case .timer:
            Text(timer.display).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Color.white)
        case .meeting(let m):
            Text("\(m) min").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Color.orange)
        }
    }
}

// MARK: - Rozbalený panel

struct OpenPanel: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var media: MediaMonitor

    /// Horní rohy tvaru se rozšiřují ven, takže tělo je užší o poloměr na každé straně.
    private var sideInset: CGFloat { NotchLayout.openTopRadius + NotchLayout.margin }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                tabBar
                Spacer(minLength: vm.geometry.notchSize.width + 24)
                statusCluster
            }
            .frame(height: vm.geometry.notchSize.height)
            .padding(.horizontal, sideInset)

            Group {
                switch vm.tab {
                case .home: HomeView()
                case .calendar: CalendarView()
                case .shelf: ShelfView()
                case .tools: ToolsView()
                }
            }
            .padding(.horizontal, sideInset)
            .padding(.top, 8)
            .padding(.bottom, NotchLayout.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ambient)
        .onChange(of: settings.visibleTabs) { _, tabs in
            // Když uživatel vypne právě zobrazenou záložku, vrátit se na Přehled.
            if !tabs.contains(vm.tab) { vm.tab = .home }
        }
    }

    /// Jemné barevné světlo za skleněnými kartami (sklo na čisté černé není vidět).
    private var ambient: some View {
        ZStack {
            Color.black
            if let art = media.artwork, media.isPlaying {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 50)
                    .opacity(0.5)
            } else {
                RadialGradient(colors: [settings.accent.color.opacity(0.38), Color.clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 320)
                RadialGradient(colors: [Color.purple.opacity(0.22), Color.clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 280)
            }
        }
        .clipped()
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(settings.visibleTabs) { tab in
                let active = vm.tab == tab
                Button {
                    withAnimation(.smooth(duration: 0.25)) { vm.tab = tab }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(active ? Color.white : Color.white.opacity(0.55))
                        .frame(width: 32, height: 24)
                        .background {
                            if active { Capsule().fill(settings.accent.color.opacity(0.55)) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(3)
        .notchGlass(in: Capsule(), tint: Color.white.opacity(0.04))
    }

    private var statusCluster: some View {
        HStack(spacing: 8) {
            if battery.hasBattery {
                HStack(spacing: 4) {
                    Image(systemName: battery.isCharging ? "bolt.fill" : "battery.75percent")
                        .font(.system(size: 11))
                        .foregroundStyle(battery.isCharging ? Color.green : Color.white.opacity(0.75))
                    Text("\(battery.level) %")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .notchGlass(in: Capsule(), tint: Color.white.opacity(0.04))
            }
            GlassIconButton(symbol: "gearshape.fill", size: 26) {
                openNotchMaxSettings()
            }
            .help("Nastavení")
        }
    }
}
