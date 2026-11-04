import SwiftUI
import AppKit

// MARK: - Rozměry HUD

/// Tvar HUD: o kolik se notch rozšíří na každou stranu a o kolik naroste pod notch.
/// HUD je vždy symetrický, takže fyzický notch zůstává přesně uprostřed.
struct HUDLayout: Equatable {
    /// Šířka obsahu na každé straně fyzického notche (bez horního zaoblení tvaru).
    var side: CGFloat
    /// O kolik je HUD vyšší než zavřený notch (obsah pod notchem).
    var extraHeight: CGFloat
    /// Vlastní spodní zaoblení (nil = výchozí podle výšky).
    var customBottomRadius: CGFloat? = nil

    var bottomRadius: CGFloat {
        if let customBottomRadius { return customBottomRadius }
        return extraHeight > 0 ? 22 : NotchLayout.closedBottomRadius
    }

    static func forEvent(_ event: HUDEvent) -> HUDLayout {
        switch event {
        case .volume, .brightness, .keyboardBrightness:
            // Mírné rozšíření a nízký pruh pod notchem pro tenký ukazatel úrovně.
            return HUDLayout(side: 50, extraHeight: 16, customBottomRadius: 16)
        case .media:
            // Jen malý obal alba vlevo a symbol vpravo.
            return HUDLayout(side: 46, extraHeight: 0)
        case .headphones:
            return HUDLayout(side: 64, extraHeight: 62)
        case .focus:
            return HUDLayout(side: 92, extraHeight: 0)
        case .claude(_, _, let message):
            let hasMessage: Bool = !(message ?? "").isEmpty
            return HUDLayout(side: 108, extraHeight: hasMessage ? 26 : 0)
        case .notification:
            return HUDLayout(side: 76, extraHeight: 78)
        }
    }
}

/// Konkrétní rozměry pro vykreslení HUD.
struct HUDMetrics {
    let side: CGFloat
    let notchWidth: CGFloat
    /// Výška horního řádku (= výška zavřeného notche včetně přesahu).
    let topHeight: CGFloat
    let extraHeight: CGFloat

    static let outerPadding: CGFloat = 12
    static let innerPadding: CGFloat = 6

    var bodyWidth: CGFloat { 2 * side + notchWidth }
}

// MARK: - Kostra

/// Rozvržení HUD: obsah vlevo a vpravo od notche, volitelně další obsah pod notchem.
struct HUDScaffold<Left: View, Right: View, Bottom: View>: View {
    let metrics: HUDMetrics
    let bottomInset: CGFloat
    let left: Left
    let right: Right
    let bottom: Bottom

    init(metrics: HUDMetrics,
         bottomInset: CGFloat = 14,
         @ViewBuilder left: () -> Left,
         @ViewBuilder right: () -> Right,
         @ViewBuilder bottom: () -> Bottom) {
        self.metrics = metrics
        self.bottomInset = bottomInset
        self.left = left()
        self.right = right()
        self.bottom = bottom()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                left
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, HUDMetrics.outerPadding)
                    .padding(.trailing, HUDMetrics.innerPadding)
                    .frame(width: metrics.side, height: metrics.topHeight)
                Color.clear
                    .frame(width: metrics.notchWidth, height: metrics.topHeight)
                right
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, HUDMetrics.innerPadding)
                    .padding(.trailing, HUDMetrics.outerPadding)
                    .frame(width: metrics.side, height: metrics.topHeight)
            }
            if metrics.extraHeight > 0 {
                bottom
                    .padding(.horizontal, bottomInset)
                    .padding(.bottom, min(bottomInset, 8))
                    .frame(width: metrics.bodyWidth, height: metrics.extraHeight)
            }
        }
        .padding(.horizontal, NotchLayout.closedTopRadius)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Kořen HUD

struct HUDView: View {
    let event: HUDEvent
    let revision: Int
    let metrics: HUDMetrics
    let accent: Color

