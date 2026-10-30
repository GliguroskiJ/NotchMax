import SwiftUI

enum LiveActivity: Equatable {
    case timer
    case music
    case meeting(Int)
    case charging
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
        if settings.liveBattery, battery.hasBattery, battery.isCharging { return .charging }
        return nil
    }

    private var size: CGSize {
        let n = vm.geometry.notchSize
        if vm.isOpen { return NotchLayout.openSize }
        if vm.banner != nil { return CGSize(width: n.width + 180, height: n.height + 38) }
        let extra: CGFloat = activity == nil ? 0 : NotchLayout.sideActivity * 2
        return CGSize(width: n.width + 12 + extra, height: n.height)
    }

    private var radii: (top: CGFloat, bottom: CGFloat) {
        if vm.isOpen { return (19, 30) }
        if vm.banner != nil { return (10, 22) }
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
        } else if vm.banner != nil {
            ChargingBanner()
                .transition(.opacity)
        } else if let a = activity {
            CompactActivity(activity: a)
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
        case .charging:
            Image(systemName: "bolt.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.green)
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
        case .charging:
            Text("\(battery.level) %").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Color.green)
        }
    }
}

// MARK: - Nabíjecí banner

struct ChargingBanner: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var battery: BatteryMonitor
    @State private var fill: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: vm.geometry.notchSize.height)
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill").foregroundStyle(Color.green)
                Text("\(battery.level) %")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(Color.green.opacity(0.85))
                            .frame(width: max(8, geo.size.width * fill))
                            .notchGlass(in: Capsule(), tint: Color.green.opacity(0.5))
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal, 18)
            .frame(height: 38)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).delay(0.25)) {
                fill = CGFloat(battery.level) / 100
            }
        }
    }
}

// MARK: - Rozbalený panel

struct OpenPanel: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var battery: BatteryMonitor

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                tabBar
                Spacer(minLength: vm.geometry.notchSize.width + 24)
                statusCluster
            }
            .frame(height: vm.geometry.notchSize.height)
            .padding(.horizontal, 26)

            Group {
                switch vm.tab {
                case .home: HomeView()
                case .calendar: CalendarView()
                case .shelf: ShelfView()
                case .tools: ToolsView()
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: settings.visibleTabs) { _, tabs in
            // Když uživatel vypne právě zobrazenou záložku, vrátit se na Přehled.
            if !tabs.contains(vm.tab) { vm.tab = .home }
        }
    }

    private var tabBar: some View {
        GlassContainer(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(settings.visibleTabs) { tab in
                    let active = vm.tab == tab
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { vm.tab = tab }
                    } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(active ? Color.white : Color.white.opacity(0.5))
                            .frame(width: 30, height: 22)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                    .notchGlass(in: Capsule(), tint: settings.accent.color.opacity(0.35), interactive: true, enabled: active)
                }
            }
        }
    }

    private var statusCluster: some View {
        HStack(spacing: 10) {
            if battery.hasBattery {
                HStack(spacing: 4) {
                    Image(systemName: battery.isCharging ? "battery.100percent.bolt" : "battery.100percent")
                        .font(.system(size: 12))
                        .foregroundStyle(battery.isCharging ? Color.green : Color.white.opacity(0.7))
                    Text("\(battery.level) %")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
            Button {
                openNotchMaxSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Nastavení")
        }
    }
}
