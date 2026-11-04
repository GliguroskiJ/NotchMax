import SwiftUI
import AppKit

enum LiveActivity: Equatable {
    case timer
    case music
    case meeting(Int)
    case battery
    case claude
    case privacy

    /// Druh aktivity (pro vyloučení duplicity mezi levou a pravou stranou).
    var slot: ActivitySlot {
        switch self {
        case .timer: return .timer
        case .music: return .music
        case .meeting: return .meeting
        case .battery: return .battery
        case .claude: return .claude
        case .privacy: return .none
        }
    }
}

/// Co se vykreslí na jedné straně notche.
enum SidePiece: Equatable {
    /// Jen ikona (jedna aktivita rozdělená na obě strany – levá část).
    case icon(LiveActivity)
    /// Jen detail (jedna aktivita rozdělená na obě strany – pravá část).
    case detail(LiveActivity)
    /// Samostatný widget ikona + detail (režim dvou aktivit).
    case widget(LiveActivity)
}

/// Rozvržení zavřeného notche s live activity. Šířky jsou bez horního zaoblení tvaru.
struct ClosedLayout: Equatable {
    var left: SidePiece?
    var right: SidePiece?
    var showsPrivacy: Bool
    var leftWidth: CGFloat
    var rightWidth: CGFloat
}

/// Rozměry obsahu live activity – šířky se počítají předem, aby tvar byl jen tak široký, jak je nutné.
enum CompactMetrics {
    static let fontSize: CGFloat = 11
    static let badgeFontSize: CGFloat = 9.5
    static let badgeMin: CGFloat = 15
    /// 4 sloupce × 2,5 + 3 mezery × 2
    static let equalizerWidth: CGFloat = 16
    static let dotSize: CGFloat = 6
    static let dotSpacing: CGFloat = 4
    static let claudeColor = Color(red: 0.85, green: 0.47, blue: 0.34)

    /// Šířka textu v písmu live activity (zaoblené, číslice stejně široké) + malá rezerva.
    static func textWidth(_ string: String, size: CGFloat = 11, weight: NSFont.Weight = .semibold) -> CGFloat {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        var font: NSFont = base
        if let rounded = base.fontDescriptor.withDesign(.rounded),
           let roundedFont = NSFont(descriptor: rounded, size: size) {
            font = roundedFont
        }
        let width = (string as NSString).size(withAttributes: [.font: font]).width
        return ceil(width) + 2
    }

    static func badgeWidth(_ count: Int) -> CGFloat {
        max(badgeMin, textWidth("\(count)", size: badgeFontSize, weight: .bold) + 8)
    }

    static func dotsWidth(mic: Bool, camera: Bool) -> CGFloat {
        let n: Int = (mic ? 1 : 0) + (camera ? 1 : 0)
        guard n > 0 else { return 0 }
        return CGFloat(n) * dotSize + CGFloat(n - 1) * dotSpacing
    }

    static func meetingText(_ minutes: Int) -> String {
        minutes <= 1 ? "1 min" : "\(minutes) min"
    }

    static func batteryText(_ level: Int) -> String {
        "\(level) %"
    }
}