    var body: some View {
        switch event {
        case .volume(let level, let muted):
            HUDLevelView(kind: .volume(muted: muted), level: level, revision: revision,
                         metrics: metrics, accent: accent)
        case .brightness(let level):
            HUDLevelView(kind: .brightness, level: level, revision: revision,
                         metrics: metrics, accent: accent)
        case .keyboardBrightness(let level):
            HUDLevelView(kind: .keyboard, level: level, revision: revision,
                         metrics: metrics, accent: accent)
        case .media(let action, _, _):
            // Bez textu – jen obal alba a symbol (titulek by přetékal).
            HUDMediaView(action: action, revision: revision, metrics: metrics, accent: accent)
        case .headphones(let name, let model, let left, let right, let caseLevel, let connected):
            HUDHeadphonesView(name: name, model: model, left: left, right: right, caseLevel: caseLevel,
                              connected: connected, revision: revision, metrics: metrics)
        case .focus(let name, let symbol, let enabled):
            HUDFocusView(name: name, symbol: symbol, enabled: enabled, revision: revision, metrics: metrics)
        case .claude(let project, let needsAttention, let message):
            HUDClaudeView(project: project, needsAttention: needsAttention, message: message,
                          revision: revision, metrics: metrics)
        case .notification(let appName, let bundleID, let title, let text):
            HUDNotificationView(appName: appName, bundleID: bundleID, title: title, text: text,
                                revision: revision, metrics: metrics)
        }
    }
}

/// Přechod obsahu HUD: rozmazání + zmenšení k hornímu okraji.
struct HUDContentTransitionModifier: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .top)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static var hudContent: AnyTransition {
        .modifier(active: HUDContentTransitionModifier(blur: 6, scale: 0.86, opacity: 0),
                  identity: HUDContentTransitionModifier(blur: 0, scale: 1, opacity: 1))
    }
}

/// Symbol, který v systému existuje; jinak náhradní.
private func hudSymbol(_ name: String, fallback: String) -> String {
    NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : fallback
}

/// Spustí animaci znovu od začátku: nejprve bez animace nastaví výchozí stav, pak animuje.
@MainActor
private func hudRestart(reset: () -> Void, animate: @escaping @MainActor () -> Void) {
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t) { reset() }
    // Krátká prodleva, aby se výchozí stav stihl vykreslit (jinak by se změny sloučily).
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 16_000_000)
        animate()
    }
}

// MARK: - Hlasitost / jas / podsvícení klávesnice

struct HUDLevelView: View {
    enum Kind: Equatable {
        case volume(muted: Bool)
        case brightness
        case keyboard
    }

    let kind: Kind
    let level: Double
    let revision: Int
    let metrics: HUDMetrics
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(level, 0), 1) }

    private var muted: Bool {
        if case .volume(let m) = kind { return m }
        return false
    }

    private var shown: Double { muted ? 0 : clamped }

    /// Jednoduchý HUD: malá ikona vlevo, drobné procento vpravo, tenký pruh pod notchem.
    var body: some View {
        HUDScaffold(metrics: metrics, bottomInset: 16) {
            icon
                .frame(width: 16, height: 16)
        } right: {
            Text("\(Int((shown * 100).rounded())) %")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(muted ? 0.5 : 0.8))
                .contentTransition(.numericText())
                .lineLimit(1)
                .fixedSize()
                .animation(.smooth(duration: 0.2), value: shown)
        } bottom: {
            HUDLevelBar(level: shown, tint: muted ? Color.white.opacity(0.35) : accent)
                .frame(height: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .volume(let isMuted):
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill",
                  variableValue: isMuted ? 1 : clamped)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isMuted ? Color.white.opacity(0.6) : Color.white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: reduceMotion ? 0 : revision)
        case .brightness:
            HUDSunIcon(level: clamped)
                .scaleEffect(0.72)
        case .keyboard:
            Image(systemName: clamped < 0.01 ? "light.min" : "light.max")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55 + 0.45 * clamped))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: reduceMotion ? 0 : revision)
                .animation(.smooth(duration: 0.2), value: clamped)
        }
    }
}

