import XCTest
import GRDB
@testable import Boxs

/// SyncEngine 编排测试(drain/pull/跳过 pending),内存 GRDB + mock 网络。
final class SyncEngineTests: XCTestCase {

    /// 内存库:expense_record + sync_outbox + sync_cursor
    private func makeDB() throws -> DatabaseQueue {
        let db = try DatabaseQueue()
        try db.write { db in
            try db.create(table: "expense_record") { t in
                t.column("id", .text).primaryKey()
                t.column("userId", .text).notNull()
                t.column("type", .text).notNull()
                t.column("amountCents", .integer).notNull()
                t.column("currency", .text).notNull().defaults(to: "CNY")
                t.column("category", .text).notNull()
                t.column("merchant", .text)
                t.column("note", .text)
                t.column("recordDate", .date).notNull()
                t.column("source", .text).notNull().defaults(to: "text")
                t.column("isDeleted", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime)
                t.column("deletedAt", .datetime)
            }
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

    private func expenseDTO(_ id: String, _ cents: Int) -> [String: Any] {
        ["id": id, "user_id": "u", "record_type": "expense", "amount_cents": cents,
         "category": "food", "note": NSNull(), "record_date": "2026-06-01",
         "deleted_at": NSNull(), "created_at": "2026-06-01T00:00:00Z", "updated_at": "2026-06-01T00:00:00Z"]
    }

    /// drain:入队 → 服务端 applied → 本地采纳服务端版本 + outbox 清空
    func testDrainAppliesServerVersionAndClearsOutbox() async throws {
        let holder = DBHolder(try makeDB())
        let mock = MockNetworking()
        let engine = SyncEngine(api: mock, getDB: { holder.db })

        var rec = ExpenseRecord.create(amountCents: 100, category: "food")
        rec.id = "e1"
        await engine.enqueueExpense(rec)
        let before = try await holder.db.read { try SyncOutbox.fetchCount($0) }
        XCTAssertEqual(before, 1)

        mock.respond(try JSONSerialization.data(withJSONObject: [["status": "applied", "record": expenseDTO("e1", 999)]]))
        await engine.drainOutbox()

        let after = try await holder.db.read { try SyncOutbox.fetchCount($0) }
        XCTAssertEqual(after, 0, "drain 后 outbox 应清空")
        let local = try await holder.db.read { try ExpenseRecord.fetchOne($0, key: "e1") }
        XCTAssertEqual(local?.amountCents, 999, "应采纳服务端版本")
    }

    /// drain LWW conflict:服务端返回 conflict + 胜出版本 → 本地采纳,清 outbox
    func testDrainConflictAdoptsWinner() async throws {
        let holder = DBHolder(try makeDB())
        let mock = MockNetworking()
        let engine = SyncEngine(api: mock, getDB: { holder.db })

        var rec = ExpenseRecord.create(amountCents: 100, category: "food")
        rec.id = "e2"
        await engine.enqueueExpense(rec)

        mock.respond(try JSONSerialization.data(withJSONObject: [["status": "conflict", "record": expenseDTO("e2", 777)]]))
        await engine.drainOutbox()

        let local = try await holder.db.read { try ExpenseRecord.fetchOne($0, key: "e2") }
        XCTAssertEqual(local?.amountCents, 777, "conflict 也应采纳服务端胜出版本")
        let n = try await holder.db.read { try SyncOutbox.fetchCount($0) }
        XCTAssertEqual(n, 0, "conflict 行也应清 outbox")
    }

    /// pull:服务端返回 items → 本地应用 + 翻页(第二页 next_cursor nil 停止)
    func testPullAppliesAndPaginates() async throws {
        let holder = DBHolder(try makeDB())
        let mock = MockNetworking()
        let engine = SyncEngine(api: mock, getDB: { holder.db })

        let page1: [String: Any] = ["items": [expenseDTO("s1", 500)], "next_cursor": "cur1"]
        let page2: [String: Any] = ["items": [expenseDTO("s2", 600)], "next_cursor": NSNull()]
        mock.respond(try JSONSerialization.data(withJSONObject: page1))
        mock.respond(try JSONSerialization.data(withJSONObject: page2))

        await engine.pull(entities: ["expenses"])

        let s1 = try await holder.db.read { try ExpenseRecord.fetchOne($0, key: "s1") }
        let s2 = try await holder.db.read { try ExpenseRecord.fetchOne($0, key: "s2") }
        XCTAssertNotNil(s1)
        XCTAssertNotNil(s2, "应翻到第二页")
    }

    /// pull 跳过 pending:本地 outbox 有该 key 的待发行时,pull 不覆盖本地编辑
    func testPullSkipsPendingOutbox() async throws {
        let holder = DBHolder(try makeDB())
        try await holder.db.write { db in
            var rec = ExpenseRecord.create(amountCents: 100, category: "food"); rec.id = "p1"
            try rec.save(db)
            try SyncOutbox.enqueue(db, entity: "expenses", recordKey: "p1", payload: Data([1]))
        }
        let mock = MockNetworking()
        let engine = SyncEngine(api: mock, getDB: { holder.db })
        mock.respond(try JSONSerialization.data(withJSONObject: ["items": [expenseDTO("p1", 999)], "next_cursor": NSNull()]))

        await engine.pull(entities: ["expenses"])

        let local = try await holder.db.read { try ExpenseRecord.fetchOne($0, key: "p1") }
        XCTAssertEqual(local?.amountCents, 100, "pending 期间不应被服务端覆盖")
    }
}

// MARK: - 测试辅助

/// 持有非 Sendable 的 DatabaseQueue,使闭包可 @Sendable 捕获
private final class DBHolder: @unchecked Sendable { let db: DatabaseQueue; init(_ db: DatabaseQueue) { self.db = db } }

/// mock 网络:按入队顺序返回响应(FIFO)
private final class MockNetworking: SyncNetworking, @unchecked Sendable {
    private var queue: [Data] = []
    func respond(_ data: Data) { queue.append(data) }
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint, body: (any Encodable & Sendable)?) async throws -> T {
        let data = queue.isEmpty ? Data() : queue.removeFirst()
        return try JSONDecoder.boxs.decode(T.self, from: data)
    }
}
