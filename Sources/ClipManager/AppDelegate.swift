import Cocoa
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var clipboardPanel: ClipboardPanel?
    private var settingsWindow: NSWindow?

    let store = ClipboardStore.shared
    private let monitor = ClipboardMonitor.shared
    private let hotkeyManager = HotkeyManager.shared

    var previousApp: NSRunningApplication?
    var isPasting = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.load()
        setupMenuBar()
        setupClipboardPanel()
        startMonitoring()
        registerHotkey()
        store.load()
        UpdateChecker.checkForUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        store.save()
    }

    func applicationWillResignActive(_ notification: Notification) {
        guard !isPasting else { return }
        closePanel()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipManager")
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Zobrazit historii", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Nastavení…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Ukončit ClipManager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Panel

    private func setupClipboardPanel() {
        let panelView = ClipboardPanelView()
            .environmentObject(store)
        clipboardPanel = ClipboardPanel(contentView: panelView)
    }

    @objc func togglePanel() {
        guard let panel = clipboardPanel else { return }
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    func openPanel() {
        guard let panel = clipboardPanel else { return }
        previousApp = NSWorkspace.shared.frontmostApplication

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            let w: CGFloat = 420, h: CGFloat = 560
            let x = frame.midX - w / 2
            let y = frame.midY - h / 2 + frame.height * 0.1
            panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func closePanel() {
        clipboardPanel?.orderOut(nil)
        previousApp = nil
    }

    // MARK: - Paste

    func pasteItem(_ item: ClipboardItem) {
        guard let panel = clipboardPanel, panel.isVisible else { return }

        PasteService.writeToPasteboard(item)
        monitor.markOwnWrite()

        isPasting = true
        panel.orderOut(nil)

        let appToActivate = previousApp
        previousApp = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            appToActivate?.activate(options: .activateAllWindows)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                PasteService.simulateCmdV()
                self?.isPasting = false
            }
        }
    }

    // MARK: - Settings

    @objc func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView().environmentObject(store)
        let hosting = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Nastavení ClipManager"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 460, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Private helpers

    private func startMonitoring() {
        monitor.onNewItem = { [weak self] item in
            DispatchQueue.main.async {
                self?.store.addItem(item)
            }
        }
        monitor.start()
    }

    private func registerHotkey() {
        let settings = AppSettings.shared
        hotkeyManager.register(
            keyCode: UInt32(settings.hotkeyKeyCode),
            modifiers: UInt32(settings.hotkeyModifiers)
        ) {
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.togglePanel()
            }
        }
    }

    func reregisterHotkey() {
        hotkeyManager.unregister()
        registerHotkey()
    }
}