/// Slunce, jehož paprsky se s jasem prodlužují a otáčejí.
struct HUDSunIcon: View {
    let level: Double

    var body: some View {
        let l = CGFloat(level)
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 7 + 2 * l, height: 7 + 2 * l)
            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 1.8, height: 2 + 3.5 * l)
                    .offset(y: -(6.5 + 2 * l))
                    .rotationEffect(.degrees(Double(i) * 45))
            }
        }
        .rotationEffect(.degrees(level * 90))
        .opacity(0.6 + 0.4 * level)
        .frame(width: 22, height: 22)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: level)
    }
}

/// Tenká skleněná kapsle s výplní v barvě zvýraznění (plní se zleva doprava, pružně).
struct HUDLevelBar: View {
    let level: Double
    let tint: Color

    var body: some View {
        let clamped: CGFloat = CGFloat(min(max(level, 0), 1))
        GeometryReader { geo in
            let width: CGFloat = geo.size.width * clamped
            ZStack(alignment: .leading) {
                Color.clear
                    .notchGlass(in: Capsule(), tint: Color.white.opacity(0.06))
                Capsule()
                    .fill(tint)
                    .frame(width: clamped > 0 ? max(width, geo.size.height) : 0)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: level)
    }
}

// MARK: - Média

struct HUDMediaView: View {
    let action: MediaAction
    let revision: Int
    let metrics: HUDMetrics
    let accent: Color
    @EnvironmentObject private var media: MediaMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Právě zobrazený obal alba (výměna se animuje otočením).
    @State private var art: NSImage?
    /// Mění se s každou výměnou obalu – identita pro přechod.
    @State private var artToken: Int = 0
    @State private var symbolName: String
    @State private var swoosh: CGFloat = 0
    @State private var swooshOpacity: Double = 1

    private static let artSize: CGFloat = 20

    init(action: MediaAction, revision: Int, metrics: HUDMetrics, accent: Color) {
        self.action = action
        self.revision = revision
        self.metrics = metrics
        self.accent = accent
        _symbolName = State(initialValue: HUDMediaView.symbol(for: action))
    }

    private static func symbol(for action: MediaAction) -> String {
        switch action {
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        }
    }

    private var direction: CGFloat {
        switch action {
        case .next: return 1
        case .previous: return -1
        case .play, .pause: return 0
        }
    }

    var body: some View {
        HUDScaffold(metrics: metrics) {
            artView
        } right: {
            symbolView
        } bottom: {
            EmptyView()
        }
        .onAppear { setup() }
        .onChange(of: revision) { _, _ in refresh() }
        .onChange(of: media.artwork) { _, image in
            if let image { swapArt(to: image) }
        }
    }

    // MARK: Obal alba

    private var artView: some View {
        ZStack {
            artTile(art)
                .id(artToken)
                .transition(artTransition)
        }
        .frame(width: Self.artSize, height: Self.artSize)
    }