/// Kořen notche: černý tvar, live activity vedle notche, animace nabíjení, rozbalený panel.
struct NotchRootView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var media: MediaMonitor
    @EnvironmentObject private var calendar: CalendarMonitor
    @EnvironmentObject private var timer: FocusTimer
    @ObservedObject private var privacy = PrivacyMonitor.shared
    @ObservedObject private var claude = ClaudeMonitor.shared

    private let spring = Animation.spring(response: 0.52, dampingFraction: 0.84)

    private var privacyActive: Bool { privacy.micActive || privacy.cameraActive }
    private var claudeActive: Bool { claude.isWorking || claude.waitingCount > 0 }

    // MARK: Výběr aktivit

    /// Aktivita s nejvyšší prioritou (volitelně kromě jednoho druhu, který už je na druhé straně).
    private func priorityActivity(excluding excluded: ActivitySlot?) -> LiveActivity? {
        var candidates: [LiveActivity] = []
        let minutes: Int? = settings.liveCalendar ? calendar.minutesToNextMeeting : nil
        // Blížící se schůzka (do 5 minut) má přednost před časovačem i hudbou, ať je odpočet vidět vždy.
        if let m = minutes, m <= 5 { candidates.append(.meeting(m)) }
        if settings.liveTimer, timer.isRunning { candidates.append(.timer) }
        if settings.liveMusic, media.isPlaying { candidates.append(.music) }
        if let m = minutes, m > 5, m <= 10 { candidates.append(.meeting(m)) }
        if settings.liveClaude, claudeActive { candidates.append(.claude) }
        return candidates.first { $0.slot != excluded }
    }

    /// Aktivita pevně zvolená pro jednu stranu (režim dvou aktivit); nil = teď nemá co ukázat.
    private func fixedActivity(for slot: ActivitySlot) -> LiveActivity? {
        switch slot {
        case .music:
            return media.isPlaying ? .music : nil
        case .timer:
            return timer.isRunning ? .timer : nil
        case .meeting:
            if let m = calendar.minutesToNextMeeting, m <= 60 { return .meeting(m) }
            return nil
        case .battery:
            return battery.hasBattery ? .battery : nil
        case .claude:
            return claudeActive ? .claude : nil
        case .auto, .none:
            return nil
        }
    }

    // MARK: Rozvržení

    private var closedLayout: ClosedLayout? {
        guard !vm.isOpen, vm.banner == nil else { return nil }
        return settings.dualActivities ? dualLayout() : singleLayout()
    }

    /// Jedna aktivita: ikona vlevo, detail vpravo, obě strany stejně široké.
    private func singleLayout() -> ClosedLayout? {
        var chosen: LiveActivity? = priorityActivity(excluding: nil)
        if chosen == nil, privacyActive { chosen = .privacy }
        guard let activity = chosen else { return nil }
        let left: SidePiece? = activity == .privacy ? nil : .icon(activity)
        let right: SidePiece? = activity == .privacy ? nil : .detail(activity)
        let leftWidth = sideWidth(content: left.map { pieceWidth($0) } ?? 0, dots: false)
        let rightWidth = sideWidth(content: right.map { pieceWidth($0) } ?? 0, dots: privacyActive)
        let width = max(leftWidth, rightWidth)
        return ClosedLayout(left: left, right: right, showsPrivacy: privacyActive,
                            leftWidth: width, rightWidth: width)
    }

    /// Dvě nezávislé aktivity: každá strana je samostatný widget s vlastní šířkou.
    private func dualLayout() -> ClosedLayout? {
        let leftSlot = settings.leftActivity
        let rightSlot = settings.rightActivity
        let rightFixed = fixedActivity(for: rightSlot)
        let leftActivity: LiveActivity? = leftSlot == .auto
            ? priorityActivity(excluding: rightFixed?.slot)
            : fixedActivity(for: leftSlot)
        let rightActivity: LiveActivity? = rightSlot == .auto
            ? priorityActivity(excluding: leftActivity?.slot)
            : rightFixed
        let left: SidePiece? = leftActivity.map { SidePiece.widget($0) }
        let right: SidePiece? = rightActivity.map { SidePiece.widget($0) }
        if left == nil, right == nil, !privacyActive { return nil }
        return ClosedLayout(
            left: left,
            right: right,
            showsPrivacy: privacyActive,
            leftWidth: sideWidth(content: left.map { pieceWidth($0) } ?? 0, dots: false),
            rightWidth: sideWidth(content: right.map { pieceWidth($0) } ?? 0, dots: privacyActive)
        )
    }

    /// Šířka strany: vnější okraj + obsah (+ tečky soukromí) + vnitřní okraj; bez obsahu 0.
    private func sideWidth(content: CGFloat, dots: Bool) -> CGFloat {
        let dotsWidth: CGFloat = dots
            ? CompactMetrics.dotsWidth(mic: privacy.micActive, camera: privacy.cameraActive)
            : 0
        let gap: CGFloat = (content > 0 && dotsWidth > 0) ? NotchLayout.compactGap : 0
        let inner: CGFloat = content + gap + dotsWidth
        guard inner > 0 else { return 0 }
        return NotchLayout.compactOuterPadding + inner + NotchLayout.compactInnerPadding
    }

    private func pieceWidth(_ piece: SidePiece) -> CGFloat {
        switch piece {
        case .icon:
            return NotchLayout.compactIcon
        case .detail(let a):
            return detailWidth(a, inWidget: false)
        case .widget(let a):
            let d = detailWidth(a, inWidget: true)
            return NotchLayout.compactIcon + (d > 0 ? NotchLayout.compactGap + d : 0)
        }
    }

    private func detailWidth(_ activity: LiveActivity, inWidget: Bool) -> CGFloat {
        switch activity {
        case .music:
            return CompactMetrics.equalizerWidth
        case .timer:
            return CompactMetrics.textWidth(timer.display)
        case .meeting(let m):
            return CompactMetrics.textWidth(CompactMetrics.meetingText(m))
        case .battery:
            return CompactMetrics.textWidth(CompactMetrics.batteryText(battery.level))
        case .claude:
            if claude.waitingCount > 0 { return CompactMetrics.badgeWidth(claude.waitingCount) }
            return inWidget ? 0 : CompactMetrics.badgeWidth(max(claude.activeCount, 1))
        case .privacy:
            return 0
        }
    }

    // MARK: Tvar

    private var radii: (top: CGFloat, bottom: CGFloat) {
        if vm.isOpen { return (NotchLayout.openTopRadius, NotchLayout.openBottomRadius) }
        return (NotchLayout.closedTopRadius, NotchLayout.closedBottomRadius)
    }

    private func shapeSize(for layout: ClosedLayout?) -> CGSize {
        if vm.isOpen { return NotchLayout.openSize }
        let n = vm.geometry.notchSize
        let height = n.height + CGFloat(settings.notchOverhang)
        // Bez live activity (a během nabíjení) má tvar přesně šířku notche + horní zaoblení.
        let sides: CGFloat = (layout?.leftWidth ?? 0) + (layout?.rightWidth ?? 0)
        return CGSize(width: n.width + 2 * NotchLayout.closedTopRadius + sides, height: height)
    }

    var body: some View {
        let layout = closedLayout
        let size = shapeSize(for: layout)
        let r = radii
        // Asymetrický tvar se posune tak, aby fyzický notch zůstal přesně uprostřed.
        let shift: CGFloat = layout.map { ($0.rightWidth - $0.leftWidth) / 2 } ?? 0
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: r.top, bottomRadius: r.bottom)
                    .fill(Color.black)

                content(layout: layout)
                    .clipShape(NotchShape(topRadius: r.top, bottomRadius: r.bottom))

                if vm.isOpen {
                    NotchOutline(topRadius: r.top, bottomRadius: r.bottom)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .allowsHitTesting(false)
                } else {
                    ChargeSweep(top: r.top, bottom: r.bottom)
                }
            }
            .frame(width: size.width, height: size.height)
            .offset(x: shift)
            .animation(spring, value: vm.isOpen)
            .animation(spring, value: vm.banner)
            .animation(spring, value: layout)
        }
        .frame(width: NotchLayout.panelSize.width, height: NotchLayout.panelSize.height, alignment: .top)
        .preferredColorScheme(.dark)
        .onChange(of: layout, initial: true) { _, newLayout in
            vm.closedSideWidths = (newLayout?.leftWidth ?? 0, newLayout?.rightWidth ?? 0)
        }
    }

    @ViewBuilder
    private func content(layout: ClosedLayout?) -> some View {
        if vm.isOpen {
            OpenPanel()
                .transition(.asymmetric(
                    insertion: AnyTransition.opacity
                        .combined(with: .scale(scale: 0.94, anchor: .top))
                        .animation(.smooth(duration: 0.38).delay(0.1)),
                    removal: AnyTransition.opacity.animation(.easeOut(duration: 0.12))
                ))
        } else if let layout = layout {
            CompactActivity(layout: layout, notchWidth: vm.geometry.notchSize.width)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        }
    }
}

