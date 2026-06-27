import XCTest
import GRDB
@testable import Boxs

/// SyncOutbox / SyncCursor 持久层测试(内存 GRDB,无需网络)。
/// 覆盖:发件箱去重、待发排序与死信排除、死信计数/重置、游标存取。
final class SyncOutboxTests: XCTestCase {

    /// 建一张内存库,含 sync_outbox + sync_cursor(同 AppDatabase v2/v3 迁移结构)
    private func makeDB() throws -> DatabaseQueue {
        let db = try DatabaseQueue()
        try db.write { db in
            try db.create(table: "sync_outbox") { t in
                t.column("id", .integer).primaryKey(autoincrement: true)
                t.column("entity", .text).notNull()
                t.column("recordKey", .text).notNull()
                t.column("op", .text).notNull().defaults(to: "upsert")
                t.column("payload", .blob).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("dead", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["entity", "recordKey"])
            }
            try db.create(table: "sync_cursor") { t in
                t.column("entity", .text).primaryKey()
                t.column("cursor", .text)
                t.column("lastSyncedAt", .datetime)
            }
        }
        return db
    }

    func testEnqueueDedupSameKey() throws {
        let db = try makeDB()
        try db.write { db in
            try SyncOutbox.enqueue(db, entity: "expenses", recordKey: "k1", payload: Data([1]))
            try SyncOutbox.enqueue(db, entity: "expenses", recordKey: "k1", payload: Data([2])) // 同 key 覆盖
            try SyncOutbox.enqueue(db, entity: "expenses", recordKey: "k2", payload: Data([3]))
        }
        let pending = try db.read { try SyncOutbox.pending($0, entity: "expenses", limit: 10) }
        XCTAssertEqual(pending.count, 2) // k1(最新) + k2
        let k1 = pending.first { $0.recordKey == "k1" }
        XCTAssertEqual(k1?.payload, Data([2]), "同 key 应只保留最新 payload")
    }

    func testPendingExcludesDead() throws {
        let db = try makeDB()
        try db.write { db in
            try SyncOutbox.enqueue(db, entity: "todos", recordKey: "a", payload: Data([1]))
            try SyncOutbox.enqueue(db, entity: "todos", recordKey: "b", payload: Data([2]))
            try db.execute(sql: "UPDATE sync_outbox SET dead = true WHERE recordKey = 'a'")
        }
        let pending = try db.read { try SyncOutbox.pending($0, entity: "todos", limit: 10) }
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.recordKey, "b", "死信不应进入待发")
    }

    func testPendingOrderAndLimit() throws {
        let db = try makeDB()
        try db.write { db in
            for i in 0..<5 { try SyncOutbox.enqueue(db, entity: "habits", recordKey: "k\(i)", payload: Data([UInt8(i)])) }
        }
        let page = try db.read { try SyncOutbox.pending($0, entity: "habits", limit: 2) }
        XCTAssertEqual(page.count, 2)
        XCTAssertEqual(page.first?.recordKey, "k0", "应按 id 升序(先入先出)")
    }

    func testDeadCountAndReset() throws {
        let db = try makeDB()
        try db.write { db in
            try SyncOutbox.enqueue(db, entity: "expenses", recordKey: "k1", payload: Data([1]))
            try db.execute(sql: "UPDATE sync_outbox SET dead = true WHERE recordKey = 'k1'")
        }
        XCTAssertEqual(try db.read { try SyncOutbox.deadCount($0) }, 1)
        try db.write { try SyncOutbox.resetDead($0) }
        XCTAssertEqual(try db.read { try SyncOutbox.deadCount($0) }, 0, "resetDead 应清零死信")
        // 重置后重新进入待发
        XCTAssertEqual(try db.read { try SyncOutbox.pending($0, entity: "expenses", limit: 10) }.count, 1)
    }

    func testCursorGetSet() throws {
        let db = try makeDB()
        XCTAssertNil(try db.read { try SyncCursor.get($0, entity: "expenses") })
        try db.write { try SyncCursor.set($0, entity: "expenses", cursor: "abc") }
        XCTAssertEqual(try db.read { try SyncCursor.get($0, entity: "expenses") }, "abc")
        try db.write { try SyncCursor.set($0, entity: "expenses", cursor: nil) }
        XCTAssertNil(try db.read { try SyncCursor.get($0, entity: "expenses") })
    }
}
