import SwiftUI
import UserNotifications
import AppKit

@main
struct FamiliarApp: App {
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // Set accent color to warm peach/apricot
        NSApplication.shared.effectiveAppearance.performAsCurrentDrawingAppearance {}
    }

    /// Signature accent color — user-configurable, appearance-aware
    static var accent: Color {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "accentR") != nil else {
            return Color(red: 0.2, green: 0.62, blue: 0.58) // default teal
        }
        let r = defaults.double(forKey: "accentR")
        if r < 0 {
            // Rainbow mode — hue cycles based on current time
            let hue = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 12) / 12
            return Color(hue: hue, saturation: 0.7, brightness: 0.85)
        }
        let g = defaults.double(forKey: "accentG")
        let b = defaults.double(forKey: "accentB")
        // Perceived luminance — if the accent is very dark, lighten it in dark mode
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        if luminance < 0.25 {
            return Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                if isDark {
                    // Invert toward white: map (0.15,0.15,0.15) → (0.85,0.85,0.85)
                    return NSColor(red: 1.0 - r, green: 1.0 - g, blue: 1.0 - b, alpha: 1)
                }
                return NSColor(red: r, green: g, blue: b, alpha: 1)
            })
        }
        return Color(red: r, green: g, blue: b)
    }
    /// Warm earth tones — decorative only, not for interactive elements
    static let earthWarm = Color(red: 0.82, green: 0.56, blue: 0.32)
    static let earthMuted = Color(red: 0.64, green: 0.48, blue: 0.38)
    /// Slightly warm off-white app canvas/surfaces for light mode
    static let canvasBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        if match == .darkAqua {
            return .windowBackgroundColor
        }
        return NSColor(calibratedRed: 0.975, green: 0.965, blue: 0.948, alpha: 1.0)
    })
    static let surfaceBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        if match == .darkAqua {
            return .controlBackgroundColor
        }
        return NSColor(calibratedRed: 0.962, green: 0.949, blue: 0.928, alpha: 1.0)
    })

    /// Tool group blue — tool use/result disclosures
    static let toolBlue = Color(red: 0.35, green: 0.62, blue: 0.75)
    /// Agent team purple — agent team headers, badges, accents
    static let agentPurple = Color(red: 0.58, green: 0.38, blue: 0.78)
    /// Agent complete green — successful agent status
    static let agentGreen = Color(red: 0.35, green: 0.75, blue: 0.55)
    /// Agent error red — failed agent status
    static let agentRed = Color(red: 0.85, green: 0.30, blue: 0.35)
    /// Thinking color — extended thinking disclosures
    static let thinkingPink = Color(red: 0.85, green: 0.45, blue: 0.55)

    // MARK: - Corner Radius System
    /// Small elements: code blocks, inline badges, thumbnails
    static let radiusSmall: CGFloat = 6
    /// Medium elements: message bubbles, tool groups, cards
    static let radiusMedium: CGFloat = 8
    /// Large elements: modals, panels, widgets
    static let radiusLarge: CGFloat = 12

    // Legacy aliases (transitioning to unified palette)
    static let earthSand = earthWarm

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    NotificationCenter.default.post(name: .newSession, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .textEditing) {
                Button("Find…") {
                    NotificationCenter.default.post(name: .findInConversation, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandMenu("Session") {
                Button("Quick Prompt") {
                    NotificationCenter.default.post(name: .openSpotlight, object: nil)
                }
                .keyboardShortcut(" ", modifiers: [.command, .shift])

                Button("Command Palette") {
                    NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                Button("Clear Conversation") {
                    NotificationCenter.default.post(name: .clearConversation, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Cancel Request") {
                    NotificationCenter.default.post(name: .cancelRequest, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                Button("Export as Markdown…") {
                    NotificationCenter.default.post(name: .exportSession, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Duplicate Session") {
                    NotificationCenter.default.post(name: .duplicateSession, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Change Directory…") {
                    NotificationCenter.default.post(name: .changeDirectory, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button("Toggle Terminal") {
                    NotificationCenter.default.post(name: .toggleTerminal, object: nil)
                }
                .keyboardShortcut("`", modifiers: .command)

                Button("Toggle Inspector") {
                    NotificationCenter.default.post(name: .toggleInspector, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("Run Diagnostics") {
                    NotificationCenter.default.post(name: .openDoctor, object: nil)
                }

                Divider()

                ForEach(1...9, id: \.self) { i in
                    Button("Session \(i)") {
                        NotificationCenter.default.post(name: .selectSession, object: i - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(i))), modifiers: .command)
                }
            }

            CommandMenu("Memory") {
                Button("Backfill Last 5 Days") {
                    MemoryDaemon.shared.backfill(days: 5)
                }

                Button("Force Session Note") {
                    MemoryDaemon.shared.forceSessionNote()
                }

                Button("Force Episodic Render") {
                    MemoryDaemon.shared.forceRender()
                }

                Button("Force Graduation (semantic)") {
                    MemoryDaemon.shared.forceGraduation()
                }
            }

            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Button("Focus Input") {
                    NotificationCenter.default.post(name: .focusInput, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra("Familiar", image: "MenuBarIcon") {
            Button("New Session") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .newSession, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Quick Prompt") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openSpotlight, object: nil)
            }
            .keyboardShortcut(" ", modifiers: [.command, .shift])

            Button("Command Palette") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openCommandPalette, object: nil)
            }

            Divider()

            Button("Cancel Request") {
                NotificationCenter.default.post(name: .cancelRequest, object: nil)
            }

            Divider()

            Button("Show Familiar") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Button("Quit Familiar") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let newSession = Notification.Name("newSession")
    static let clearConversation = Notification.Name("clearConversation")
    static let cancelRequest = Notification.Name("cancelRequest")
    static let selectSession = Notification.Name("selectSession")
    static let findInConversation = Notification.Name("findInConversation")
    static let openSettings = Notification.Name("openSettings")
    static let openCommandPalette = Notification.Name("openCommandPalette")
    static let openDoctor = Notification.Name("openDoctor")
    static let completeTypewriter = Notification.Name("completeTypewriter")
    static let openSpotlight = Notification.Name("openSpotlight")
    static let openSplitSession = Notification.Name("openSplitSession")
    static let applyWorkflowPreset = Notification.Name("applyWorkflowPreset")
    static let exportSession = Notification.Name("exportSession")
    static let duplicateSession = Notification.Name("duplicateSession")
    static let changeDirectory = Notification.Name("changeDirectory")
    static let toggleTerminal = Notification.Name("toggleTerminal")
    static let toggleInspector = Notification.Name("toggleInspector")
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let focusInput = Notification.Name("focusInput")
    static let focusInputField = Notification.Name("focusInputField")
}
