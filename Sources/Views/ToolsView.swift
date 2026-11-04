import SwiftUI

/// Nástroje: focus časovač s prstencem, předvolby, Soustředění (automatické „Nerušit“)
/// a „nenechat Mac usnout“.
struct ToolsView: View {
    @EnvironmentObject private var timer: FocusTimer
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var focus = FocusController.shared
    @State private var selectedMinutes: Int = 30

    private let presets: [Int] = [5, 15, 30, 45, 60, 90, 120, 180]
    private let presetColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: NotchLayout.spacingM) {
            timerCard
            VStack(spacing: NotchLayout.spacingM) {
                focusCard
                awakeCard
            }
            .frame(width: NotchLayout.columnWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            focus.refreshPermission()
        }
        .onReceive(permissionTimer) { _ in
            if settings.focusWithTimer { focus.refreshPermission() }
        }
    }

    // MARK: - Časovač

    private var timerCard: some View {
        HStack(alignment: .center, spacing: NotchLayout.spacingM) {
            ring
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: NotchLayout.spacingS) {
                    CardLabel(symbol: "timer", title: "Focus časovač")
                    Spacer(minLength: 0)
                    if timer.isRunning, let end = timer.endTime {
                        Text("Konec v \(end.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                presetGrid
                    .opacity(timer.isRunning ? 0.4 : 1)
                    .disabled(timer.isRunning)
                HStack(spacing: NotchLayout.spacingS) {
                    if timer.isRunning {
                        GlassPill(title: "Zastavit", symbol: "stop.fill", tint: Color.red.opacity(0.35)) {
                            timer.stop()
                        }
                        .help("Zastavit časovač")
                    } else {
                        GlassPill(title: "Spustit", symbol: "play.fill", tint: settings.accent.color.opacity(0.45)) {
                            timer.start(minutes: selectedMinutes)
                        }
                        .help("Spustit časovač na \(selectedMinutes) min")
                    }
                    if let error = timer.focusError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(error)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .help(error)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .glassCard(padding: NotchLayout.spacingM)
        .animation(.smooth(duration: 0.3), value: timer.isRunning)
        .animation(.smooth(duration: 0.3), value: timer.focusError)
    }

    private var ring: some View {
        let remainingFraction: Double = timer.isRunning ? 1 - timer.progress : 1
        let lineWidth: CGFloat = 6
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(remainingFraction))
                .stroke(
                    settings.accent.color.opacity(timer.isRunning ? 1 : 0.35),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: remainingFraction)
            VStack(spacing: 0) {
                Text(ringText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.white)
                Text(timer.isRunning ? "zbývá" : "připraveno")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(.horizontal, lineWidth + 6)
        }
        .padding(lineWidth / 2)
        .frame(width: 110, height: 110)
    }

    /// Čas v prstenci: „mm:ss“, od hodiny výš „h:mm:ss“ (předvolby až 180 min).
    private var ringText: String {
        let secs = timer.isRunning ? Int(ceil(timer.remaining)) : selectedMinutes * 60
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// Předvolby v mřížce 4 × 2 – větší skleněné kapsle, snadno se na ně kliká.
    private var presetGrid: some View {
        LazyVGrid(columns: presetColumns, spacing: 6) {
            ForEach(presets, id: \.self) { minutes in
                PresetChip(minutes: minutes,
                           isSelected: minutes == selectedMinutes,
                           tint: settings.accent.color) {
                    selectedMinutes = minutes
                }
            }
        }
    }

    // MARK: - Pravý sloupec

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: NotchLayout.spacingS) {
                CardLabel(symbol: "moon.fill", title: "Soustředění")
                Spacer(minLength: 0)
                Toggle("", isOn: $settings.focusWithTimer)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .tint(settings.accent.color)
            }
            HStack(spacing: 5) {
                Circle()
                    .fill(focusStatus.color)
                    .frame(width: 6, height: 6)
                Text(focusStatus.text)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if settings.focusWithTimer && focus.needsAccessibility {
                    Spacer(minLength: 0)
                    Button {
                        MediaKeyInterceptor.shared.requestAccess()
                        focus.refreshPermission()
                    } label: {
                        Text("Povolit")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(settings.accent.color)
                    }
                    .buttonStyle(.plain)
                    .help("Povolit NotchMaxu Zpřístupnění, aby mohl přepínat Nerušit")
                }
            }
            .help(focusStatus.text)
        }
        .glassCard(padding: NotchLayout.spacingM)
        .onChange(of: settings.focusWithTimer) { _, isOn in
            if isOn { focus.refreshPermission() }
            if !isOn && !timer.focusActive { timer.focusError = nil }
        }
    }

    private var awakeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: NotchLayout.spacingS) {
                CardLabel(symbol: "cup.and.saucer.fill", title: "Nenechat usnout")
                Spacer(minLength: 0)
                Toggle("", isOn: $timer.keepAwake)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .tint(settings.accent.color)
            }
            Text(timer.keepAwake ? "Displej zůstane zapnutý." : "Vypnuto.")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
        }
        .glassCard(padding: NotchLayout.spacingM)
    }

    private var focusStatus: (text: String, color: Color) {
        if !settings.focusWithTimer {
            return ("Vypnuto", Color.white.opacity(0.3))
        }
        if focus.needsAccessibility {
            return ("Potřebuje Zpřístupnění", Color.orange)
        }
        if timer.focusError != nil {
            return ("Chyba – viz časovač", Color.orange)
        }
        if timer.focusActive {
            return ("Nerušit zapnuto s časovačem", Color.green)
        }
        return ("Připraveno – zapne Nerušit", Color.green)
    }
}

/// Skleněná kapsle s předvolbou: „90 min“, od dvou hodin „2 h“.
private struct PresetChip: View {
    let minutes: Int
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    private var value: String {
        minutes >= 120 && minutes % 60 == 0 ? "\(minutes / 60)" : "\(minutes)"
    }

    private var unit: String {
        minutes >= 120 && minutes % 60 == 0 ? "h" : "min"
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 9, weight: .medium))
                    .opacity(0.6)
            }
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(NotchGlassButtonStyle(shape: Capsule(), tint: isSelected ? tint.opacity(0.5) : nil))
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? tint.opacity(0.9) : Color.clear, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .hoverScale(1.04)
        .help("\(minutes) minut")
    }
}
