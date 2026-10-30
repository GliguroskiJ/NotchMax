import SwiftUI

/// Nástroje: focus časovač (s progress glow kolem notche) a „nenechat Mac usnout“.
struct ToolsView: View {
    @EnvironmentObject private var timer: FocusTimer
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Focus časovač", systemImage: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                if timer.isRunning {
                    HStack {
                        Text(timer.display)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                        Spacer()
                        GlassIconButton(symbol: "stop.fill", size: 36) { timer.stop() }
                    }
                    ProgressView(value: timer.progress).tint(settings.accent.color)
                } else {
                    GlassContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach([5, 15, 25, 50], id: \.self) { minutes in
                                GlassPill(title: "\(minutes) min") { timer.start(minutes: minutes) }
                            }
                        }
                    }
                    Text("Kolem notche se zobrazí průběh.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .cardStyle()

            VStack(alignment: .leading, spacing: 10) {
                Label("Nenechat Mac usnout", systemImage: "moon.zzz.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                Toggle("", isOn: $timer.keepAwake)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text(timer.keepAwake ? "Displej zůstane zapnutý." : "Vypnuto.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .cardStyle()
            .frame(width: 190)
        }
    }
}
