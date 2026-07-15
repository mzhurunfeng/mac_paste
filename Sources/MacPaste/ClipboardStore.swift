import Foundation
import SQLite3

final class ClipboardStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.macpaste.store")

    init() throws {
        try AppPaths.ensureDirectories()
        guard sqlite3_open(AppPaths.databaseURL.path, &db) == SQLITE_OK else {
            throw StoreError.openFailed(message: lastErrorMessage)
        }
        try migrate()
    }

    deinit {
        queue.sync {
            if let db {
                sqlite3_close(db)
                self.db = nil
            }
        }
    }

    func upsert(_ item: ClipboardItemDraft) throws {
        try queue.sync {
            try upsertUnlocked(item)
        }
    }

    private func upsertUnlocked(_ item: ClipboardItemDraft) throws {
        let sql = """
        INSERT INTO clipboard_items (
            type, title, text_content, image_path, created_at, char_count,
            word_count, byte_size, width, height, content_hash, source_app_name
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(content_hash) DO UPDATE SET
            type = excluded.type,
            title = excluded.title,
            text_content = excluded.text_content,
            image_path = excluded.image_path,
            created_at = excluded.created_at,
            char_count = excluded.char_count,
            word_count = excluded.word_count,
            byte_size = excluded.byte_size,
            width = excluded.width,
            height = excluded.height,
            source_app_name = excluded.source_app_name
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        bind(text: item.type.rawValue, to: statement, at: 1)
        bind(text: item.title, to: statement, at: 2)
        bind(optionalText: item.textContent, to: statement, at: 3)
        bind(optionalText: item.imagePath, to: statement, at: 4)
        sqlite3_bind_double(statement, 5, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 6, Int64(item.charCount))
        sqlite3_bind_int64(statement, 7, Int64(item.wordCount))
        sqlite3_bind_int64(statement, 8, Int64(item.byteSize))
        bind(optionalInt: item.width, to: statement, at: 9)
        bind(optionalInt: item.height, to: statement, at: 10)
        bind(text: item.contentHash, to: statement, at: 11)
        bind(optionalText: item.sourceAppName, to: statement, at: 12)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.writeFailed(message: lastErrorMessage)
        }
    }

    func touchItem(id: Int64, at date: Date = Date()) throws {
        try queue.sync {
            let sql = "UPDATE clipboard_items SET created_at = ? WHERE id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepareFailed(message: lastErrorMessage)
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 2, id)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.writeFailed(message: lastErrorMessage)
            }
        }
    }

    func setFavorite(id: Int64, isFavorite: Bool) throws {
        try queue.sync {
            let sql = "UPDATE clipboard_items SET is_favorite = ? WHERE id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepareFailed(message: lastErrorMessage)
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, isFavorite ? 1 : 0)
            sqlite3_bind_int64(statement, 2, id)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.writeFailed(message: lastErrorMessage)
            }
        }
    }

    func deleteItem(id: Int64) throws {
        try queue.sync {
            let imagePath = try imagePathForItem(id: id)
            try deleteItemUnlocked(id: id)
            if let imagePath, try !imagePathIsReferenced(imagePath) {
                try? FileManager.default.removeItem(atPath: imagePath)
            }
        }
    }

    func fetchItems(searchQuery: String = "", filter: ClipboardFilter = .all, limit: Int = 50, offset: Int = 0) throws -> [ClipboardItem] {
        try queue.sync {
            try fetchItemsUnlocked(searchQuery: searchQuery, filter: filter, limit: limit, offset: offset)
        }
    }

    func fetchItemsAsync(
        searchQuery: String = "",
        filter: ClipboardFilter = .all,
        limit: Int = 50,
        offset: Int = 0,
        completion: @escaping (Result<[ClipboardItem], Error>) -> Void
    ) {
        queue.async {
            let result = Result {
                try self.fetchItemsUnlocked(searchQuery: searchQuery, filter: filter, limit: limit, offset: offset)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func fetchItemsUnlocked(searchQuery: String = "", filter: ClipboardFilter = .all, limit: Int = 50, offset: Int = 0) throws -> [ClipboardItem] {
        var clauses: [String] = []
        var values: [String] = []

        if let itemType = filter.itemType {
            clauses.append("type = ?")
            values.append(itemType.rawValue)
        }
        if filter == .favorite {
            clauses.append("is_favorite = 1")
        }

        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            clauses.append("(title LIKE ? OR text_content LIKE ? OR source_app_name LIKE ?)")
            values.append("%\(trimmedQuery)%")
            values.append("%\(trimmedQuery)%")
            values.append("%\(trimmedQuery)%")
        }

        let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = """
        SELECT id, type, title, text_content, image_path, created_at, char_count,
               word_count, byte_size, width, height, content_hash, source_app_name, is_favorite
        FROM clipboard_items
        \(whereSQL)
        ORDER BY created_at DESC
        LIMIT ?
        OFFSET ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in values.enumerated() {
            bind(text: value, to: statement, at: Int32(index + 1))
        }
        sqlite3_bind_int64(statement, Int32(values.count + 1), Int64(limit))
        sqlite3_bind_int64(statement, Int32(values.count + 2), Int64(offset))

        var items: [ClipboardItem] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let item = rowItem(statement) {
                items.append(item)
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw StoreError.readFailed(message: lastErrorMessage)
        }
        return items
    }

    func deleteExpired(retentionDays: Int) throws {
        try queue.sync {
            try deleteExpiredUnlocked(retentionDays: retentionDays)
        }
    }

    private func deleteExpiredUnlocked(retentionDays: Int) throws {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60).timeIntervalSince1970
        let expiredImages = try imagePaths(before: cutoff)

        var statement: OpaquePointer?
        let sql = "DELETE FROM clipboard_items WHERE created_at < ? AND is_favorite = 0"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, cutoff)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.writeFailed(message: lastErrorMessage)
        }

        for path in expiredImages {
            if try !imagePathIsReferenced(path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    func enforceItemLimit(maxItems: Int) throws {
        try queue.sync {
            try enforceItemLimitUnlocked(maxItems: maxItems)
        }
    }

    private func enforceItemLimitUnlocked(maxItems: Int) throws {
        let limit = max(1, maxItems)
        let expiredImages = try imagePathsAfterItemLimit(maxItems: limit)

        var statement: OpaquePointer?
        let sql = """
        DELETE FROM clipboard_items
        WHERE id IN (
            SELECT id FROM clipboard_items
            WHERE is_favorite = 0
            ORDER BY created_at DESC, id DESC
            LIMIT -1 OFFSET ?
        )
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(limit))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.writeFailed(message: lastErrorMessage)
        }

        for path in expiredImages {
            if try !imagePathIsReferenced(path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    func enforceImageStorageLimit(maxBytes: Int) throws {
        try queue.sync {
            try enforceImageStorageLimitUnlocked(maxBytes: maxBytes)
        }
    }

    private func enforceImageStorageLimitUnlocked(maxBytes: Int) throws {
        let images = try imageItemsOldestFirst()
        var totalBytes = images.reduce(0) { $0 + $1.byteSize }
        guard totalBytes > maxBytes else { return }

        for image in images {
            guard totalBytes > maxBytes else { break }
            try deleteItemUnlocked(id: image.id)
            if try !imagePathIsReferenced(image.path) {
                try? FileManager.default.removeItem(atPath: image.path)
                totalBytes = max(0, totalBytes - image.byteSize)
            }
        }
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            text_content TEXT,
            image_path TEXT,
            created_at REAL NOT NULL,
            char_count INTEGER NOT NULL DEFAULT 0,
            word_count INTEGER NOT NULL DEFAULT 0,
            byte_size INTEGER NOT NULL DEFAULT 0,
            width INTEGER,
            height INTEGER,
            content_hash TEXT NOT NULL UNIQUE,
            source_app_name TEXT,
            is_favorite INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_clipboard_items_created_at
            ON clipboard_items(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_clipboard_items_type
            ON clipboard_items(type);
        """

        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.migrationFailed(message: lastErrorMessage)
        }
        try addColumnIfNeeded(name: "source_app_name", definition: "TEXT")
        try addColumnIfNeeded(name: "is_favorite", definition: "INTEGER NOT NULL DEFAULT 0")
    }

    private func addColumnIfNeeded(name: String, definition: String) throws {
        guard try !columnExists(name) else { return }
        let sql = "ALTER TABLE clipboard_items ADD COLUMN \(name) \(definition)"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.migrationFailed(message: lastErrorMessage)
        }
    }

    private func columnExists(_ name: String) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(clipboard_items)", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if columnText(statement, 1) == name {
                return true
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw StoreError.readFailed(message: lastErrorMessage)
        }
        return false
    }

    private func imagePaths(before cutoff: TimeInterval) throws -> [String] {
        let sql = "SELECT image_path FROM clipboard_items WHERE created_at < ? AND is_favorite = 0 AND image_path IS NOT NULL"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, cutoff)
        var paths: [String] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let path = columnText(statement, 0) {
                paths.append(path)
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw StoreError.readFailed(message: lastErrorMessage)
        }
        return paths
    }

    private func imagePathsAfterItemLimit(maxItems: Int) throws -> [String] {
        let sql = """
        SELECT image_path FROM clipboard_items
        WHERE image_path IS NOT NULL
          AND is_favorite = 0
          AND id IN (
              SELECT id FROM clipboard_items
              WHERE is_favorite = 0
              ORDER BY created_at DESC, id DESC
              LIMIT -1 OFFSET ?
          )
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(maxItems))
        var paths: [String] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let path = columnText(statement, 0) {
                paths.append(path)
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw StoreError.readFailed(message: lastErrorMessage)
        }
        return paths
    }

    private func imageItemsOldestFirst() throws -> [(id: Int64, path: String, byteSize: Int)] {
        let sql = """
        SELECT id, image_path, byte_size
        FROM clipboard_items
        WHERE image_path IS NOT NULL AND is_favorite = 0
        ORDER BY created_at ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        var items: [(id: Int64, path: String, byteSize: Int)] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let path = columnText(statement, 1) {
                items.append((
                    id: sqlite3_column_int64(statement, 0),
                    path: path,
                    byteSize: Int(sqlite3_column_int64(statement, 2))
                ))
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw StoreError.readFailed(message: lastErrorMessage)
        }
        return items
    }

    private func deleteItemUnlocked(id: Int64) throws {
        var statement: OpaquePointer?
        let sql = "DELETE FROM clipboard_items WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.writeFailed(message: lastErrorMessage)
        }
    }

    private func imagePathForItem(id: Int64) throws -> String? {
        var statement: OpaquePointer?
        let sql = "SELECT image_path FROM clipboard_items WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, id)
        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            return columnText(statement, 0)
        }
        guard stepResult == SQLITE_DONE else {
            throw StoreError.readFailed(message: lastErrorMessage)
        }
        return nil
    }

    private func imagePathIsReferenced(_ path: String) throws -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM clipboard_items WHERE image_path = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        bind(text: path, to: statement, at: 1)
        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            return true
        }
        guard stepResult == SQLITE_DONE else {
            throw StoreError.readFailed(message: lastErrorMessage)
        }
        return false
    }

    private func rowItem(_ statement: OpaquePointer?) -> ClipboardItem? {
        guard
            let typeRaw = columnText(statement, 1),
            let type = ClipboardItemType(rawValue: typeRaw),
            let title = columnText(statement, 2),
            let contentHash = columnText(statement, 11)
        else {
            return nil
        }

        let widthValue = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 9))
        let heightValue = sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 10))

        return ClipboardItem(
            id: sqlite3_column_int64(statement, 0),
            type: type,
            title: title,
            textContent: columnText(statement, 3),
            imagePath: columnText(statement, 4),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
            charCount: Int(sqlite3_column_int64(statement, 6)),
            wordCount: Int(sqlite3_column_int64(statement, 7)),
            byteSize: Int(sqlite3_column_int64(statement, 8)),
            width: widthValue,
            height: heightValue,
            contentHash: contentHash,
            sourceAppName: columnText(statement, 12),
            isFavorite: sqlite3_column_int(statement, 13) != 0
        )
    }

    private func bind(text: String, to statement: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
    }

    private func bind(optionalText: String?, to statement: OpaquePointer?, at index: Int32) {
        if let optionalText {
            bind(text: optionalText, to: statement, at: index)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(optionalInt: Int?, to statement: OpaquePointer?, at index: Int32) {
        if let optionalInt {
            sqlite3_bind_int64(statement, index, Int64(optionalInt))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private var lastErrorMessage: String {
        guard let db, let error = sqlite3_errmsg(db) else {
            return "未知 SQLite 错误"
        }
        return String(cString: error)
    }
}

struct ClipboardItemDraft {
    let type: ClipboardItemType
    let title: String
    let textContent: String?
    let imagePath: String?
    let createdAt: Date
    let charCount: Int
    let wordCount: Int
    let byteSize: Int
    let width: Int?
    let height: Int?
    let contentHash: String
    let sourceAppName: String?
}

enum StoreError: LocalizedError {
    case openFailed(message: String)
    case migrationFailed(message: String)
    case prepareFailed(message: String)
    case readFailed(message: String)
    case writeFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "无法打开历史数据库：\(message)"
        case .migrationFailed(let message):
            return "无法迁移历史数据库：\(message)"
        case .prepareFailed(let message):
            return "无法准备数据库语句：\(message)"
        case .readFailed(let message):
            return "无法读取数据库记录：\(message)"
        case .writeFailed(let message):
            return "无法写入数据库记录：\(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
