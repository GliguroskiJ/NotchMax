import SwiftUI
import AppKit

enum LiveActivity: Hashable {
    case timer
    case music
    /// Nejbližší schůzka – nese čas začátku, odpočet se počítá každou sekundu.
    case meeting(Date)
    case claude
    case privacy
}

/// Co se vykreslí na jedné straně notche.
enum SidePiece: Hashable {
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
    /// Nejširší běžný text odpočtu – podle něj se měří šířka, aby se tvar každou sekundu necukal.
    static let counterTemplate = "00 min"

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

    /// Odpočet: od 60 s výš jen minuty (zaokrouhlené nahoru), v poslední minutě jen sekundy.
    static func countdownText(_ seconds: TimeInterval) -> String {
        let secs: Int = max(0, Int(ceil(seconds)))
        if secs >= 60 { return "\((secs + 59) / 60) min" }
        return "\(secs) s"
    }

    /// Šířka odpočtu – vždy aspoň pro „00 min“, aby se neměnila s každým tikem.
    static func counterWidth(_ string: String) -> CGFloat {
        max(textWidth(counterTemplate), textWidth(string))
    }
}

/// Kořen notche: černý tvar, live activity vedle notche, animace nabíjení, rozbalený panel.
struct NotchRootView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var media: MediaMonitor
    @EnvironmentObject private var calendar: CalendarMonitor
    @EnvironmentObject private var timer: FocusTimer
    @ObservedObject private var privacy = PrivacyMonitor.shared
    @ObservedObject private var claude = ClaudeMonitor.shared
    @ObservedObject private var hud = HUDCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spring = Animation.spring(response: 0.52, dampingFraction: 0.84)

    /// Pružina pro rozbalení notche do HUD (při omezení pohybu jen krátké prolnutí).
    private var hudSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.78)
    }

    /// HUD se ukazuje jen u zavřeného notche a ne během animace nabíjení.
    private var hudEvent: HUDEvent? {
        guard !vm.isOpen, vm.banner == nil, vm.chargeStart == nil else { return nil }
        return hud.current
    }

    private var privacyActive: Bool { privacy.micActive || privacy.cameraActive }
    private var claudeActive: Bool { claude.isWorking || claude.waitingCount > 0 }

    // MARK: Výběr aktivit

    /// Začátek nejbližší schůzky, pokud začíná do 10 minut (a live kalendář je zapnutý).
    private var upcomingMeetingStart: Date? {
        guard settings.liveCalendar,
              let m = calendar.minutesToNextMeeting, m <= 10 else { return nil }
        return calendar.meetings.first(where: { $0.start > calendar.now })?.start
    }

    /// Schůzka do 5 minut je vidět vždy, i když není mezi dvěma nejnovějšími aktivitami.
    private var meetingIsUrgent: Bool {
        guard upcomingMeetingStart != nil, let m = calendar.minutesToNextMeeting else { return false }
        return m <= 5
    }

    /// Právě aktivní druhy live activity (podle přepínačů v Nastavení).
    private var activeKinds: Set<LiveKind> {
        var kinds = Set<LiveKind>()
        if upcomingMeetingStart != nil { kinds.insert(.meeting) }
        if settings.liveTimer, timer.isRunning { kinds.insert(.timer) }
        if settings.liveMusic, media.isPlaying { kinds.insert(.music) }
        if settings.liveClaude, claudeActive { kinds.insert(.claude) }
        return kinds
    }

    /// Aktivní druhy seřazené podle času zapnutí (nejstarší první). Druhy, které model
    /// ještě nezaznamenal (stejný snímek jako změna), se připojí na konec.
    private var orderedActiveKinds: [LiveKind] {
        let active = activeKinds
        var ordered: [LiveKind] = vm.activityOrder.filter { active.contains($0) }
        ordered.append(contentsOf: LiveKind.allCases.filter { active.contains($0) && !ordered.contains($0) })
        return ordered
    }

    /// Nanejvýš dvě zobrazené aktivity: dvě naposledy spuštěné (starší vlevo, novější vpravo).
    private var shownActivities: [LiveActivity] {
        let ordered = orderedActiveKinds
        var picked: [LiveKind] = ordered.count > 2 ? Array(ordered.suffix(2)) : ordered
        if ordered.count > 2, meetingIsUrgent, !picked.contains(.meeting) {
            // Schůzka je starší než obě vybrané, takže zůstane vlevo.
            picked = [.meeting, picked[picked.count - 1]]
        }
        return picked.map { activity(for: $0) }
    }

    private func activity(for kind: LiveKind) -> LiveActivity {
        switch kind {
        case .meeting: return .meeting(upcomingMeetingStart ?? Date())
        case .timer: return .timer
        case .music: return .music
        case .claude: return .claude
        }
    }

    // MARK: Rozvržení

    private var closedLayout: ClosedLayout? {
        guard !vm.isOpen, vm.banner == nil, hudEvent == nil else { return nil }
        let shown = shownActivities
        if shown.count >= 2 { return dualLayout(older: shown[0], newer: shown[1]) }
        if let only = shown.first { return singleLayout(only) }
        return privacyOnlyLayout()
    }

    /// Bez aktivity jen tečky soukromí (symetricky), jinak obyčejný notch.
    private func privacyOnlyLayout() -> ClosedLayout? {
        guard privacyActive else { return nil }
        let width = sideWidth(content: 0, dots: true)
        return ClosedLayout(left: nil, right: nil, showsPrivacy: true,
                            leftWidth: width, rightWidth: width)
    }

    /// Jedna aktivita: ikona vlevo, detail vpravo, obě strany stejně široké.
    private func singleLayout(_ activity: LiveActivity) -> ClosedLayout {
        let left = SidePiece.icon(activity)
        let right = SidePiece.detail(activity)
        let leftWidth = sideWidth(content: pieceWidth(left), dots: false)
        let rightWidth = sideWidth(content: pieceWidth(right), dots: privacyActive)
        let width = max(leftWidth, rightWidth)
        return ClosedLayout(left: left, right: right, showsPrivacy: privacyActive,
                            leftWidth: width, rightWidth: width)
    }

    /// Dvě aktivity: každá strana je samostatný widget, obě strany stejně široké,
    /// takže tvar zůstává symetrický kolem fyzického notche.
    private func dualLayout(older: LiveActivity, newer: LiveActivity) -> ClosedLayout {
        let left = SidePiece.widget(older)
        let right = SidePiece.widget(newer)
        let leftWidth = sideWidth(content: pieceWidth(left), dots: false)
        let rightWidth = sideWidth(content: pieceWidth(right), dots: privacyActive)
        let width = max(leftWidth, rightWidth)
        return ClosedLayout(left: left, right: right, showsPrivacy: privacyActive,
                            leftWidth: width, rightWidth: width)
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
            // Ve dvojici aktivit je hudba jen obal alba, bez ekvalizéru.
            return inWidget ? 0 : CompactMetrics.equalizerWidth
        case .timer:
            return CompactMetrics.counterWidth(CompactMetrics.countdownText(timer.remaining))
        case .meeting:
            return CompactMetrics.counterWidth(CompactMetrics.counterTemplate)
        case .claude:
            if claude.waitingCount > 0 { return CompactMetrics.badgeWidth(claude.waitingCount) }
            return inWidget ? 0 : CompactMetrics.badgeWidth(max(claude.activeCount, 1))
        case .privacy:
            return 0
        }
    }

    // MARK: Tvar

    private func radii(hud: HUDLayout?) -> (top: CGFloat, bottom: CGFloat) {
        if vm.isOpen { return (NotchLayout.openTopRadius, NotchLayout.openBottomRadius) }
        if let hud { return (NotchLayout.closedTopRadius, hud.bottomRadius) }
        return (NotchLayout.closedTopRadius, NotchLayout.closedBottomRadius)
    }

    private func shapeSize(for layout: ClosedLayout?, hud: HUDLayout?) -> CGSize {
        if vm.isOpen { return NotchLayout.openSize }
        let n = vm.geometry.notchSize
        let height = n.height + CGFloat(settings.notchOverhang)
        // HUD: symetricky rozšířený (a případně vyšší) tvar, notch zůstává uprostřed.
        if let hud {
            return CGSize(width: n.width + 2 * NotchLayout.closedTopRadius + 2 * hud.side,
                          height: height + hud.extraHeight)
        }
        // Bez live activity (a během nabíjení) má tvar přesně šířku notche + horní zaoblení.
        let sides: CGFloat = (layout?.leftWidth ?? 0) + (layout?.rightWidth ?? 0)
        return CGSize(width: n.width + 2 * NotchLayout.closedTopRadius + sides, height: height)
    }

    var body: some View {
        let event = hudEvent
        let hudLayout: HUDLayout? = event.map { HUDLayout.forEvent($0) }
        let layout = closedLayout
        let size = shapeSize(for: layout, hud: hudLayout)
        let r = radii(hud: hudLayout)
        let hoverSides: HoverSides = hudLayout.map { HoverSides(left: $0.side, right: $0.side) }
            ?? HoverSides(left: layout?.leftWidth ?? 0, right: layout?.rightWidth ?? 0)
        // Strany jsou vždy stejně široké; posun je jen pojistka pro případnou asymetrii.
        let shift: CGFloat = layout.map { ($0.rightWidth - $0.leftWidth) / 2 } ?? 0
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: r.top, bottomRadius: r.bottom)
                    .fill(Color.black)

                content(layout: layout, event: event, hudLayout: hudLayout)
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
            .animation(hudSpring, value: hudLayout)
            .animation(hudSpring, value: event?.family)
        }
        .frame(width: NotchLayout.panelSize.width, height: NotchLayout.panelSize.height, alignment: .top)
        .preferredColorScheme(.dark)
        // Oblast pro najetí myší (NotchWindowController.closedHotRect) kopíruje šířku live activity i HUD.
        .onChange(of: hoverSides, initial: true) { _, sides in
            vm.closedSideWidths = (sides.left, sides.right)
        }
        // Pořadí zapnutí aktivit – podle něj se vybírají dvě nejnovější.
        .onChange(of: activeKinds, initial: true) { _, kinds in
            vm.updateActiveActivities(kinds)
        }
        .onChange(of: vm.isOpen) { _, open in
            if !open { vm.showMirror = false }
        }
    }

    @ViewBuilder
    private func content(layout: ClosedLayout?, event: HUDEvent?, hudLayout: HUDLayout?) -> some View {
        if vm.isOpen {
            OpenPanel()
                .transition(.asymmetric(
                    insertion: AnyTransition.opacity
                        .combined(with: .scale(scale: 0.94, anchor: .top))
                        .animation(.smooth(duration: 0.38).delay(0.1)),
                    removal: AnyTransition.opacity.animation(.easeOut(duration: 0.12))
                ))
        } else if let event = event, let hudLayout = hudLayout {
            HUDView(event: event,
                    revision: hud.revision,
                    metrics: HUDMetrics(side: hudLayout.side,
                                        notchWidth: vm.geometry.notchSize.width,
                                        topHeight: vm.geometry.notchSize.height + CGFloat(settings.notchOverhang),
                                        extraHeight: hudLayout.extraHeight),
                    accent: settings.accent.color)
                // Stejná rodina (např. opakované stisky hlasitosti) jen aktualizuje obsah, jiná vymění pohled.
                .id(event.family)
                .transition(.asymmetric(
                    insertion: AnyTransition.hudContent
                        .animation(reduceMotion
                                   ? Animation.easeOut(duration: 0.15)
                                   : Animation.spring(response: 0.4, dampingFraction: 0.82).delay(0.06)),
                    removal: AnyTransition.opacity.animation(.easeOut(duration: 0.12))
                ))
        } else if let layout = layout {
            CompactActivity(layout: layout, notchWidth: vm.geometry.notchSize.width)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        }
    }
}

