import SwiftUI

/// Nástroje: focus časovač (s progress glow kolem notche) a „nenechat Mac usnout“.
struct ToolsView: View {
    @EnvironmentObject private var timer: FocusTimer
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: NotchLayout.spacingM) {
            timerCard
            awakeCard
                .frame(width: NotchLayout.columnWidth)
        }
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: NotchLayout.spacingS) {
            CardLabel(symbol: "timer", title: "Focus časovač")
            Spacer(minLength: 0)
            if timer.isRunning {
                HStack {
                    Text(timer.display)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Color.white)
                    Spacer()
                    GlassIconButton(symbol: "stop.fill", size: 40) { timer.stop() }
                        .help("Zastavit časovač")
                }
                ThinProgress(value: timer.progress, tint: settings.accent.color, height: 6)
            } else {
                GlassContainer(spacing: NotchLayout.spacingS) {
                    HStack(spacing: NotchLayout.spacingS) {
                        ForEach([5, 15, 25, 50], id: \.self) { minutes in
                            GlassPill(title: "\(minutes) min") { timer.start(minutes: minutes) }
                        }
                    }
                }
                Text("Kolem notche se zobrazí průběh.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .glassCard()
        .animation(.smooth(duration: 0.3), value: timer.isRunning)
    }

    private var awakeCard: some View {
        VStack(alignment: .leading, spacing: NotchLayout.spacingS) {
            CardLabel(symbol: "moon.zzz.fill", title: "Nenechat Mac usnout")
            Spacer(minLength: 0)
            HStack(spacing: NotchLayout.spacingS) {
                Toggle("", isOn: $timer.keepAwake)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(settings.accent.color)
                Text(timer.keepAwake ? "Displej zůstane zapnutý." : "Vypnuto.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .glassCard()
    }
}
