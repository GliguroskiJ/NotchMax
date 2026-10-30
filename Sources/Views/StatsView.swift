import SwiftUI

// MARK: - Sparkline

/// Čára grafu z posledních vzorků; vzorky se řadí zprava (nejnovější vpravo).
struct SparklineShape: Shape {
    var values: [Double]
    var maxValue: Double
    var capacity: Int = SystemStats.historyLength
    /// Uzavřít plochu pod čarou (pro výplň gradientem).
    var closed: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, rect.width > 0, rect.height > 0 else { return path }
        let top: Double = max(maxValue, 0.000_001)
        let step: CGFloat = rect.width / CGFloat(max(capacity - 1, 1))
        let n = values.count

        func point(_ i: Int) -> CGPoint {
            let x = rect.maxX - CGFloat(n - 1 - i) * step
            let ratio = CGFloat(min(max(values[i] / top, 0), 1))
            let y = rect.maxY - ratio * rect.height
            return CGPoint(x: x, y: y)
        }

        let first = point(0)
        path.move(to: closed ? CGPoint(x: first.x, y: rect.maxY) : first)
        if closed { path.addLine(to: first) }
        for i in 1..<n {
            path.addLine(to: point(i))
        }
        if closed {
            path.addLine(to: CGPoint(x: point(n - 1).x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// Sparkline: jemný gradient pod čarou + čára v barvě akcentu.
struct Sparkline: View {
    var values: [Double]
    var maxValue: Double
    var tint: Color

    var body: some View {
        ZStack {
            SparklineShape(values: values, maxValue: maxValue, closed: true)
                .fill(
                    LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                )
            SparklineShape(values: values, maxValue: maxValue)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - StatsView

/// Systémové statistiky: mřížka 2×2 (CPU, Paměť, Síť, Disk).
struct StatsView: View {
    @ObservedObject private var stats = SystemStats.shared

    private var tint: Color { AppSettings.shared.accent.color }

    var body: some View {
        VStack(spacing: NotchLayout.spacingM) {
            HStack(spacing: NotchLayout.spacingM) {
                cpuCard
                memoryCard
            }
            HStack(spacing: NotchLayout.spacingM) {
                networkCard
                diskCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    // MARK: Karty

    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            CardLabel(symbol: "cpu", title: "Procesor")
            HStack(alignment: .bottom, spacing: NotchLayout.spacingS) {
                Text("\(Int((stats.cpu * 100).rounded())) %")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Sparkline(values: stats.cpuHistory, maxValue: 1, tint: tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .glassCard(padding: NotchLayout.spacingM)
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            CardLabel(symbol: "memorychip", title: "Paměť")
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formatNumber(stats.memoryUsedGB))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                Text("/ \(formatNumber(stats.memoryTotalGB)) GB")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .lineLimit(1)
            ThinProgress(value: stats.memoryUsedFraction, tint: tint)
        }
        .glassCard(padding: NotchLayout.spacingM)
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            CardLabel(symbol: "arrow.up.arrow.down", title: "Síť")
            HStack(alignment: .bottom, spacing: NotchLayout.spacingS) {
                VStack(alignment: .leading, spacing: 1) {
                    rateRow(symbol: "arrow.down", value: stats.netDownBytesPerSec)
                    rateRow(symbol: "arrow.up", value: stats.netUpBytesPerSec)
                }
                .fixedSize()
                Sparkline(values: stats.netDownHistory, maxValue: networkScale, tint: tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .glassCard(padding: NotchLayout.spacingM)
    }

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            CardLabel(symbol: "internaldrive", title: "Disk")
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(formatNumber(stats.diskFreeGB)) GB")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                Text("volno z \(formatNumber(stats.diskTotalGB)) GB")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            ThinProgress(value: diskUsedFraction, tint: tint)
        }
        .glassCard(padding: NotchLayout.spacingM)
    }

    private func rateRow(symbol: String, value: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 10)
            Text(formatRate(value))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
        }
    }

    // MARK: Pomocné výpočty

    private var diskUsedFraction: Double {
        guard stats.diskTotalGB > 0 else { return 0 }
        return min(max(1 - stats.diskFreeGB / stats.diskTotalGB, 0), 1)
    }

    /// Měřítko grafu sítě: největší vzorek v historii, minimálně 100 KB/s, aby šum nevypadal jako špička.
    private var networkScale: Double {
        let peak = stats.netDownHistory.max() ?? 0
        return max(peak, 100 * 1024)
    }

    private func formatNumber(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "cs_CZ"), value)
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        let kb = bytesPerSec / 1024
        if kb < 1000 {
            return String(format: "%.0f KB/s", locale: Locale(identifier: "cs_CZ"), kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB/s", locale: Locale(identifier: "cs_CZ"), mb)
    }
}
