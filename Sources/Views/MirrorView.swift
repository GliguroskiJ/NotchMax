import SwiftUI
import AppKit
import AVFoundation

// MARK: - Zrcátko
//
// Živý náhled z kamery (zrcadlově otočený) pro rychlou kontrolu před hovorem.
// Kamera běží jen, dokud je pohled zobrazený.

struct MirrorView: View {
    @ObservedObject private var camera = CameraMirror.shared
    @AppStorage("mirror.flipped") private var mirrored = true
    @AppStorage("mirror.light") private var light = false

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NotchLayout.cardRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { camera.start() }
            .onDisappear { camera.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch camera.state {
        case .idle, .requesting:
            requestingState
        case .denied:
            deniedState
        case .noCamera:
            EmptyState(symbol: "video.slash",
                       title: L("Žádná kamera"),
                       message: L("Připoj kameru nebo iPhone (Kamera Continuity)."))
                .glassCard()
        case .failed(let message):
            VStack(spacing: NotchLayout.spacingS) {
                EmptyState(symbol: "exclamationmark.triangle",
                           title: L("Kameru se nepodařilo spustit"),
                           message: message)
                GlassPill(title: L("Zkusit znovu"), symbol: "arrow.clockwise") {
                    camera.retry()
                }
            }
            .glassCard()
        case .starting, .running:
            preview
        }
    }

    // MARK: Stavy

    private var requestingState: some View {
        VStack(spacing: NotchLayout.spacingS) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.white)
            Text(L("Žádám o přístup ke kameře…"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }

    private var deniedState: some View {
        VStack(spacing: NotchLayout.spacingS) {
            EmptyState(symbol: "video.slash",
                       title: L("Přístup ke kameře je zakázán"),
                       message: L("Povol NotchMaxu kameru v Nastavení systému → Soukromí a zabezpečení → Kamera."))
            GlassPill(title: L("Otevřít nastavení"), symbol: "gearshape") {
                SystemSettingsLink.open(.camera)
            }
        }
        .glassCard()
    }

    // MARK: Náhled

    private var preview: some View {
        let ringInset: CGFloat = light ? 5 : 0
        let ringShape = RoundedRectangle(cornerRadius: NotchLayout.cardRadius + ringInset, style: .continuous)

        return ZStack {
            Color.black

            CameraPreview(session: camera.session,
                          mirrored: mirrored,
                          token: camera.configurationToken,
                          cornerRadius: NotchLayout.cardRadius)

            if camera.state == .starting {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.white)
            }

            if light {
                // Jemné rozjasnění a vnitřní záře – jako by obličej osvětlovalo kruhové světlo.
                Color.white.opacity(0.06)
                    .allowsHitTesting(false)
                cardShape
                    .strokeBorder(Color.white.opacity(0.8), lineWidth: 3)
                    .blur(radius: 6)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(cardShape)
        .overlay(glassRim.allowsHitTesting(false))
        .overlay(alignment: .bottom) { controls }
        .padding(ringInset)
        .background {
            if light {
                Color.clear
                    .notchGlass(in: ringShape, tint: Color.white.opacity(0.55))
                    .shadow(color: Color.white.opacity(0.55), radius: 12)
                    .allowsHitTesting(false)
            }
        }
        .animation(.smooth(duration: 0.25), value: light)
    }

    /// Měkký skleněný okraj náhledu.
    private var glassRim: some View {
        ZStack {
            cardShape
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 3)
                .blur(radius: 2)
                .clipShape(cardShape)
            cardShape
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.55), location: 0),
                            .init(color: Color.white.opacity(0.15), location: 0.4),
                            .init(color: Color.white.opacity(0.06), location: 0.7),
                            .init(color: Color.white.opacity(0.18), location: 1)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        }
    }

    private var controls: some View {
        HStack(spacing: NotchLayout.spacingS) {
            if camera.devices.count > 1 {
                GlassPill(title: shortName(camera.currentDevice?.localizedName ?? L("Kamera")),
                          symbol: "arrow.triangle.2.circlepath.camera") {
                    camera.selectNextDevice()
                }
                .help(L("Přepnout kameru"))
            }
            Spacer(minLength: 0)
            GlassIconButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                            prominent: mirrored,
                            size: NotchLayout.controlHeight) {
                mirrored.toggle()
            }
            .help(mirrored ? L("Vypnout zrcadlení") : L("Zapnout zrcadlení"))
            GlassPill(title: L("Světlo"),
                      symbol: light ? "lightbulb.fill" : "lightbulb",
                      tint: light ? Color.white.opacity(0.3) : nil) {
                light.toggle()
            }
            .help(L("Kruhové světlo kolem náhledu"))
        }
        .padding(NotchLayout.spacingS)
    }

    private func shortName(_ name: String) -> String {
        let limit = 18
        guard name.count > limit else { return name }
        return String(name.prefix(limit - 1)) + "…"
    }
}

// MARK: - Náhled kamery (AVCaptureVideoPreviewLayer)

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    /// Mění se po rekonfiguraci session – vynutí znovu nastavení zrcadlení na novém spojení.
    let token: Int
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView(session: session)
        view.cornerRadius = cornerRadius
        view.applyMirroring(mirrored)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.applyMirroring(mirrored)
    }
}

final class CameraPreviewNSView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    var cornerRadius: CGFloat = 0 {
        didSet {
            layer?.cornerRadius = cornerRadius
        }
    }

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)

        // Layer-hosting view: vlastní kořenová vrstva, náhled jako podvrstva.
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        root.masksToBounds = true
        root.cornerCurve = .continuous
        layer = root
        wantsLayer = true

        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.backgroundColor = NSColor.black.cgColor
        root.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) není podporováno")
    }

    override func layout() {
        super.layout()
        layoutPreview()
    }

    /// Layer-hosting view nemusí po změně rámu dostat `layout()`, proto i zde.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutPreview()
    }

    private func layoutPreview() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Při případné transformaci (záložní zrcadlení) se nesmí nastavovat `frame`.
        previewLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func applyMirroring(_ mirrored: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
            previewLayer.setAffineTransform(.identity)
        } else {
            // Záloha, když spojení zrcadlení nepodporuje (nebo ještě neexistuje).
            previewLayer.setAffineTransform(mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        }
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
