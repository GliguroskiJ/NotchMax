import SwiftUI

/// Nástroje: focus časovač s prstencem, předvolby, Soustředění (automatické „Nerušit“)
/// a „nenechat Mac usnout“.
struct ToolsView: View {
    @EnvironmentObject private var timer: FocusTimer
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var focus = FocusController.shared
    @State private var selectedMinutes: Int = 25

    private let presets: [Int] = [5, 15, 25, 45, 60]
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
        HStack(alignment: .center, spacing: NotchLayout.spacingL) {
            ring
            VStack(alignment: .leading, spacing: NotchLayout.spacingS) {
                CardLabel(symbol: "timer", title: "Focus časovač")
                Spacer(minLength: 0)
                presetChips
                    .opacity(timer.isRunning ? 0.4 : 1)
                    .disabled(timer.isRunning)
                HStack(spacing: NotchLayout.spacingS) {
                    if timer.isRunning {
                        GlassPill(title: "Zastavit", symbol: "stop.fill", tint: Color.red.opacity(0.35)) {
                            timer.stop()
                        }
                        .help("Zastavit časovač")
                        if let end = timer.endTime {
                            Text("Konec v \(end.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    } else {
                        GlassPill(title: "Spustit", symbol: "play.fill", tint: settings.accent.color.opacity(0.45)) {
                            timer.start(minutes: selectedMinutes)
                        }
                        .help("Spustit časovač na \(selectedMinutes) min")
                    }
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard()
        .animation(.smooth(duration: 0.3), value: timer.isRunning)
        .animation(.smooth(duration: 0.3), value: timer.focusError)
    }

    private var ring: some View {
        let remainingFraction: Double = timer.isRunning ? 1 - timer.progress : 1
        let lineWidth: CGFloat = 7
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
                Text(timer.isRunning ? timer.display : String(format: "%02d:00", selectedMinutes))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.white)
                Text(timer.isRunning ? "zbývá" : "připraveno")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .padding(lineWidth / 2)
        .frame(width: 120, height: 120)
    }

    private var presetChips: some View {
        GlassContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { minutes in
                    PresetChip(minutes: minutes,
                               isSelected: minutes == selectedMinutes,
                               tint: settings.accent.color) {
                        selectedMinutes = minutes
                    }
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

/// Kulatý čip s počtem minut.
private struct PresetChip: View {
    let minutes: Int
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: -1) {
                Text("\(minutes)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("min")
                    .font(.system(size: 7, weight: .medium))
                    .opacity(0.6)
            }
            .foregroundStyle(Color.white)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .notchGlass(in: Circle(), tint: isSelected ? tint.opacity(0.5) : nil, interactive: true)
        .overlay(
            Circle().strokeBorder(isSelected ? tint.opacity(0.9) : Color.clear, lineWidth: 1)
        )
        .hoverScale(1.06)
        .help("\(minutes) minut")
    }
}
