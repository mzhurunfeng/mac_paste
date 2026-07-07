import AppKit
import Foundation

final class ClipboardMonitor {
    private let store: ClipboardStore
    private let onChange: (_ copied: Bool) -> Void
    private var timer: Timer?
    private var cleanupTimer: Timer?
    private var retentionPolicy: RetentionPolicy
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var isCapturingImage = false
    private let captureQueue = DispatchQueue(label: "com.macpaste.capture", qos: .userInitiated)

    init(store: ClipboardStore, onChange: @escaping (_ copied: Bool) -> Void) {
        self.store = store
        self.onChange = onChange
        self.retentionPolicy = RetentionPolicy(days: 30, count: 500)
    }

    func start(retentionPolicy: RetentionPolicy) {
        stop()
        self.retentionPolicy = retentionPolicy
        cleanup(retentionPolicy: retentionPolicy)
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60 * 30, repeats: true) { [weak self] _ in
            self?.cleanup()
        }
    }

    func stop() {
        timer?.invalidate()
        cleanupTimer?.invalidate()
        timer = nil
        cleanupTimer = nil
    }

    func cleanup(retentionPolicy: RetentionPolicy? = nil) {
        do {
            if let retentionPolicy {
                self.retentionPolicy = retentionPolicy
            }
            try applyCleanup()
            onChange(false)
        } catch {
            NSLog("MacPaste cleanup failed: \(error.localizedDescription)")
        }
    }

    private func applyCleanup() throws {
        try store.deleteExpired(retentionDays: retentionPolicy.days)
        try store.enforceItemLimit(maxItems: retentionPolicy.count)
        try store.enforceImageStorageLimit(maxBytes: StorageLimits.maxImageDirectoryBytes)
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else {
            return
        }

        if PasteboardGuard.shouldSuppress {
            lastChangeCount = currentChangeCount
            return
        }

        let sourceAppName = NSWorkspace.shared.frontmostApplication?.localizedName

        if let imageData = extractImageData(from: pasteboard) {
            guard !isCapturingImage else { return }
            lastChangeCount = currentChangeCount
            captureImage(imageData, sourceAppName: sourceAppName)
            return
        }

        if let draft = readTextDraft(from: pasteboard, sourceAppName: sourceAppName) {
            lastChangeCount = currentChangeCount
            capture(draft)
            return
        }

        lastChangeCount = currentChangeCount
    }

    private func captureImage(_ imageData: Data, sourceAppName: String?) {
        isCapturingImage = true
        captureQueue.async { [weak self] in
            guard let self else { return }
            defer {
                DispatchQueue.main.async {
                    self.isCapturingImage = false
                }
            }

            do {
                if let draft = try self.buildImageDraft(from: imageData, sourceAppName: sourceAppName) {
                    try self.store.upsert(draft)
                    try self.applyCleanup()
                    DispatchQueue.main.async {
                        self.onChange(true)
                    }
                }
            } catch {
                NSLog("MacPaste clipboard capture failed: \(error.localizedDescription)")
            }
        }
    }

    private func capture(_ draft: ClipboardItemDraft) {
        do {
            try store.upsert(draft)
            try applyCleanup()
            onChange(true)
        } catch {
            NSLog("MacPaste clipboard capture failed: \(error.localizedDescription)")
        }
    }

    private func extractImageData(from pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        if let data = pasteboard.data(forType: .tiff) {
            return data
        }
        return nil
    }

    private func readTextDraft(from pasteboard: NSPasteboard, sourceAppName: String?) -> ClipboardItemDraft? {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return nil
        }
        guard text.count <= StorageLimits.maxTextCharacters else {
            return nil
        }

        let type = ContentClassifier.classifyText(text)
        let metrics = ContentClassifier.textMetrics(text)
        let data = text.data(using: .utf8) ?? Data()
        return ClipboardItemDraft(
            type: type,
            title: ContentClassifier.title(for: text, type: type),
            textContent: text,
            imagePath: nil,
            createdAt: Date(),
            charCount: metrics.chars,
            wordCount: metrics.words,
            byteSize: metrics.bytes,
            width: nil,
            height: nil,
            contentHash: ContentClassifier.sha256Hex(data: data),
            sourceAppName: sourceAppName
        )
    }

    private func buildImageDraft(from imageData: Data, sourceAppName: String?) throws -> ClipboardItemDraft? {
        guard let bitmap = NSBitmapImageRep(data: imageData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        guard pngData.count <= StorageLimits.maxImageBytes else {
            return nil
        }

        let hash = ContentClassifier.sha256Hex(data: pngData)
        let imageURL = AppPaths.imageDirectory.appendingPathComponent("\(hash).png")
        if !FileManager.default.fileExists(atPath: imageURL.path) {
            try pngData.write(to: imageURL, options: .atomic)
        }

        let width = Int(bitmap.pixelsWide)
        let height = Int(bitmap.pixelsHigh)
        return ClipboardItemDraft(
            type: .image,
            title: "图片 \(width)x\(height)",
            textContent: nil,
            imagePath: imageURL.path,
            createdAt: Date(),
            charCount: 0,
            wordCount: 0,
            byteSize: pngData.count,
            width: width,
            height: height,
            contentHash: hash,
            sourceAppName: sourceAppName
        )
    }
}