    @ViewBuilder
    private func artTile(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Self.artSize, height: Self.artSize)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: Self.artSize, height: Self.artSize)
        }
    }

    /// Nový obal se otočí dovnitř ze směru přeskočení, starý se otočí ven.
    private var artTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let dir: CGFloat = direction == 0 ? 1 : direction
        let identity = HUDArtFlipModifier(angle: 0, offsetX: 0, opacity: 1)
        return .asymmetric(
            insertion: .modifier(active: HUDArtFlipModifier(angle: -85 * Double(dir), offsetX: 8 * dir, opacity: 0),
                                 identity: identity),
            removal: .modifier(active: HUDArtFlipModifier(angle: 85 * Double(dir), offsetX: -8 * dir, opacity: 0),
                               identity: identity)
        )
    }

    private func swapArt(to image: NSImage) {
        if let current = art, current === image { return }
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.48, dampingFraction: 0.8)
        withAnimation(animation) {
            art = image
            artToken &+= 1
        }
    }

    // MARK: Symbol

    private var symbolView: some View {
        Image(systemName: symbolName)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(accent)
            .contentTransition(.symbolEffect(.replace))
            .offset(x: swoosh)
            .opacity(swooshOpacity)
            .frame(width: Self.artSize, height: Self.artSize)
    }

    // MARK: Animace

    private func setup() {
        let bridge = MediaHUDBridge.shared
        let current: NSImage? = media.artwork
        if direction != 0, !reduceMotion, bridge.artworkChangedRecently,
           let previous = bridge.previousArtwork, let current, current !== previous {
            // Obal nové skladby už je načtený → začít starým a hned ho otočit na nový.
            art = previous
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                swapArt(to: current)
            }
        } else {
            // Obal nové skladby se teprve načítá → zatím poslední známý, výměnu spustí onChange.
            art = current ?? bridge.lastArtwork
        }
        animateSymbol()
    }

    private func refresh() {
        if let current = media.artwork { swapArt(to: current) }
        animateSymbol()
    }

    private func animateSymbol() {
        let target = Self.symbol(for: action)
        if reduceMotion {
            symbolName = target
            return
        }
        if direction == 0 {
            // Play / pauza: symbol se promění z opačného stavu.
            let from: String = action == .play ? "pause.fill" : "play.fill"
            hudRestart {
                symbolName = from
            } animate: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { symbolName = target }
            }
        } else {
            symbolName = target
            let dir = direction
            hudRestart {
                swoosh = -dir * 10
                swooshOpacity = 0.2
            } animate: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                    swoosh = 0
                    swooshOpacity = 1
                }
            }
        }
    }
}

/// Otočení obalu alba kolem svislé osy s posunem a prolnutím.
struct HUDArtFlipModifier: ViewModifier {
    let angle: Double
    let offsetX: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .offset(x: offsetX)
            .opacity(opacity)
    }
}

/// Jednořádkový text, který při přetečení pomalu projede (při omezení pohybu jen zeslábne na konci).
struct HUDMarquee: View {
    let text: String
    var size: CGFloat = 11
    var weight: Font.Weight = .semibold
    var color: Color = Color.white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var start = Date()

    private var overflow: CGFloat { max(0, textWidth - boxWidth) }

