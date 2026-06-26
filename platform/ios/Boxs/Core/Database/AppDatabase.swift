import Foundation
import GRDB
import os.log

/// 本地 SQLite 数据库管理器（单例）
final class AppDatabase {
    static nonisolated(unsafe) let shared = AppDatabase()

    private var dbQueue: DatabaseQueue?
    private let logger = Logger(subsystem: "com.boxs.app", category: "Database")

    private init() {}

    // MARK: - 公开接口

    /// 初始化数据库（App 启动时调用）
    func setup() throws {
        let dbURL = try databaseURL()
        var config = Configuration()
        config.prepareDatabase { db in
            // 启用 WAL 模式，提升并发读写性能
            try db.execute(sql: "PRAGMA journal_mode=WAL")
            try db.execute(sql: "PRAGMA foreign_keys=ON")
        }
        dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
        try migrate()
        logger.info("数据库初始化完成: \(dbURL.path)")
    }

    /// 获取 DatabaseQueue（所有数据库操作通过此方法获取连接）
    func getDB() throws -> DatabaseQueue {
        guard let dbQueue else {
            throw DatabaseError.notInitialized
        }
        return dbQueue
    }

    // MARK: - 私有方法

    private func databaseURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbDir = appSupport.appendingPathComponent("Boxs", isDirectory: true)
        try fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)
        return dbDir.appendingPathComponent("boxs.sqlite")
    }

    private func migrate() throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }

        var migrator = DatabaseMigrator()
        // 开发期间禁用破坏性变更校验
        migrator.eraseDatabaseOnSchemaChange = true

        // v1: 初始表结构
        migrator.registerMigration("v1_create_tables") { db in
            // 记账表
            try db.create(table: "expense_record") { t in
                t.column("id", .text).primaryKey()
                t.column("userId", .text).notNull()
                t.column("type", .text).notNull() // expense / income / transfer
                t.column("amountCents", .integer).notNull()
                t.column("currency", .text).notNull().defaults(to: "CNY")
                t.column("category", .text).notNull()
                t.column("merchant", .text)
                t.column("note", .text)
                t.column("recordDate", .date).notNull()
                t.column("source", .text).notNull().defaults(to: "text") // voice / text / ocr
                t.column("isDeleted", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime)
                t.column("deletedAt", .datetime)
            }

            // 习惯定义表
            try db.create(table: "habit_definition") { t in
                t.column("id", .text).primaryKey()
                t.column("userId", .text).notNull()
                t.column("name", .text).notNull()
                t.column("icon", .text)
                t.column("unit", .text)
                t.column("goalValue", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime)
            }

            // 习惯打卡记录表
            try db.create(table: "habit_record") { t in
                t.column("id", .text).primaryKey()
                t.column("userId", .text).notNull()
                t.column("habitId", .text).notNull()
                    .references("habit_definition", onDelete: .cascade)
                t.column("value", .text)
                t.column("recordDate", .date).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime)
                t.uniqueKey(["habitId", "recordDate"])
            }

            // 待办/备忘表
            try db.create(table: "todo_record") { t in
                t.column("id", .text).primaryKey()
                t.column("userId", .text).notNull()
                t.column("type", .text).notNull() // todo / memo / idea
                t.column("content", .text).notNull()
                t.column("remindAt", .datetime)
                t.column("priority", .text).notNull().defaults(to: "medium")
                t.column("isCompleted", .boolean).notNull().defaults(to: false)
                t.column("completedAt", .datetime)
                t.column("isDeleted", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime)
                t.column("deletedAt", .datetime)
            }
        }

        // v2: 同步发件箱 + 游标
        migrator.registerMigration("v2_sync") { db in
            try db.create(table: "sync_outbox") { t in
                t.column("id", .integer).primaryKey(autoincrement: true)
                t.column("entity", .text).notNull()
                t.column("recordKey", .text).notNull()
                t.column("op", .text).notNull().defaults(to: "upsert")
                t.column("payload", .blob).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["entity", "recordKey"])
            }
            try db.create(table: "sync_cursor") { t in
                t.column("entity", .text).primaryKey()
                t.column("cursor", .text)
                t.column("lastSyncedAt", .datetime)
            }
        }

        // v3: 发件箱死信标记(到重试上限标记 dead,不再静默丢弃)
        migrator.registerMigration("v3_outbox_dead") { db in
            try db.alter(table: "sync_outbox") { t in
                t.add(column: "dead", .boolean).notNull().defaults(to: false)
            }
        }

        try migrator.migrate(dbQueue)
        logger.info("数据库迁移完成")
    }
}

// MARK: - 错误类型

enum DatabaseError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "数据库未初始化，请先调用 AppDatabase.shared.setup()"
        }
    }
}
