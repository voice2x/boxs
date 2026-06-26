import Foundation
import GRDB

/// 同步发件箱：待推送的本地变更（推送权威源）
struct SyncOutbox: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_outbox"

    var id: Int64?
    var entity: String       // "expenses" | "todos" | "habits" | "habit_checkins"
    var recordKey: String    // id 或 "habitId|recordDate"
    var op: String           // "upsert"
    var payload: Data        // 该实体 change 的 JSON 快照
    var attempts: Int
    var createdAt: Date
}

extension SyncOutbox {
    /// 入队：同一 (entity, recordKey) 只保留最新一条（先删后插）
    static func enqueue(_ db: Database, entity: String, recordKey: String, payload: Data) throws {
        try SyncOutbox
            .filter(Column("entity") == entity && Column("recordKey") == recordKey)
            .deleteAll(db)
        var row = SyncOutbox(id: nil, entity: entity, recordKey: recordKey, op: "upsert",
                             payload: payload, attempts: 0, createdAt: Date())
        try row.insert(db)
    }

    /// 取某实体待发(按 id 升序)
    static func pending(_ db: Database, entity: String, limit: Int) throws -> [SyncOutbox] {
        try SyncOutbox
            .filter(Column("entity") == entity)
            .order(Column("id").asc)
            .limit(limit)
            .fetchAll(db)
    }

    static let allEntities = ["expenses", "todos", "habits", "habit_checkins"]
}
