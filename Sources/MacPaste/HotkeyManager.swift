import Carbon
import Foundation

enum HotkeyModifierFlags {
    static let command: UInt32 = UInt32(cmdKey)
    static let shift: UInt32 = UInt32(shiftKey)
    static let option: UInt32 = UInt32(optionKey)
    static let control: UInt32 = UInt32(controlKey)
    static let commandShift: UInt32 = UInt32(cmdKey | shiftKey)
}

final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onPressed: () -> Void

    init(onPressed: @escaping () -> Void) {
        self.onPressed = onPressed
        installHandler()
    }

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        let hotkeyID = EventHotKeyID(signature: OSType(0x4D_50_53_54), id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status != noErr {
            hotkeyRef = nil
        }
    }

    private func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onPressed()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }
}