// MARK: - Live activity vedle notche

struct CompactActivity: View {
    let layout: ClosedLayout
    let notchWidth: CGFloat
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var media: MediaMonitor
    @EnvironmentObject private var timer: FocusTimer
    @ObservedObject private var claude = ClaudeMonitor.shared

    var body: some View {
        HStack(spacing: 0) {
            leftSide
                .frame(width: layout.leftWidth)
            Color.clear
                .frame(width: notchWidth)
            rightSide
                .frame(width: layout.rightWidth)
        }
        .padding(.horizontal, NotchLayout.closedTopRadius)
        // Obsah je svisle uprostřed celé výšky zavřeného tvaru.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Levá strana: obsah zarovnaný k vnějšímu (zaoblenému) okraji.
    @ViewBuilder private var leftSide: some View {
        if let piece = layout.left, layout.leftWidth > 0 {
            HStack(spacing: 0) {
                pieceView(piece)
                Spacer(minLength: 0)
            }
            .padding(.leading, NotchLayout.compactOuterPadding)
            .padding(.trailing, NotchLayout.compactInnerPadding)
        } else {
            Color.clear
        }
    }

    /// Pravá strana: obsah zarovnaný k vnějšímu okraji, tečky soukromí úplně vpravo.
    @ViewBuilder private var rightSide: some View {
        if layout.rightWidth > 0 {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if let piece = layout.right {
                    pieceView(piece)
                }
                if layout.showsPrivacy {
                    PrivacyDots()
                        .padding(.leading, layout.right == nil ? 0 : NotchLayout.compactGap)
                }
            }
            .padding(.leading, NotchLayout.compactInnerPadding)
            .padding(.trailing, NotchLayout.compactOuterPadding)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private func pieceView(_ piece: SidePiece) -> some View {
        switch piece {
        case .icon(let a):
            icon(a)
        case .detail(let a):
            detail(a, inWidget: false)
        case .widget(let a):
            HStack(spacing: NotchLayout.compactGap) {
                icon(a)
                if hasDetail(a, inWidget: true) {
                    detail(a, inWidget: true)
                }
            }
        }
    }

    private func hasDetail(_ activity: LiveActivity, inWidget: Bool) -> Bool {
        switch activity {
        case .claude: return claude.waitingCount > 0 || !inWidget
        case .privacy: return false
        case .music, .timer, .meeting, .battery: return true
        }
    }

    // MARK: Ikony

    @ViewBuilder private func icon(_ activity: LiveActivity) -> some View {
        switch activity {
        case .music:
            if let art = media.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: NotchLayout.compactIcon, height: NotchLayout.compactIcon)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
            } else {
                symbol("music.note", color: settings.accent.color)
            }
        case .timer:
            symbol("timer", color: settings.accent.color)
        case .meeting:
            symbol("calendar", color: Color.orange)
        case .battery:
            Image(systemName: BatteryIcon.name(level: battery.level, charging: battery.isCharging))
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(battery.isCharging ? Color.green : Color.white.opacity(0.85))
                .frame(width: NotchLayout.compactIcon, height: 11)
                .frame(height: NotchLayout.compactIcon)
        case .claude:
            CompactClaudeSparkle(working: claude.isWorking)
                .frame(width: NotchLayout.compactIcon, height: NotchLayout.compactIcon)
        case .privacy:
            EmptyView()
        }
    }

