import Cocoa
import SwiftUI
import Carbon

/// A dropdown "quick terminal" panel that slides from the top of the screen,
/// toggled by a global hotkey (Ctrl+Space by default).
@MainActor
final class QuickTerminalController: NSObject, NSWindowDelegate {
    static let shared = QuickTerminalController()

    private(set) var visible = false
    private var panel: NSPanel?
    private var tabManager: TabManager?
    private var previousApp: NSRunningApplication?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var retryTimer: Timer?

    private let animationDuration: TimeInterval = 0.2

    private override init() {
        super.init()
    }

    // MARK: - Global Hotkey (CGEvent tap)

    func installGlobalHotkey() {
        if localMonitor == nil {
            // Always install local monitor so Ctrl+Space works when KSHR is focused
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let requiredFlags: NSEvent.ModifierFlags = [.control]
                let maskedFlags = event.modifierFlags.intersection([.control, .option, .command, .shift])
                if event.keyCode == 49 && maskedFlags == requiredFlags {
                    DispatchQueue.main.async {
                        QuickTerminalController.shared.toggle()
                    }
                    return nil
                }
                return event
            }
        }

        guard eventTap == nil else { return }

        retryTimer?.invalidate()
        retryTimer = nil

        // Try CGEvent tap for global (cross-app) hotkey
        if tryInstallEventTap() {
            return
        }

        // Retry periodically in case Accessibility permission is granted later
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard QuickTerminalController.shared.eventTap == nil else { return }
                if QuickTerminalController.shared.tryInstallEventTap() {
                    QuickTerminalController.shared.retryTimer?.invalidate()
                    QuickTerminalController.shared.retryTimer = nil
                }
            }
        }
    }

    fileprivate func tryInstallEventTap() -> Bool {
        let eventMask = [
            CGEventType.keyDown
        ].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: quickTerminalEventTapCallback,
            userInfo: nil
        ) else {
            return false
        }

        self.eventTap = eventTap
        retryTimer?.invalidate()
        retryTimer = nil

        let source = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    func removeGlobalHotkey() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        if let mon = localMonitor {
            NSEvent.removeMonitor(mon)
            localMonitor = nil
        }
    }

    fileprivate nonisolated func isQuickTerminalHotkey(_ event: NSEvent) -> Bool {
        let requiredFlags: NSEvent.ModifierFlags = [.control]
        let maskedFlags = event.modifierFlags.intersection([.control, .option, .command, .shift])
        return event.keyCode == 49 && maskedFlags == requiredFlags
    }

    // MARK: - Toggle

    func toggle() {
        if visible {
            animateOut()
        } else {
            animateIn()
        }
    }

    // MARK: - Panel Setup

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let panelWidth = screenFrame.width
        let panelHeight = screenFrame.height * 0.4

        let panel = NSPanel(
            contentRect: NSRect(x: screenFrame.minX, y: screenFrame.maxY, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "KSHR Quick Terminal"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.animationBehavior = .none
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let tm = TabManager()
        self.tabManager = tm

        let notificationStore = TerminalNotificationStore.shared
        let sidebarState = SidebarState(isVisible: false)
        let sidebarSelectionState = SidebarSelectionState()
        let kshrConfigStore = KshrConfigStore()
        kshrConfigStore.wireDirectoryTracking(tabManager: tm)
        kshrConfigStore.loadAll()

        let windowId = UUID()
        let root = ContentView(updateViewModel: AppDelegate.shared?.updateViewModel ?? UpdateViewModel(), windowId: windowId)
            .environmentObject(tm)
            .environmentObject(notificationStore)
            .environmentObject(sidebarState)
            .environmentObject(sidebarSelectionState)
            .environmentObject(kshrConfigStore)

        panel.contentView = NSHostingView(rootView: root)

        self.panel = panel
        return panel
    }

    // MARK: - Animation

    private func animateIn() {
        guard !visible else { return }
        visible = true

        let frontApp = NSWorkspace.shared.frontmostApplication
        if frontApp?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontApp
        }

        let panel = ensurePanel()
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let panelWidth = screenFrame.width
        let panelHeight = screenFrame.height * 0.4

        let startFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY,
            width: panelWidth,
            height: panelHeight
        )
        let endFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - panelHeight,
            width: panelWidth,
            height: panelHeight
        )

        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(endFrame, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: {
            panel.makeKey()
        })
    }

    private func animateOut() {
        guard visible, let panel else { return }
        visible = false

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let currentFrame = panel.frame

        let endFrame = NSRect(
            x: currentFrame.minX,
            y: screenFrame.maxY,
            width: currentFrame.width,
            height: currentFrame.height
        )

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(endFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            if let prev = self?.previousApp, prev.isTerminated == false {
                prev.activate()
            }
            self?.previousApp = nil
        })
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let w = notification.object as? NSPanel, w === self.panel else { return }
            if self.visible {
                self.animateOut()
            }
        }
    }

    // MARK: - Re-enable tap on timeout

    func reenableTapIfNeeded() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

// C function callback for CGEvent tap — no captures, uses static access
private func quickTerminalEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    cgEvent: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let result = Unmanaged.passUnretained(cgEvent)

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            QuickTerminalController.shared.reenableTapIfNeeded()
        }
        return result
    }

    guard type == .keyDown else { return result }
    guard !NSApp.isActive else { return result }
    guard let event: NSEvent = .init(cgEvent: cgEvent) else { return result }
    guard QuickTerminalController.shared.isQuickTerminalHotkey(event) else { return result }

    DispatchQueue.main.async {
        QuickTerminalController.shared.toggle()
    }
    return nil
}