    var body: some View {
        let scrolls: Bool = overflow > 1 && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !scrolls)) { context in
            let x: CGFloat = scrolls ? offset(at: context.date) : 0
            Text(text)
                .font(.system(size: size, weight: weight, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .background(
                    GeometryReader { g in
                        Color.clear
                            .onAppear { textWidth = g.size.width }
                            .onChange(of: g.size.width) { _, w in textWidth = w }
                    }
                )
                .offset(x: -x)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: ceil(size * 1.35))
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { boxWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in boxWidth = w }
            }
        )
        .clipped()
        .mask {
            LinearGradient(stops: [
                .init(color: Color.black, location: 0),
                .init(color: Color.black, location: overflow > 1 ? 0.85 : 1),
                .init(color: Color.black.opacity(overflow > 1 ? 0 : 1), location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        }
        .onChange(of: text) { _, _ in start = Date() }
    }

    private func offset(at date: Date) -> CGFloat {
        let speed: Double = 28
        let pause: Double = 1.2
        let travel: Double = max(Double(overflow) / speed, 0.1)
        let cycle: Double = pause + travel + pause
        let t: Double = date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
        let p: Double = min(max((t - pause) / travel, 0), 1)
        return CGFloat(p) * overflow
    }
}

// MARK: - Sluchátka

struct HUDHeadphonesView: View {
    let name: String
    let model: HeadphoneModel
    let left: Int?
    let right: Int?
    let caseLevel: Int?
    let connected: Bool
    let revision: Int
    let metrics: HUDMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin: Double = 0

    private var minBudLevel: Int? { [left, right].compactMap { $0 }.min() }

    var body: some View {
        HUDScaffold(metrics: metrics) {
            Circle()
                .fill(connected ? Color.green : Color.white.opacity(0.35))
                .frame(width: 6, height: 6)
                .shadow(color: connected ? Color.green.opacity(0.7) : Color.clear, radius: 3)
        } right: {
            if let level = minBudLevel {
                Text("\(level) %")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(level > 20 ? Color.green : Color.red)
                    .lineLimit(1)
                    .fixedSize()
            }
        } bottom: {
            HStack(spacing: 10) {
                symbolView
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(connected ? "Připojeno" : "Odpojeno")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(connected ? Color.green : Color.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    if let left {
                        HUDBatteryRing(level: left, label: "L", revision: revision)
                    }
                    if let right {
                        HUDBatteryRing(level: right, label: "P", revision: revision)
                    }
                    if let caseLevel {
                        HUDBatteryRing(level: caseLevel, label: "Pouzdro", revision: revision)
                    }
                }
                .opacity(connected ? 1 : 0.45)
            }
        }
        .onAppear { runSpin() }
        .onChange(of: revision) { _, _ in runSpin() }
    }

    private var symbolView: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            let float: CGFloat = reduceMotion ? 0 : CGFloat(sin(t * 2 * Double.pi / 2.6)) * 2
            Image(systemName: hudSymbol(model.symbol, fallback: "headphones"))
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Color.white)
                .offset(y: float)
        }
        .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .frame(width: 44, height: 44)
        .opacity(connected ? 1 : 0.6)
    }

    private func runSpin() {
        guard !reduceMotion else { return }
        withAnimation(.timingCurve(0.2, 0.8, 0.25, 1, duration: 1.2)) { spin += 360 }
    }
}

/// Kroužek baterie (zelený nad 20 %, červený do 20 %).
struct HUDBatteryRing: View {
    let level: Int
    let label: String
    let revision: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    private var fraction: Double { Double(min(max(level, 0), 100)) / 100 }
    private var color: Color { level > 20 ? Color.green : Color.red }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.5), radius: 2)
                Text("\(level)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: 28, height: 28)
            Text(label)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .fixedSize()
        }
        .onAppear { fill() }
        .onChange(of: revision) { _, _ in fill() }
        .onChange(of: level) { _, _ in fill() }
    }

    private func fill() {
        let target = fraction
        if reduceMotion {
            progress = target
            return
        }
        hudRestart {
            progress = 0
        } animate: {
            withAnimation(.easeOut(duration: 0.9).delay(0.25)) { progress = target }
        }
    }
}

// MARK: - Soustředění

struct HUDFocusView: View {
    let name: String
    let symbol: String
    let enabled: Bool
    let revision: Int
    let metrics: HUDMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: CGFloat = 1
    @State private var burst: Double = 1

    private let tint = Color(red: 0.56, green: 0.5, blue: 1.0)

    var body: some View {
        HUDScaffold(metrics: metrics) {
            badge
        } right: {
            VStack(alignment: .trailing, spacing: 0) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(enabled ? "Zapnuto" : "Vypnuto")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(enabled ? tint : Color.white.opacity(0.55))
                    .lineLimit(1)
            }
        } bottom: {
            EmptyView()
        }
        .onAppear { restart() }
        .onChange(of: revision) { _, _ in restart() }
    }

    private var badge: some View {
        let d: CGFloat = max(min(metrics.topHeight - 8, 26), 18)
        return ZStack {
            Circle()
                .stroke(tint, lineWidth: 1.5)
                .frame(width: d, height: d)
                .scaleEffect(1 + 0.6 * CGFloat(burst))
                .opacity(1 - burst)
                .allowsHitTesting(false)
            Image(systemName: hudSymbol(symbol, fallback: "moon.fill"))
                .font(.system(size: d * 0.48, weight: .semibold))
                .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.6))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: d, height: d)
                .notchGlass(in: Circle(), tint: enabled ? tint.opacity(0.45) : Color.white.opacity(0.04))
                .scaleEffect(pop)
        }
        .frame(width: d, height: d)
    }

    private func restart() {
        guard !reduceMotion else {
            pop = 1
            burst = 1
            return
        }
        hudRestart {
            pop = 0.4
            burst = 0
        } animate: {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.55)) { pop = 1 }
            withAnimation(.easeOut(duration: 0.75).delay(0.08)) { burst = 1 }
        }
    }
}

