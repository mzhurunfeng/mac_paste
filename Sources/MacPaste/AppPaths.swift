import Foundation

enum AppPaths {
    static let appSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacPaste", isDirectory: true)
    }()

    static let imageDirectory: URL = {
        appSupportDirectory.appendingPathComponent("Images", isDirectory: true)
    }()

    static let databaseURL: URL = {
        appSupportDirectory.appendingPathComponent("history.sqlite3")
    }()

    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    }
}
