import Foundation
import GRDB

/// 各实体最后消费的服务端游标
struct SyncCursor: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_cursor"

    var entity: String
    var cursor: String?       // nil = 尚未引导(全量拉取)
    var lastSyncedAt: Date?
}

extension SyncCursor {
    static func get(_ db: Database, entity: String) throws -> String? {
        try SyncCursor.fetchOne(db, key: entity)?.cursor
    }

    static func set(_ db: Database, entity: String, cursor: String?) throws {
        let row = SyncCursor(entity: entity, cursor: cursor, lastSyncedAt: Date())
        try row.save(db)
    }
}
