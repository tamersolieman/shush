import AppKit
import SwiftUI

@main
struct ShushApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        // The main window. A `Window` rather than a `WindowGroup`: this app has one front
        // panel, and letting ⌘N spawn a second copy of a tape deck makes no sense.
        Window("Shush", id: "main") {
            MainWindow(controller: delegate.controller)
                // Hands the delegate a way to reopen this window/settings from the status
                // item — `openWindow`/`openSettings` only exist in SwiftUI's environment,
                // not in AppKit code.
                .onAppear {
                    delegate.openMainWindow = { openWindow(id: "main") }
                    delegate.openSettingsWindow = { openSettings() }
                }
        }
        .defaultSize(width: 860, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Reveal Dictionary File") {
                    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                }
            }
        }

        // Fully qualified: this app has its own `Settings` type, which otherwise shadows
        // SwiftUI's settings scene.
        SwiftUI.Settings {
            SettingsWindow(controller: delegate.controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    private var hud: HUDPanel?
    private var stateObservation: NSObjectProtocol?
    /// Owns the live toast so it isn't deallocated out from under itself — `CorrectionWatcher`
    /// only hands back a detected correction, it doesn't own any UI.
    private var correctionToast: CorrectionToastPanel?
    private var statusItem: NSStatusItem?
    /// Set by `ShushApp` once the main window's `onAppear` has fired — AppKit code has no
    /// direct access to SwiftUI's `openWindow`/`openSettings` environment actions.
    var openMainWindow: (() -> Void)?
    var openSettingsWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A regular app now: dock icon, app menu, standard windows. The HUD is still a
        // non-activating panel, so dictating into another app never steals its focus — that
        // property belongs to the panel, not to the activation policy.
        NSApp.setActivationPolicy(.regular)

        hud = HUDPanel(controller: controller)
        setUpStatusItem()

        if !controller.activate() {
            Permissions.promptForAccessibility()
            // The tap can only be created once the user grants Accessibility, and there's
            // no notification for that — poll until it takes.
            retryActivation()
        }

        // Write the dashboard up front so the menu item always opens something, even
        // before the first dictation.
        RunLog.regenerate()

        // No-ops until the user has signed in and turned sync on.
        SyncEngine.shared.start()

        CorrectionWatcher.shared.onCorrectionDetected = { [weak self] correction, element in
            guard let self else { return }
            self.correctionToast?.dismiss()
            let toast = CorrectionToastPanel(
                correction: correction,
                onSave: { DictionaryStore.shared.add(.correction(hear: correction.hear, write: correction.write)) },
                onDismiss: {}
            )
            self.correctionToast = toast
            toast.present(near: element)
        }

        // Parakeet's models take ~20s to load from disk, and that cost lands on whichever
        // dictation touches them first — so the first hold after every launch would stall
        // with the HUD showing nothing. Warm them in the background instead, but only when
        // they're actually going to be used and are already downloaded.
        let willUseParakeet = Settings.shared.engine == .parakeet
        if willUseParakeet, ParakeetModels.isDownloaded {
            Task.detached(priority: .utility) {
                _ = try? await ParakeetModels.shared.manager()
            }
        }
        if Settings.shared.engine == .cohere, CohereModels.isDownloaded {
            Task.detached(priority: .utility) {
                _ = try? await CohereModels.shared.loaded()
            }
        }

        observeState()
        Log.app.info("Shush ready — hold \(Settings.shared.pushToTalkKey.displayName) to dictate")
    }

    /// `shush://clear`, used by the legacy HTML dashboard.  Google sign-in's redirect doesn't
    /// come through here — it's a local loopback HTTP listener, not this URL scheme (see
    /// `LoopbackRedirectServer`).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "shush" {
            switch url.host {
            case "clear":
                RunLog.clear()
            default:
                break
            }
        }
    }

    /// This is a menu-bar-first app — closing the main window should leave the hotkey and
    /// status item running, not quit. Only `Quit Shush` (menu or ⌘Q) actually terminates.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock icon click with no visible windows — reopens the main window the same way the
    /// status item's "Open Shush" does.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            openMainWindow?()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.deactivate()
    }

    /// Shows and hides the HUD, and dims the status item icon, in step with the
    /// controller's state.
    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.controller.state.isActive {
                    self.hud?.present()
                } else {
                    self.hud?.dismiss()
                }
                self.statusItem?.button?.alphaValue = self.controller.state.isActive ? 1 : 0.55
                self.observeState()
            }
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = StatusBarIcon.image ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
            button.alphaValue = controller.state.isActive ? 1 : 0.55
        }
        item.menu = buildStatusMenu()
        statusItem = item
    }

    /// Just "Open Shush" / "Settings" / "Quit" for now — room to grow, but the app's real
    /// controls live in the main window, not buried in a menu-bar dropdown.
    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Shush", action: #selector(openShush), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Shush", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    @objc private func openShush() {
        NSApp.activate(ignoringOtherApps: true)
        openMainWindow?()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettingsWindow?()
    }

    private func retryActivation() {
        Task { @MainActor in
            while !Permissions.hasAccessibility {
                try? await Task.sleep(for: .seconds(1))
            }
            controller.activate()
            Log.app.info("Accessibility granted — hotkey armed")
        }
    }
}
