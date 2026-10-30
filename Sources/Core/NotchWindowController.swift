import AppKit
import SwiftUI
import Combine

/// Vlastní okno notche + sledování myši (hover / tažení souborů).
@MainActor
final class NotchWindowController {
    private let services = AppServices.shared
    private let vm: NotchViewModel
    private let panel = NotchPanel()
    private var monitors: [Any] = []
    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var dragStartCount = 0
    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)

    /// Selže (nil), pokud právě není připojen žádný displej.
    init?() {
        guard let screen = Self.targetScreen(for: AppServices.shared.settings.display) else { return nil }
        vm = NotchViewModel(geometry: NotchGeometry(screen: screen))
        services.viewModel = vm

        let root = NotchRootView()
            .environmentObject(vm)
            .withServices()
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.frame = NSRect(origin: .zero, size: NotchLayout.panelSize)
        panel.contentView = hosting

        position()
        panel.orderFrontRegardless()
        installMonitors()
        observe()
    }

    deinit {
        for m in monitors { NSEvent.removeMonitor(m) }
    }

    // MARK: - Displej a pozice

    static func targetScreen(for choice: DisplayChoice) -> NSScreen? {
        let screens = NSScreen.screens
        switch choice {
        case .builtIn:
            return screens.first { $0.safeAreaInsets.top > 0 } ?? screens.first ?? NSScreen.main
        case .primary:
            return screens.first ?? NSScreen.main
        }
    }

    /// `choice` se předává explicitně, protože `@Published` emituje ještě před zápisem nové hodnoty.
    private func position(for choice: DisplayChoice? = nil) {
        guard let screen = Self.targetScreen(for: choice ?? services.settings.display) else { return }
        vm.geometry = NotchGeometry(screen: screen)
        let size = NotchLayout.panelSize
        let f = screen.frame
        panel.setFrame(
            NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    private func observe() {
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.position() }
            .store(in: &cancellables)

        services.settings.$display
            .dropFirst()
            .sink { [weak self] choice in self?.position(for: choice) }
            .store(in: &cancellables)

        services.battery.onPlugIn = { [weak self] in
            guard let self, self.services.settings.chargingAnimation else { return }
            self.vm.runChargeAnimation()
        }
    }

    // MARK: - Myš

    private var screenFrame: CGRect { vm.geometry.screen.frame }

    private func closedHotRect() -> CGRect {
        let n = vm.geometry.notchSize
        let w = n.width + 2 * NotchLayout.sideActivity + 24
        return CGRect(x: screenFrame.midX - w / 2,
                      y: screenFrame.maxY - n.height - 2,
                      width: w,
                      height: n.height + 8)
    }

    private func openRect() -> CGRect {
        let s = NotchLayout.openSize
        return CGRect(x: screenFrame.midX - s.width / 2,
                      y: screenFrame.maxY - s.height,
                      width: s.width,
                      height: s.height)
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            Task { @MainActor in self?.handleEvent(type) }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            Task { @MainActor in self?.handleEvent(type) }
            return event
        }) { monitors.append(l) }
    }

    private func handleEvent(_ type: NSEvent.EventType) {
        if type == .leftMouseDown {
            // Změní-li se během tažení drag pasteboard, začalo tažení souborů.
            dragStartCount = NSPasteboard(name: .drag).changeCount
            return
        }
        handleMouse(dragging: type == .leftMouseDragged)
    }

    private func draggedFiles() -> Bool {
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != dragStartCount else { return false }
        return pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private func handleMouse(dragging: Bool) {
        let p = NSEvent.mouseLocation
        if vm.isOpen {
            if openRect().insetBy(dx: -24, dy: -24).contains(p) {
                cancelClose()
            } else {
                scheduleClose()
            }
        } else if closedHotRect().contains(p) {
            if dragging {
                if services.settings.tabShelf, draggedFiles() {
                    vm.tab = .shelf
                    cancelOpen()
                    open()
                }
            } else {
                scheduleOpen()
            }
        } else {
            cancelOpen()
        }
    }

    // MARK: - Otevření / zavření

    private func scheduleOpen() {
        guard openTask == nil else { return }
        cancelClose()
        let delay = services.settings.hoverDelay
        openTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    private func cancelOpen() {
        openTask?.cancel()
        openTask = nil
    }

    private func open() {
        openTask = nil
        guard !vm.isOpen else { return }
        panel.ignoresMouseEvents = false
        withAnimation(spring) {
            vm.banner = nil
            vm.isOpen = true
        }
    }

    private func scheduleClose() {
        guard vm.isOpen, closeTask == nil else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, let self else { return }
            // Během držení tlačítka myši (tažení souboru ven) se nezavírá.
            if NSEvent.pressedMouseButtons & 1 != 0 {
                self.closeTask = nil
                return
            }
            self.close()
        }
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func close() {
        closeTask = nil
        withAnimation(spring) { vm.isOpen = false }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !self.vm.isOpen else { return }
            self.panel.ignoresMouseEvents = true
        }
    }
}
