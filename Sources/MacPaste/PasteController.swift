import AppKit
import Foundation

enum PasteController {
    @discardableResult
    static func copyAndPaste(_ item: ClipboardItem, directPaste: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        let previousItems = duplicate(pasteboard.pasteboardItems ?? [])
        let didWrite: Bool

        switch item.type {
        case .image:
            guard let imagePath = item.imagePath,
                  let image = NSImage(contentsOfFile: imagePath) else {
                return false
            }
            pasteboard.clearContents()
            didWrite = pasteboard.writeObjects([image])
        case .text, .link, .color:
            guard let text = item.textContent, !text.isEmpty else {
                return false
            }
            pasteboard.clearContents()
            didWrite = pasteboard.setString(text, forType: .string)
        }

        guard didWrite else {
            restore(previousItems, to: pasteboard)
            return false
        }

        PasteboardGuard.suppress()

        guard directPaste, AXIsProcessTrusted() else {
            return true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            simulateCommandV()
        }
        return true
    }

    private static func simulateCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func duplicate(_ items: [NSPasteboardItem]) -> [NSPasteboardItem] {
        items.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}