// MARK: - Claude

struct HUDClaudeView: View {
    let project: String
    let needsAttention: Bool
    let message: String?
    let revision: Int
    let metrics: HUDMetrics

    var body: some View {
        HUDScaffold(metrics: metrics) {
            HStack(spacing: 6) {
                HUDShimmerSparkles(color: CompactMetrics.claudeColor, revision: revision)
                    .frame(width: 18, height: 18)
                Text(project)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } right: {
            HStack(spacing: 4) {
                Image(systemName: needsAttention ? "exclamationmark.bubble.fill" : "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(needsAttention ? "Čeká na tebe" : "Hotovo")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(needsAttention ? Color.orange : Color.green)
        } bottom: {
            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Ikona Claude s přejíždějícím leskem.
struct HUDShimmerSparkles: View {
    let color: Color
    let revision: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            let phase: CGFloat = CGFloat(t.truncatingRemainder(dividingBy: 1.8) / 1.8)
            let x0: CGFloat = -1.2 + 2.4 * phase
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    reduceMotion
                        ? AnyShapeStyle(color)
                        : AnyShapeStyle(LinearGradient(colors: [color, color, Color.white, color, color],
                                                       startPoint: UnitPoint(x: x0, y: 0.2),
                                                       endPoint: UnitPoint(x: x0 + 1, y: 0.8)))
                )
                .symbolEffect(.bounce, value: reduceMotion ? 0 : revision)
        }
    }
}

// MARK: - Oznámení

struct HUDNotificationView: View {
    let appName: String
    let bundleID: String?
    let title: String
    let text: String?
    let revision: Int
    let metrics: HUDMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var rise: CGFloat = 0

    private var appURL: URL? {
        guard let id = bundleID, !id.isEmpty else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    var body: some View {
        let url = appURL
        let cardShape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        HUDScaffold(metrics: metrics, bottomInset: 7) {
            HStack(spacing: 5) {
                appIcon(url, size: 14)
                Text(appName)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } right: {
            Text("teď")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)
                .fixedSize()
        } bottom: {
            HStack(alignment: .center, spacing: 10) {
                appIcon(url, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let text, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(CardGlass(shape: cardShape))
            .overlay(
                cardShape
                    .fill(Color.white.opacity(hovering ? 0.06 : 0))
                    .allowsHitTesting(false)
            )
            .contentShape(cardShape)
            .scaleEffect(hovering ? 1.015 : 1)
            .offset(y: rise)
            .animation(.smooth(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
            .onTapGesture { openApp(url) }
            .help("Otevřít \(appName)")
        }
        .onAppear { runRise() }
        .onChange(of: revision) { _, _ in runRise() }
    }

    @ViewBuilder
    private func appIcon(_ url: URL?, size: CGFloat) -> some View {
        if let url {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "bell.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(LinearGradient(colors: [Color.orange, Color.red],
                                             startPoint: .top, endPoint: .bottom))
                )
        }
    }

    private func openApp(_ url: URL?) {
        HUDCenter.shared.dismiss()
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    private func runRise() {
        guard !reduceMotion else { return }
        hudRestart {
            rise = 10
        } animate: {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { rise = 0 }
        }
    }
}
