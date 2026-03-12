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
        HotKeyManager.shared.onToggleRuler = { [weak self] in
            self?.toggleRuler()
        }
        HotKeyManager.shared.onOpenSettings = { [weak self] in
            // This is handled by SwiftUI observer now, but we keep the logic here for the menu item
            // or we delegate it to the MenuBarExtra buttons.
        }
        HotKeyManager.shared.setupHotkey()

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

    @objc func toggleOrb() {
        HotKeyManager.shared.toggleVoiceOrb()
    }

    @objc func toggleRuler() {
        guard let panel = rulerPanel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    @objc func openPreferences() {
        // Handled by SwiftUI
    }
}

@main
struct SnapFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openSettings) private var openSettings
    @StateObject private var hotKeyManager = HotKeyManager.shared
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
        
        MenuBarExtra("SnapFocus", systemImage: "bolt.horizontal.fill") {
            VStack {
                Text("SnapFocus")
                Divider()
                
                Button(action: {
                    appDelegate.toggleOrb()
                }) {
                    Label("Toggle AI Scheduler", systemImage: "bolt.fill")
                }
                .keyboardShortcut("S", modifiers: [.command, .shift])
                
                Button(action: {
                    appDelegate.toggleRuler()
                }) {
                    Text("Show/Hide Ruler HUD")
                }
                .keyboardShortcut("H", modifiers: [.command, .shift])
                
                Divider()
                
                SettingsLink {
                    Label("Settings ...", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                
                Divider()
                
                Button("Quit SnapFocus") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("Q", modifiers: .command)
            }
            .onReceive(hotKeyManager.$settingsTriggerPulse) { _ in
                // We need to actually call openSettings from here
                // However, openSettings is often not enough to bring it to front
                // The native Cmd+, usually just works if Settings scene is present.
                // But for global hotkeys, we pulse this.
                // Since this closure runs when the pulse toggles, we try opening.
                NSApp.activate(ignoringOtherApps: true)
                try? openSettings()
            }
        }
    }
}