/// Šířky oblasti vedle notche pro najetí myší.
private struct HoverSides: Equatable {
    var left: CGFloat
    var right: CGFloat
}

// MARK: - Live activity vedle notche

struct CompactActivity: View {
    let layout: ClosedLayout
    let notchWidth: CGFloat
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var media: MediaMonitor
    @EnvironmentObject private var timer: FocusTimer
    @ObservedObject private var claude = ClaudeMonitor.shared

    /// Přechod obsahu při změně rozvržení (jedna ↔ dvě aktivity, výměna aktivity).
    private var pieceTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.7))
    }

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
                    .id(piece)
                    .transition(pieceTransition)
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
                        .id(piece)
                        .transition(pieceTransition)
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
        case .music: return !inWidget
        case .claude: return claude.waitingCount > 0 || !inWidget
        case .privacy: return false
        case .timer, .meeting: return true
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
            compactText(CompactMetrics.countdownText(timer.remaining), color: Color.white)
        case .meeting(let start):
            // Odpočet do schůzky tiká každou sekundu jen po dobu, kdy je aktivita vidět.
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                compactText(CompactMetrics.countdownText(start.timeIntervalSince(context.date)),
                            color: Color.orange)
            }
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
            .contentTransition(.numericText(countsDown: true))
            .lineLimit(1)
            .fixedSize()
            .animation(.smooth(duration: 0.3), value: string)
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

    /// Mezera v hlavičce pro fyzický notch (+ 8 pt na každou stranu).
    private var notchGap: CGFloat { vm.geometry.notchSize.width + 16 }

    /// Šířka levé / pravé oblasti hlavičky vedle notche.
    private var headerSideWidth: CGFloat {
        max((NotchLayout.openSize.width - 2 * sideInset - notchGap) / 2, 0)
    }

    /// Šířka jedné záložky – zúží se, pokud by se všechny záložky nevešly vedle notche.
    private var tabWidth: CGFloat {
        let n = CGFloat(max(settings.visibleTabs.count, 1))
        // Kapsle má vnitřní okraj 3 pt na každé straně, mezi záložkami 2 pt.
        let fit = floor((headerSideWidth - 6 - 2 * (n - 1)) / n)
        return max(min(32, fit), 22)
    }

    private var cardTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Záložky vlevo a stavové prvky vpravo mají pevně stejně široké oblasti,
            // aby mezera pro fyzický notch byla přesně uprostřed a nic pod notch nezajelo.
            HStack(spacing: 0) {
                tabBar
                    .frame(width: headerSideWidth, alignment: .leading)
                Color.clear
                    .frame(width: notchGap)
                statusCluster
                    .frame(width: headerSideWidth, alignment: .trailing)
            }
            .frame(height: NotchLayout.controlHeight)
            .padding(.top, NotchLayout.margin)
            .padding(.horizontal, sideInset)

            ZStack {
                if vm.showMirror {
                    MirrorView()
                        .transition(cardTransition)
                } else {
                    tabContent
                }
            }
            .animation(.smooth(duration: 0.3), value: vm.tab)
            .animation(.smooth(duration: 0.3), value: vm.showMirror)
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
        .onChange(of: settings.mirrorButton) { _, enabled in
            if !enabled { vm.showMirror = false }
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
                              active: vm.tab == tab && !vm.showMirror,
                              accent: settings.accent.color,
                              width: tabWidth,
                              namespace: tabNamespace) {
                        withAnimation(.smooth(duration: 0.3)) {
                            vm.tab = tab
                            vm.showMirror = false
                        }
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
                if settings.mirrorButton {
                    GlassIconButton(symbol: "camera.fill",
                                    prominent: vm.showMirror,
                                    tint: settings.accent.color.opacity(0.45),
                                    size: NotchLayout.controlHeight) {
                        withAnimation(.smooth(duration: 0.3)) { vm.showMirror.toggle() }
                    }
                    .help(vm.showMirror ? "Skrýt zrcátko" : "Zrcátko")
                }
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
    let width: CGFloat
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: width)
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
