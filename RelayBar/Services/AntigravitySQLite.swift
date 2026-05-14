import Foundation
import SQLite3

final class AntigravitySQLiteDatabase {
    private var db: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let message = db.flatMap { sqlite3_errmsg($0).map(String.init(cString:)) } ?? "unknown sqlite error"
            throw AntigravitySQLiteError.openFailed(url.path, message)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func queryString(_ sql: String, bindings: [String] = []) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw currentError(.prepareFailed(sql))
        }
        defer { sqlite3_finalize(statement) }

        try bind(strings: bindings, to: statement)

        let step = sqlite3_step(statement)
        if step == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else {
                return nil
            }
            return String(cString: text)
        }

        if step == SQLITE_DONE {
            return nil
        }

        throw currentError(.queryFailed(sql))
    }

    func queryStringRows(_ sql: String, bindings: [String] = []) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw currentError(.prepareFailed(sql))
        }
        defer { sqlite3_finalize(statement) }

        try bind(strings: bindings, to: statement)

        var rows: [[String?]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                return rows
            }
            guard step == SQLITE_ROW else {
                throw currentError(.queryFailed(sql))
            }

            let columnCount = sqlite3_column_count(statement)
            var row: [String?] = []
            for column in 0..<columnCount {
                guard let bytes = sqlite3_column_blob(statement, column) else {
                    row.append(nil)
                    continue
                }
                let length = Int(sqlite3_column_bytes(statement, column))
                let data = Data(bytes: bytes, count: length)
                row.append(String(data: data, encoding: .utf8))
            }
            rows.append(row)
        }
    }

    func execute(_ sql: String, bindings: [String] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw currentError(.prepareFailed(sql))
        }
        defer { sqlite3_finalize(statement) }

        try bind(strings: bindings, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw currentError(.executeFailed(sql))
        }
    }

    private func bind(strings: [String], to statement: OpaquePointer?) throws {
        for (index, value) in strings.enumerated() {
            let sqliteIndex = Int32(index + 1)
            guard sqlite3_bind_text(statement, sqliteIndex, value, -1, sqliteTransient) == SQLITE_OK else {
                throw currentError(.bindFailed)
            }
        }
    }

    private var sqliteTransient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private func currentError(_ fallback: AntigravitySQLiteError) -> AntigravitySQLiteError {
        if let db, let message = sqlite3_errmsg(db) {
            return .sqlite(String(cString: message))
        }
        return fallback
    }
}

enum AntigravitySQLiteError: LocalizedError {
    case openFailed(String, String)
    case prepareFailed(String)
    case bindFailed
    case queryFailed(String)
    case executeFailed(String)
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let message):
            return "打开 Antigravity state.vscdb 失败: \(path) (\(message))"
        case .prepareFailed:
            return "准备 Antigravity SQLite 语句失败"
        case .bindFailed:
            return "绑定 Antigravity SQLite 参数失败"
        case .queryFailed:
            return "读取 Antigravity SQLite 数据失败"
        case .executeFailed:
            return "写入 Antigravity SQLite 数据失败"
        case .sqlite(let message):
            return "Antigravity SQLite 错误: \(message)"
        }
    }
}
