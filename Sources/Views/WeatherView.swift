import SwiftUI

/// Počasí (Open-Meteo): vlevo aktuální stav, vpravo 5denní předpověď.
struct WeatherView: View {
    @ObservedObject private var store = WeatherStore.shared
    @EnvironmentObject private var vm: NotchViewModel

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private let forecastWidth: CGFloat = 224

    var body: some View {
        VStack(spacing: 4) {
            mainContent
            Text("Data: Open-Meteo.com")
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .task { await store.refreshIfNeeded() }
        .onDisappear {
            vm.holdOpen = false
        }
    }

    // MARK: Stavy

    @ViewBuilder
    private var mainContent: some View {
        switch store.state {
        case .loaded:
            loadedContent
        case .error(let message):
            VStack(spacing: NotchLayout.spacingS) {
                EmptyState(symbol: "exclamationmark.triangle", title: "Počasí není dostupné", message: message)
                GlassPill(title: "Zkusit znovu", symbol: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
            }
            .glassCard(padding: NotchLayout.spacingM)
        case .idle, .loading:
            if store.current != nil {
                loadedContent
            } else {
                EmptyState(symbol: "cloud.sun", title: "Načítám počasí…", message: store.cityName)
                    .glassCard(padding: NotchLayout.spacingM)
            }
        }
    }

    private var loadedContent: some View {
        HStack(spacing: NotchLayout.spacingM) {
            currentCard
            forecastCard
                .frame(width: forecastWidth)
        }
    }

    // MARK: Aktuální počasí

    private var currentCard: some View {
        let cur = store.current
        let info = WeatherCodes.info(code: cur?.code ?? 3, isDay: cur?.isDay ?? true)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: info.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 36))
                    .frame(width: 46)
                Text(cur.map { Self.degrees($0.temperature) } ?? "–")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            Text(info.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
            if let cur {
                Text("Pocitově \(Self.degrees(cur.apparent)) · Vítr \(Int(cur.windKmh.rounded())) km/h")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            cityRow
        }
        .glassCard(padding: NotchLayout.spacingM)
        .animation(.smooth(duration: 0.25), value: editing)
    }

    private var cityRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
            if editing {
                TextField("Město", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white)
                    .focused($fieldFocused)
                    .onSubmit { commitCity() }
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            } else {
                Text(store.cityName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !editing {
                Button(action: startEditing) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Změnit město")
            }
        }
        .onChange(of: fieldFocused) { _, focused in
            vm.holdOpen = focused
            if !focused { editing = false }
        }
    }

    private func startEditing() {
        draft = store.city
        editing = true
        DispatchQueue.main.async {
            fieldFocused = true
        }
    }

    private func commitCity() {
        let value = draft
        editing = false
        fieldFocused = false
        vm.holdOpen = false
        store.setCity(value)
    }

    // MARK: Předpověď

    private var forecastCard: some View {
        HStack(spacing: 0) {
            ForEach(Array(store.daily.enumerated()), id: \.element.id) { index, day in
                dayColumn(day, isToday: index == 0)
            }
        }
        .frame(maxHeight: .infinity)
        .glassCard(padding: 6)
    }

    private func dayColumn(_ day: WeatherDay, isToday: Bool) -> some View {
        let info = WeatherCodes.info(code: day.code, isDay: true)
        return VStack(spacing: 5) {
            Text(isToday ? "Dnes" : day.weekdayShort)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isToday ? 0.9 : 0.55))
            Spacer(minLength: 0)
            Image(systemName: info.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 16))
            Spacer(minLength: 0)
            Text(Self.degrees(day.max))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
            Text(Self.degrees(day.min))
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Pomocné

    private static func degrees(_ value: Double) -> String {
        return "\(Int(value.rounded()))°"
    }
}
