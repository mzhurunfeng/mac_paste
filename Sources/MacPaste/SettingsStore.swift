import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: Keys.retentionDays)
            onRetentionChanged?(retentionPolicy)
        }
    }

    @Published var retentionCount: Int {
        didSet {
            UserDefaults.standard.set(retentionCount, forKey: Keys.retentionCount)
            onRetentionChanged?(retentionPolicy)
        }
    }

    @Published var hotkeyKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: Keys.hotkeyKeyCode)
            onHotkeyChanged?()
        }
    }

    @Published var hotkeyModifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(hotkeyModifiers), forKey: Keys.hotkeyModifiers)
            onHotkeyChanged?()
        }
    }

    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var lastLaunchAtLoginError: String?

    var onHotkeyChanged: (() -> Void)?
    var onRetentionChanged: ((RetentionPolicy) -> Void)?

    let retentionOptions = [1, 7, 30, 90, 180, 365]
    let retentionCountOptions = [50, 100, 200, 500, 1000, 2000]

    private init() {
        let savedRetention = UserDefaults.standard.integer(forKey: Keys.retentionDays)
        retentionDays = savedRetention == 0 ? 30 : savedRetention
        let savedRetentionCount = UserDefaults.standard.integer(forKey: Keys.retentionCount)
        retentionCount = savedRetentionCount == 0 ? 500 : savedRetentionCount

        let savedKeyCode = UserDefaults.standard.object(forKey: Keys.hotkeyKeyCode) as? Int
        let savedModifiers = UserDefaults.standard.object(forKey: Keys.hotkeyModifiers) as? Int
        hotkeyKeyCode = UInt32(savedKeyCode ?? Int(KeyCodes.c))
        hotkeyModifiers = UInt32(savedModifiers ?? Int(HotkeyModifierFlags.commandShift))

        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    var hotkeyDescription: String {
        "\(modifierDescription(hotkeyModifiers))\(KeyCodes.name(for: hotkeyKeyCode))"
    }

    var retentionPolicy: RetentionPolicy {
        RetentionPolicy(days: retentionDays, count: retentionCount)
    }

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            lastLaunchAtLoginError = nil
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            lastLaunchAtLoginError = error.localizedDescription
        }
    }

    private func modifierDescription(_ modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & HotkeyModifierFlags.control != 0 { parts.append("Control") }
        if modifiers & HotkeyModifierFlags.option != 0 { parts.append("Option") }
        if modifiers & HotkeyModifierFlags.shift != 0 { parts.append("Shift") }
        if modifiers & HotkeyModifierFlags.command != 0 { parts.append("Command") }
        return parts.isEmpty ? "" : parts.joined(separator: " + ") + " + "
    }
}

enum Keys {
    static let retentionDays = "retentionDays"
    static let retentionCount = "retentionCount"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
}

struct RetentionPolicy {
    let days: Int
    let count: Int
}

enum KeyCodes {
    static let c: UInt32 = 8
    static let k: UInt32 = 40

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K", 45: "N", 46: "M", 49: "Space"
    ]

    static func name(for keyCode: UInt32) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