    private func symbol(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: NotchLayout.compactIcon, height: NotchLayout.compactIcon)
    }

    // MARK: Detaily

    @ViewBuilder private func detail(_ activity: LiveActivity, inWidget: Bool) -> some View {
        switch activity {
        case .music:
            EqualizerBars(color: settings.accent.color, active: media.isPlaying)
                .frame(width: CompactMetrics.equalizerWidth)
        case .timer:
            compactText(timer.display, color: Color.white)
        case .meeting(let m):
            compactText(CompactMetrics.meetingText(m), color: Color.orange)
        case .battery:
            compactText(CompactMetrics.batteryText(battery.level),
                        color: battery.isCharging ? Color.green : Color.white)
        case .claude:
            if claude.waitingCount > 0 {
                CompactCountBadge(count: claude.waitingCount, fill: Color.orange)
            } else if !inWidget {
                CompactCountBadge(count: max(claude.activeCount, 1), fill: Color.white.opacity(0.2))
            }
        case .privacy:
            EmptyView()
        }
    }

    private func compactText(_ string: String, color: Color) -> some View {
        Text(string)
            .font(.system(size: CompactMetrics.fontSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .lineLimit(1)
            .fixedSize()
    }
}

/// Malý odznak s počtem (např. agenti čekající na vstup).
private struct CompactCountBadge: View {
    let count: Int
    let fill: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: CompactMetrics.badgeFontSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .frame(minWidth: CompactMetrics.badgeMin, minHeight: CompactMetrics.badgeMin)
            .background(Capsule().fill(fill))
    }
}

/// Ikona Claude agentů – pokud agent pracuje, jemně pulzuje.
private struct CompactClaudeSparkle: View {
    let working: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !working)) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            let pulse: Double = working ? 0.5 + 0.5 * sin(t * 2 * Double.pi / 1.4) : 1
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CompactMetrics.claudeColor)
                .scaleEffect(working ? CGFloat(0.86 + 0.18 * pulse) : 1)
                .opacity(working ? 0.6 + 0.4 * pulse : 0.9)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        case .agents: ClaudeAgentsView().transition(cardTransition)
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
        .notchGlass(in: Capsule(),
                    tint: battery.isCharging ? Color.green.opacity(0.14) : Color.white.opacity(0.05),
                    interactive: true)
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
