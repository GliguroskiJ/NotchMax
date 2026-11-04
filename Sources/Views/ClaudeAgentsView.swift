import SwiftUI

/// Záložka „Agenti“: přehled relací Claude Code běžících na tomto Macu.
struct ClaudeAgentsView: View {
    @ObservedObject private var monitor = ClaudeMonitor.shared

    private let cardWidth: CGFloat = 172

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLayout.spacingS) {
            header
            if monitor.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.smooth(duration: 0.3), value: monitor.sessions)
    }

    // MARK: - Hlavička

    private var header: some View {
        HStack(spacing: NotchLayout.spacingS) {
            CardLabel(symbol: "sparkles", title: "Claude Code")
            Spacer(minLength: 0)
            if monitor.workingCount > 0 {
                CountChip(count: monitor.workingCount, label: "pracuje", color: .green)
            }
            if monitor.waitingCount > 0 {
                CountChip(count: monitor.waitingCount, label: "čeká", color: .orange)
            }
            let idleCount = monitor.sessions.count - monitor.activeCount
            if idleCount > 0 {
                CountChip(count: idleCount, label: "nečinné", color: Color.white.opacity(0.45))
            }
            Button {
                monitor.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Obnovit")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Seznam relací

    @ViewBuilder
    private var sessionList: some View {
        if monitor.sessions.count <= 3 {
            HStack(spacing: NotchLayout.spacingS) {
                ForEach(monitor.sessions) { session in
                    card(session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NotchLayout.spacingS) {
                    ForEach(monitor.sessions) { session in
                        card(session)
                            .frame(width: cardWidth)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func card(_ session: ClaudeSession) -> some View {
        Button {
            monitor.open(session)
        } label: {
            ClaudeSessionCard(session: session)
        }
        .buttonStyle(.plain)
        .help(session.cwd.isEmpty ? "Otevřít v Terminálu" : "Otevřít \(session.cwd) v Terminálu")
        .contextMenu {
            Button("Otevřít v Terminálu") { monitor.open(session) }
            Button("Zobrazit ve Finderu") { monitor.revealInFinder(session) }
                .disabled(session.cwd.isEmpty)
            Button("Kopírovat příkaz pro obnovení") { monitor.copyResumeCommand(session) }
        }
    }

    // MARK: - Prázdný stav

    private var emptyState: some View {
        EmptyState(
            symbol: "sparkles",
            title: "Spusť Claude Code v terminálu",
            message: monitor.hooksInstalled
                ? "Relace Claude Code z posledních 24 hodin se zobrazí tady."
                : "Relace z posledních 24 hodin se zobrazí tady. Pro přesnější stav nainstaluj hooky v Nastavení → Agenti."
        )
        .glassCard(padding: NotchLayout.spacingM)
    }
}

// MARK: - Karta relace

private struct ClaudeSessionCard: View {
    let session: ClaudeSession
    @State private var hovering = false

    private var stateColor: Color {
        switch session.state {
        case .working: return .green
        case .waiting: return .orange
        case .idle: return Color.white.opacity(0.4)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ClaudeStatusDot(state: session.state)
                Text(session.projectName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(ClaudeRelativeTime.string(from: session.lastActivity, now: context.date))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            if let branch = session.branch {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(branch)
                        .font(.system(size: 9.5, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(Color.white.opacity(0.5))
            }

            if let prompt = session.lastPrompt {
                Text("› " + prompt)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let title = session.title {
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            statusLine
        }
        .glassCard(padding: NotchLayout.spacingM)
        .overlay(
            RoundedRectangle(cornerRadius: NotchLayout.cardRadius, style: .continuous)
                .strokeBorder(session.state == .waiting ? Color.orange.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: NotchLayout.cardRadius, style: .continuous))
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.smooth(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var statusLine: some View {
        let detail: String? = {
            switch session.state {
            case .waiting: return session.attentionMessage
            case .idle: return session.lastReply
            case .working: return nil
            }
        }()
        HStack(spacing: 4) {
            Text(session.state.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(stateColor)
                .lineLimit(1)
                .fixedSize()
            if let detail {
                Text("· " + detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

// MARK: - Stavová tečka

private struct ClaudeStatusDot: View {
    let state: ClaudeSessionState
    @State private var pulse = false

    private var color: Color {
        switch state {
        case .working: return .green
        case .waiting: return .orange
        case .idle: return Color.white.opacity(0.35)
        }
    }

    var body: some View {
        ZStack {
            if state == .working {
                Circle()
                    .fill(color.opacity(0.45))
                    .frame(width: 7, height: 7)
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 1)
            }
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: state == .idle ? .clear : color.opacity(0.8), radius: 3)
        }
        .frame(width: 10, height: 10)
        .onAppear { startPulse() }
        .onChange(of: state) { _, _ in startPulse() }
    }

    private func startPulse() {
        pulse = false
        guard state == .working else { return }
        withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

// MARK: - Počítadlo v hlavičce

private struct CountChip: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

// MARK: - Relativní čas

enum ClaudeRelativeTime {
    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "právě teď" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "před \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "před \(hours) h" }
        return "před \(hours / 24) d"
    }
}
