//
//  SnapFlowApp.swift
//  SnapFlow
//
//  Created by Francesca Frederick on 3/7/26.
//

import SwiftUI
import Cocoa
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var rulerPanel: NSPanel?
    var voiceOrbPanel: NSPanel?
    var cancellables = Set<AnyCancellable>()
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run in background (removes Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Setup global hotkey
        HotKeyManager.shared.setupHotkey()

        // Setup menu bar status icon
        setupStatusItem()

        // Setup Ruler HUD panel — 250 wide (expanded), positioned flush to left edge
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let contentRect = NSRect(x: 0, y: 0, width: 250, height: screenHeight)
        let panel = FloatingPanel(contentRect: contentRect, content: RulerHUDView())

        // Flush to the very left edge of the screen (x = screen.minX, no gap)
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.minX, y: screen.frame.minY))
        }

        panel.orderFront(nil)
        self.rulerPanel = panel

        // Setup Voice Orb Panel
        let orbRect = NSRect(x: 0, y: 0, width: 300, height: 300)
        let orbPanel = FloatingPanel(contentRect: orbRect, content: VoiceOrbView())
        orbPanel.center()
        self.voiceOrbPanel = orbPanel

        HotKeyManager.shared.$isVoiceOrbVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                if isVisible {
                    self?.voiceOrbPanel?.makeKeyAndOrderFront(nil)
                } else {
                    self?.voiceOrbPanel?.orderOut(nil)
                }
            }
            .store(in: &cancellables)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: "SnapFocus")
            button.toolTip = "SnapFocus"
        }

        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Toggle Scheduler header (non-functional label)
        let header = NSMenuItem(title: "SnapFocus", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Toggle Voice Orb / Scheduler
        let orbItem = NSMenuItem(
            title: "Toggle AI Scheduler",
            action: #selector(toggleOrb),
            keyEquivalent: "S"
        )
        orbItem.keyEquivalentModifierMask = [.command, .shift]
        orbItem.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        orbItem.target = self
        menu.addItem(orbItem)

        // Toggle Ruler HUD visibility
        let rulerItem = NSMenuItem(
            title: "Show/Hide Ruler HUD",
            action: #selector(toggleRuler),
            keyEquivalent: "H"
        )
        rulerItem.keyEquivalentModifierMask = [.command, .shift]
        rulerItem.target = self
        menu.addItem(rulerItem)

        menu.addItem(.separator())

        // Settings
        let prefsItem = NSMenuItem(
            title: "Settings ...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        // Quit
        menu.addItem(NSMenuItem(title: "Quit SnapFocus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc private func toggleOrb() {
        HotKeyManager.shared.toggleVoiceOrb()
    }

    @objc private func toggleRuler() {
        guard let panel = rulerPanel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    @objc private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

@main
struct SnapFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No main window — app runs entirely from the status bar menu
        Settings { SettingsView() }
    }
}
