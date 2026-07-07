import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipboardStore?
    private var viewModel: HistoryViewModel?
    private var monitor: ClipboardMonitor?
    private var hotkeyManager: HotkeyManager?
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private weak var previousApplication: NSRunningApplication?
    private var workspaceObserver: NSObjectProtocol?
    private var panelOpenedAt: Date?
    private var hasPendingClipboardCapture = false

    private let settings = SettingsStore.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let store = try ClipboardStore()
            let viewModel = HistoryViewModel(store: store)
            let monitor = ClipboardMonitor(store: store) { [weak self] copied in
                Task { @MainActor in
                    guard let self else { return }
                    if copied, self.panel?.isVisible == true {
                        viewModel.reloadAfterClipboardCapture()
                    } else if copied {
                        self.hasPendingClipboardCapture = true
                    } else if self.panel?.isVisible == true {
                        viewModel.reload()
                    }
                }
            }

            self.store = store
            self.viewModel = viewModel
            self.monitor = monitor

            configureStatusItem()
            configureHotkey()
            configureSettingsCallbacks()
            configureWorkspaceObserver()
            monitor.start(retentionPolicy: settings.retentionPolicy)
        } catch {
            let alert = NSAlert()
            alert.messageText = "MacPaste 无法启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        monitor?.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = menuBarIcon()

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示粘贴板历史", action: #selector(showClipboardHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(closeCurrentWindow), keyEquivalent: "w"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 MacPaste", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem?.menu = menu
    }

    private func menuBarIcon() -> NSImage? {
        let bundledIcon = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg")
            .flatMap { NSImage(contentsOf: $0) }
        let image = bundledIcon ?? NSImage(systemSymbolName: "clipboard", accessibilityDescription: "MacPaste")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        return image
    }

    private func configureHotkey() {
        hotkeyManager = HotkeyManager { [weak self] in
            Task { @MainActor in
                self?.toggleClipboardHistory()
            }
        }
        hotkeyManager?.register(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }

    private func configureSettingsCallbacks() {
        settings.onHotkeyChanged = { [weak self] in
            guard let self else { return }
            self.hotkeyManager?.register(keyCode: self.settings.hotkeyKeyCode, modifiers: self.settings.hotkeyModifiers)
        }
        settings.onRetentionChanged = { [weak self] policy in
            self?.monitor?.cleanup(retentionPolicy: policy)
            self?.monitor?.start(retentionPolicy: policy)
        }
    }

    @objc private func showClipboardHistory() {
        openClipboardHistory()
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func closeCurrentWindow() {
        if panel?.isVisible == true {
            closeClipboardHistory()
            return
        }
        if settingsWindow?.isVisible == true {
            settingsWindow?.performClose(nil)
        }
    }

    private func configureWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier else {
                    return
                }
                self.previousApplication = app
            }
        }
    }

    private func toggleClipboardHistory() {
        if panel?.isVisible == true {
            closeClipboardHistory()
        } else {
            openClipboardHistory()
        }
    }

    private static let panelWindowLevel = NSWindow.Level.popUpMenu

    private func openClipboardHistory() {
        capturePreviousApplication()
        guard let viewModel else { return }
        if hasPendingClipboardCapture {
            hasPendingClipboardCapture = false
            viewModel.prepareForOpen()
        }

        if panel == nil {
            let content = ClipboardPanelView(
                viewModel: viewModel,
                settings: settings,
                onPaste: { [weak self] item in self?.paste(item) }
            )
            let hostingView = NSHostingView(rootView: content)
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 14
            hostingView.layer?.masksToBounds = true

            let panel = FloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.isFloatingPanel = true
            panel.level = Self.panelWindowLevel
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }

        panel?.hidesOnDeactivate = false
        panel?.level = Self.panelWindowLevel
        centerPanel()
        panelOpenedAt = Date()

        installPanelKeyMonitor()
        installPanelMouseMonitor()
        panel?.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak viewModel] in
            viewModel?.requestSearchFocus()
        }
    }

    private func centerPanel() {
        guard let screenFrame = NSScreen.main?.visibleFrame, let panel else {
            return
        }
        panel.setFrameOrigin(NSPoint(
            x: screenFrame.midX - panel.frame.width / 2,
            y: screenFrame.midY - panel.frame.height / 2
        ))
    }

    private func closeClipboardHistory() {
        panel?.resignKey()
        panel?.orderOut(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func openSettings() {
        if settingsWindow == nil {
            let content = SettingsView(settings: settings)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MacPaste 设置"
            window.contentView = NSHostingView(rootView: content)
            window.isReleasedWhenClosed = false
            window.standardWindowButton(.closeButton)?.keyEquivalent = "w"
            window.standardWindowButton(.closeButton)?.keyEquivalentModifierMask = [.command]
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func capturePreviousApplication() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let frontmost, frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApplication = frontmost
        }
    }

    private func resolveTargetApplication() -> NSRunningApplication? {
        if let previousApplication, !previousApplication.isTerminated {
            return previousApplication
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let frontmost, frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            return frontmost
        }
        return nil
    }

    private var isPasting = false

    private func paste(_ item: ClipboardItem) {
        guard !isPasting else { return }
        isPasting = true

        let targetApplication = resolveTargetApplication()
        closeClipboardHistory()

        targetApplication?.activate(options: [.activateIgnoringOtherApps])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [settings] in
            let didCopy = PasteController.copyAndPaste(
                item,
                directPaste: settings.accessibilityTrusted
            )
            if didCopy {
                self.viewModel?.bumpItemToTop(id: item.id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isPasting = false
            }
        }
    }

    private func installPanelKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isVisible == true else {
                return event
            }
            return self.handlePanelKeyDown(event) ? nil : event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self, self.panel?.isVisible == true else { return }
                guard self.panel?.isKeyWindow != true else { return }
                _ = self.handlePanelKeyDown(event)
            }
        }
    }

    @discardableResult
    private func handlePanelKeyDown(_ event: NSEvent) -> Bool {
        if isCloseShortcut(event) {
            closeClipboardHistory()
            return true
        }

        if isCopyShortcut(event), copyPreviewSelection() {
            return true
        }

        if isPreviewTextActive(), shouldPassThroughPreviewEditing(event) {
            return false
        }

        switch event.keyCode {
        case 36:
            if let item = viewModel?.selectedItem {
                paste(item)
            }
            return true
        case 125:
            clearPreviewSelection()
            viewModel?.selectNext()
            return true
        case 126:
            clearPreviewSelection()
            viewModel?.selectPrevious()
            return true
        default:
            break
        }

        if viewModel?.isSearchFocused == true {
            return false
        }

        return false
    }

    private func isCloseShortcut(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            return true
        case 13:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return flags.contains(.command) || flags.contains(.control)
        default:
            return false
        }
    }

    private func isPreviewTextActive() -> Bool {
        panel?.firstResponder is PreviewTextView
    }

    private func shouldPassThroughPreviewEditing(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command), event.keyCode == 0 {
            return true
        }

        if flags.contains(.shift) {
            switch event.keyCode {
            case 123, 124, 125, 126:
                return true
            default:
                break
            }
        }

        return false
    }

    private func isCopyShortcut(_ event: NSEvent) -> Bool {
        event.keyCode == 8 &&
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
    }

    @discardableResult
    private func copyPreviewSelection() -> Bool {
        guard let textView = findPreviewTextView(in: panel?.contentView),
              textView.selectedRange().length > 0 else {
            return false
        }
        textView.copy(nil)
        return true
    }

    private func clearPreviewSelection() {
        guard let textView = findPreviewTextView(in: panel?.contentView) else { return }
        textView.selectedRange = NSRange(location: textView.selectedRange.location, length: 0)
    }

    private func findPreviewTextView(in view: NSView?) -> PreviewTextView? {
        guard let view else { return nil }
        if let preview = view as? PreviewTextView {
            return preview
        }
        for subview in view.subviews {
            if let found = findPreviewTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func installPanelMouseMonitor() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            guard let self else { return event }
            self.closeClipboardHistoryIfClickOutside(self.screenLocation(for: event))
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            Task { @MainActor in
                self?.closeClipboardHistoryIfClickOutside(NSEvent.mouseLocation)
            }
        }
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window = event.window else {
            return NSEvent.mouseLocation
        }
        return window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
    }

    private func closeClipboardHistoryIfClickOutside(_ screenLocation: NSPoint) {
        guard let panel, panel.isVisible else { return }
        if let panelOpenedAt, Date().timeIntervalSince(panelOpenedAt) < 0.25 {
            return
        }
        guard !panel.frame.contains(screenLocation) else { return }
        closeClipboardHistory()
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
