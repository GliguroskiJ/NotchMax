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

/// Systémové statistiky: mřížka 4 × 2 (CPU, Paměť, Síť, Disk / Teplota, Ventilátory, GPU, Energie).
struct StatsView: View {
    @ObservedObject private var stats = SystemStats.shared
    @ObservedObject private var settings = AppSettings.shared

    private var tint: Color { settings.accent.color }
    private let gap: CGFloat = NotchLayout.spacingS

    var body: some View {
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                cpuCard
                memoryCard
                networkCard
                diskCard
            }
            HStack(spacing: gap) {
                temperatureCard
                fanCard
                gpuCard
                energyCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    // MARK: Karty – první řada

    private var cpuCard: some View {
        StatCard(symbol: "cpu", title: "Procesor") {
            StatValue(text: "\(Int((stats.cpu * 100).rounded())) %")
            Sparkline(values: stats.cpuHistory, maxValue: 1, tint: tint)
                .frame(maxWidth: .infinity, minHeight: 6, maxHeight: .infinity)
        }
    }

    private var memoryCard: some View {
        StatCard(symbol: "memorychip", title: "Paměť") {
            Spacer(minLength: 0)
            StatValue(text: "\(formatNumber(stats.memoryUsedGB)) GB")
            StatSubtitle(text: "z \(formatNumber(stats.memoryTotalGB)) GB")
            ThinProgress(value: stats.memoryUsedFraction, tint: tint, height: 4)
        }
    }

    private var networkCard: some View {
        StatCard(symbol: "arrow.up.arrow.down", title: "Síť") {
            VStack(alignment: .leading, spacing: 1) {
                rateRow(symbol: "arrow.down", value: stats.netDownBytesPerSec)
                rateRow(symbol: "arrow.up", value: stats.netUpBytesPerSec)
            }
            Sparkline(values: stats.netDownHistory, maxValue: networkScale, tint: tint)
                .frame(maxWidth: .infinity, minHeight: 6, maxHeight: .infinity)
        }
    }

    private var diskCard: some View {
        StatCard(symbol: "internaldrive", title: "Disk") {
            Spacer(minLength: 0)
            StatValue(text: "\(formatNumber(stats.diskFreeGB)) GB")
            StatSubtitle(text: "volno z \(formatNumber(stats.diskTotalGB)) GB")
            ThinProgress(value: diskUsedFraction, tint: tint, height: 4)
        }
    }

    // MARK: Karty – druhá řada

    private var temperatureCard: some View {
        StatCard(symbol: "thermometer.medium", title: "Teplota CPU") {
            Spacer(minLength: 0)
            if let temp = stats.cpuTemperature {
                StatValue(text: "\(Int(temp.rounded())) °C")
                StatSubtitle(text: temperatureLabel(temp))
                ThinProgress(value: (temp - 20) / 80, tint: temp >= 90 ? Color.orange : tint, height: 4)
            } else {
                StatValue(text: "—")
                StatSubtitle(text: stats.sensorsLoaded ? "Nedostupné" : " ")
            }
        }
    }

    private var fanCard: some View {
        StatCard(symbol: "fan", title: "Ventilátory") {
            Spacer(minLength: 0)
            if let count = stats.fanCount {
                if count == 0 {
                    StatValue(text: "Bez ventilátoru", size: 13)
                    StatSubtitle(text: "Pasivní chlazení")
                } else if let rpm = stats.fanRPM {
                    StatValue(text: "\(formatInteger(rpm)) RPM")
                    StatSubtitle(text: "\(count) \(czechPlural(count, "ventilátor", "ventilátory", "ventilátorů"))")
                } else {
                    StatValue(text: "—")
                    StatSubtitle(text: "\(count) \(czechPlural(count, "ventilátor", "ventilátory", "ventilátorů"))")
                }
            } else {
                StatValue(text: "—")
                StatSubtitle(text: stats.sensorsLoaded ? "Nedostupné" : " ")
            }
        }
    }

    private var gpuCard: some View {
        StatCard(symbol: "cube.transparent", title: "GPU") {
            if let gpu = stats.gpuUtilization {
                StatValue(text: "\(Int((gpu * 100).rounded())) %")
            } else {
                StatValue(text: "—")
            }
            Sparkline(values: stats.gpuHistory, maxValue: 1, tint: tint)
                .frame(maxWidth: .infinity, minHeight: 6, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var energyCard: some View {
        if let battery = stats.battery {
            StatCard(symbol: battery.isCharging ? "battery.100percent.bolt" : "bolt", title: "Energie") {
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    StatValue(text: "\(formatNumber(battery.powerWatts)) W")
                        .layoutPriority(1)
                    StatSubtitle(text: powerStateLabel(battery))
                }
                StatSubtitle(text: batteryHealthLabel(battery))
            }
        } else {
            StatCard(symbol: "clock", title: "Doba běhu") {
                Spacer(minLength: 0)
                StatValue(text: stats.sensorsLoaded ? formatUptime(stats.uptime) : "—")
                StatSubtitle(text: "od spuštění systému")
            }
        }
    }

    private func rateRow(symbol: String, value: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 9)
            Text(formatRate(value))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

    private func temperatureLabel(_ temp: Double) -> String {
        switch temp {
        case ..<60: return "V pohodě"
        case 60..<80: return "Zahřátý"
        case 80..<95: return "Horký"
        default: return "Velmi horký"
        }
    }

    private func powerStateLabel(_ battery: SensorsBatteryInfo) -> String {
        if battery.isCharging { return "nabíjí" }
        if battery.externalConnected { return "adaptér" }
        return "z baterie"
    }

    private func batteryHealthLabel(_ battery: SensorsBatteryInfo) -> String {
        var parts: [String] = []
        if let health = battery.healthPercent {
            parts.append("Zdraví \(health) %")
        }
        if let cycles = battery.cycleCount {
            parts.append("\(cycles) \(czechPlural(cycles, "cyklus", "cykly", "cyklů"))")
        }
        return parts.isEmpty ? "Baterie" : parts.joined(separator: " · ")
    }

    private func czechPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        if n == 1 { return one }
        if (2...4).contains(n) { return few }
        return many
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days) d \(hours) h" }
        if hours > 0 { return "\(hours) h \(minutes) min" }
        return "\(minutes) min"
    }

    private func formatNumber(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "cs_CZ"), value)
    }

    private func formatInteger(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
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

// MARK: - Kompaktní stavební prvky karet

/// Kompaktní karta statistiky: popisek nahoře, obsah vyplní zbytek; nikdy netlačí na layout.
private struct StatCard<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            StatLabel(symbol: symbol, title: title)
            content()
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(padding: NotchLayout.spacingS)
    }
}

/// Malý jednořádkový popisek karty (ikona + název).
private struct StatLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(Color.white.opacity(0.55))
    }
}

/// Hlavní hodnota karty.
private struct StatValue: View {
    let text: String
    var size: CGFloat = 16

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// Doplňkový řádek pod hodnotou.
private struct StatSubtitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.55))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
