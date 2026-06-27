import Foundation
import GRDB
import os.log

/// 同步引擎:本地写 → 发件箱;周期 = drain(推送) → pull(拉取)。
/// 冲突由服务端 LWW 裁决;本地采纳返回的胜出版本。
/// db 与 api 可注入(单测用内存 GRDB + mock 网络)。
actor SyncEngine {
    static let shared = SyncEngine()

    private let api: any SyncNetworking
    private let getDB: @Sendable () throws -> DatabaseQueue
    private let logger = Logger(subsystem: "com.boxs.app", category: "SyncEngine")
    private let batchSize = 50
    private let maxAttempts = 10
    private let minInterval: TimeInterval = 30
    private var lastSyncAt: Date = .distantPast
    private var isSyncing = false

    init(api: any SyncNetworking = APIClient.shared,
         getDB: @escaping @Sendable () throws -> DatabaseQueue = { try AppDatabase.shared.getDB() }) {
        self.api = api
        self.getDB = getDB
    }

    private func db() -> DatabaseQueue? { try? getDB() }

    // MARK: - 入队（本地写后调用）

    func enqueueExpense(_ r: ExpenseRecord) async {
        var rec = r; rec.updatedAt = Date()
        await saveLocal(rec)
        await enqueue("expenses", key: rec.id, ExpenseMapper.toChange(rec))
    }
    func enqueueExpenseDelete(id: String) async {
        guard var rec = await fetch(ExpenseRecord.self, id: id) else { return }
        rec.deletedAt = Date(); rec.isDeleted = true; rec.updatedAt = Date()
        await saveLocal(rec)
        await enqueue("expenses", key: rec.id, ExpenseMapper.toChange(rec))
    }
    func enqueueTodo(_ r: TodoRecord) async {
        var rec = r; rec.updatedAt = Date()
        await saveLocal(rec)
        await enqueue("todos", key: rec.id, TodoMapper.toChange(rec))
    }
    func enqueueTodoDelete(id: String) async {
        guard var rec = await fetch(TodoRecord.self, id: id) else { return }
        rec.deletedAt = Date(); rec.isDeleted = true; rec.updatedAt = Date()
        await saveLocal(rec)
        await enqueue("todos", key: rec.id, TodoMapper.toChange(rec))
    }
    func enqueueTodoComplete(id: String) async {
        guard var rec = await fetch(TodoRecord.self, id: id) else { return }
        rec.isCompleted = true; rec.completedAt = Date(); rec.updatedAt = Date()
        await saveLocal(rec)
        await enqueue("todos", key: rec.id, TodoMapper.toChange(rec))
    }
    func enqueueHabit(_ r: HabitDefinition) async {
        var rec = r; rec.updatedAt = Date()
        await saveLocal(rec)
        await enqueue("habits", key: rec.id, HabitMapper.toChange(rec))
    }
    func enqueueHabitArchive(id: String) async {
        guard var rec = await fetch(HabitDefinition.self, id: id) else { return }
        rec.isActive = false; rec.updatedAt = Date()
        await saveLocal(rec)
        await enqueue("habits", key: rec.id, HabitMapper.toChange(rec))
    }
    func enqueueCheckin(_ r: HabitRecord) async {
        var rec = r; rec.updatedAt = Date()
        await saveLocal(rec)
        let key = "\(rec.habitId)|\(formatDateYMD(rec.recordDate))"
        await enqueue("habit_checkins", key: key, HabitRecordMapper.toChange(rec))
    }

    private func enqueue<C: Encodable>(_ entity: String, key: String, _ change: C) async {
        guard let payload = try? JSONEncoder.boxs.encode(change) else { return }
        guard let dbq = db() else { return }
        _ = try? await dbq.write { try SyncOutbox.enqueue($0, entity: entity, recordKey: key, payload: payload) }
    }

    // MARK: - 本地读写助手

    private func saveLocal<T: PersistableRecord & Sendable>(_ rec: T) async {
        guard let dbq = db() else { return }
        _ = try? await dbq.write { db in var r = rec; try r.save(db) }
    }
    private func fetch<T>(_ type: T.Type, id: String) async -> T? where T: FetchableRecord & PersistableRecord & Sendable {
        guard let dbq = db() else { return nil }
        return try? await dbq.read { try T.fetchOne($0, key: id) }
    }

    // MARK: - drain(推送)——一次查询读全部 outbox,按实体分组

    func drainOutbox() async {
        guard let dbq = db() else { return }
        let all = (try? await dbq.read { try SyncOutbox.order(Column("id").asc).fetchAll($0) }) ?? []
        let grouped = Dictionary(grouping: all, by: \.entity)
        await drain(grouped["expenses"] ?? [], endpoint: Endpoints.expenseBatch,
                    change: ExpenseChange.self, dto: ExpenseDTO.self, keyFor: { $0.id }) { db, dto in
            let rec = ExpenseMapper.toLocal(dto)
            try db.execute(sql: "DELETE FROM expense_record WHERE id = ?", arguments: [rec.id])
            var r = rec; try r.insert(db)
        }
        await drain(grouped["todos"] ?? [], endpoint: Endpoints.todoBatch,
                    change: TodoChange.self, dto: TodoDTO.self, keyFor: { $0.id }) { db, dto in
            let rec = TodoMapper.toLocal(dto)
            try db.execute(sql: "DELETE FROM todo_record WHERE id = ?", arguments: [rec.id])
            var r = rec; try r.insert(db)
        }
        await drain(grouped["habits"] ?? [], endpoint: Endpoints.habitBatch,
                    change: HabitChange.self, dto: HabitDefinitionDTO.self, keyFor: { $0.id }) { db, dto in
            let rec = HabitMapper.toLocal(dto)
            try db.execute(sql: "DELETE FROM habit_definition WHERE id = ?", arguments: [rec.id])
            var r = rec; try r.insert(db)
        }
        await drain(grouped["habit_checkins"] ?? [], endpoint: Endpoints.checkinBatch,
                    change: CheckinChange.self, dto: HabitRecordDTO.self,
                    keyFor: { "\($0.habit_id)|\($0.record_date)" }) { db, dto in
            var rec = HabitRecordMapper.toLocal(dto)
            try HabitRecord.filter(Column("habitId") == rec.habitId && Column("recordDate") == rec.recordDate).deleteAll(db)
            try rec.insert(db)
        }
    }

    /// 解码 payload → 批量推送 → 批量对账(一个事务内应用 + 清 outbox / bump 死信)
    private func drain<C: Codable & Sendable, D: Decodable & Sendable>(
        _ rows: [SyncOutbox], endpoint: Endpoint, change: C.Type, dto: D.Type,
        keyFor: @escaping @Sendable (D) -> String,
        applyOne: @escaping @Sendable (Database, D) throws -> Void
    ) async {
        // 解码 payload(失败的行跳过,保持对齐)
        var drows: [SyncOutbox] = []; var changes: [C] = []
        for r in rows {
            guard let c = try? JSONDecoder.boxs.decode(C.self, from: r.payload) else { continue }
            drows.append(r); changes.append(c)
        }
        guard !changes.isEmpty else { return }
        do {
            let results: [BatchResult<D>] = try await api.send(endpoint, body: BatchRequest(changes: changes))
            await reconcileBatch(drows, results, applyOne: applyOne)
        } catch {
            await bumpAttempts(ids: drows.map { $0.id })
            logger.warning("drain 失败: \(error.localizedDescription)")
        }
    }

    /// drain 对账:applied/conflict 采纳服务端版本并清 outbox;error 留待重试/死信。全部在一个事务。
    private func reconcileBatch<D: Sendable>(
        _ rows: [SyncOutbox], _ results: [BatchResult<D>],
        applyOne: @escaping @Sendable (Database, D) throws -> Void
    ) async {
        guard let dbq = db() else { return }
        _ = try? await dbq.write { db in
            for (i, row) in rows.enumerated() where i < results.count {
                switch results[i].status {
                case "applied", "conflict":
                    if let rec = results[i].record { try applyOne(db, rec) }
                    if let oid = row.id { try SyncOutbox.deleteOne(db, key: oid) }
                default:
                    if let oid = row.id, var r = try SyncOutbox.fetchOne(db, key: oid) {
                        r.attempts += 1
                        if r.attempts >= self.maxAttempts { r.dead = true }
                        try r.update(db)
                    }
                }
            }
        }
    }

    private func bumpAttempts(ids: [Int64?]) async {
        guard let dbq = db() else { return }
        _ = try? await dbq.write { db in
            for id in ids.compactMap({ $0 }) {
                guard var r = try SyncOutbox.fetchOne(db, key: id) else { continue }
                r.attempts += 1
                if r.attempts >= maxAttempts { r.dead = true }
                try r.update(db)
            }
        }
    }

    /// 死信数量(供 UI 展示"有同步失败")
    func deadLetterCount() async -> Int {
        guard let dbq = db() else { return 0 }
        return (try? await dbq.read { try SyncOutbox.deadCount($0) }) ?? 0
    }

    /// 待发数量(供 UI 展示"排队中")
    func pendingCount() async -> Int {
        guard let dbq = db() else { return 0 }
        return (try? await dbq.read { try SyncOutbox.filter(Column("dead") == false).fetchCount($0) }) ?? 0
    }

    /// 重试全部死信(清标记,重新进入待发)
    func retryDeadLetters() async {
        guard let dbq = db() else { return }
        _ = try? await dbq.write { try SyncOutbox.resetDead($0) }
        await sync(force: true)
    }

    // MARK: - pull(增量)——每页一个事务批量应用

    func pullAll() async { await pull(entities: SyncOutbox.allEntities) }

    /// 只拉取指定实体(页面按需调用);drain 始终推送全部 pending
    func pull(entities: [String]) async {
        for e in entities {
            switch e {
            case "expenses": await pullLoop(entity: "expenses", endpoint: { Endpoints.expenseChanges(cursor: $0, since: $1) },
                                            keyFor: { (d: ExpenseDTO) in d.id }) { db, dto in
                let rec = ExpenseMapper.toLocal(dto)
                try db.execute(sql: "DELETE FROM expense_record WHERE id = ?", arguments: [rec.id])
                var r = rec; try r.insert(db)
            }
            case "todos": await pullLoop(entity: "todos", endpoint: { Endpoints.todoChanges(cursor: $0, since: $1) },
                                         keyFor: { (d: TodoDTO) in d.id }) { db, dto in
                let rec = TodoMapper.toLocal(dto)
                try db.execute(sql: "DELETE FROM todo_record WHERE id = ?", arguments: [rec.id])
                var r = rec; try r.insert(db)
            }
            case "habits": await pullLoop(entity: "habits", endpoint: { Endpoints.habitChanges(cursor: $0, since: $1) },
                                          keyFor: { (d: HabitDefinitionDTO) in d.id }) { db, dto in
                let rec = HabitMapper.toLocal(dto)
                try db.execute(sql: "DELETE FROM habit_definition WHERE id = ?", arguments: [rec.id])
                var r = rec; try r.insert(db)
            }
            case "habit_checkins": await pullLoop(entity: "habit_checkins", endpoint: { Endpoints.checkinChanges(cursor: $0, since: $1) },
                                                  keyFor: { (d: HabitRecordDTO) in "\(d.habit_id)|\(d.record_date)" }) { db, dto in
                var rec = HabitRecordMapper.toLocal(dto)
                try HabitRecord.filter(Column("habitId") == rec.habitId && Column("recordDate") == rec.recordDate).deleteAll(db)
                try rec.insert(db)
            }
            default: break
            }
        }
    }

    /// 翻页拉取直到 next_cursor == nil;每页用 applyBatch 批量应用后存新游标。
    /// 引导(cursor 为空)时传 since(近 12 个月),有界化首次同步。
    private func pullLoop<D: Decodable & Sendable>(
        entity: String,
        endpoint: @escaping @Sendable (String?, String?) -> Endpoint,
        keyFor: @escaping @Sendable (D) -> String,
        applyOne: @escaping @Sendable (Database, D) throws -> Void
    ) async {
        var cursor = await readCursor(entity)
        repeat {
            let since = cursor == nil ? Self.bootstrapSince() : nil
            let resp: ChangesResponse<D>
            do { resp = try await api.send(endpoint(cursor, since), body: nil) }
            catch { logger.warning("pull \(entity) 失败: \(error.localizedDescription)"); return }
            await applyBatch(resp.items, entity: entity, keyFor: keyFor, applyOne: applyOne)
            cursor = resp.next_cursor
            await writeCursor(entity, cursor)
        } while cursor != nil
    }

    /// 引导窗口:近 12 个月
    private static func bootstrapSince() -> String {
        let d = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date()
        return formatISO8601(d)
    }

    /// 一页一次事务:批量取 pending key,跳过 pending 的(不覆盖未 drain 的本地编辑),其余批量 delete+insert
    private func applyBatch<D: Sendable>(
        _ items: [D], entity: String,
        keyFor: @escaping @Sendable (D) -> String,
        applyOne: @escaping @Sendable (Database, D) throws -> Void
    ) async {
        guard let dbq = db() else { return }
        _ = try? await dbq.write { db in
            let pendingKeys = Set((try? SyncOutbox
                .filter(Column("entity") == entity)
                .fetchAll(db)
                .map(\.recordKey)) ?? [])
            for item in items {
                guard !pendingKeys.contains(keyFor(item)) else { continue }
                try applyOne(db, item)
            }
        }
    }

    private func readCursor(_ entity: String) async -> String? {
        guard let dbq = db() else { return nil }
        return try? await dbq.read { try SyncCursor.get($0, entity: entity) }
    }
    private func writeCursor(_ entity: String, _ cursor: String?) async {
        guard let dbq = db() else { return }
        _ = try? await dbq.write { try SyncCursor.set($0, entity: entity, cursor: cursor) }
    }

    // MARK: - 周期入口

    /// - Parameter entities: 本次 pull 的实体(默认全部);drain 始终推送全部 pending。
    /// - Parameter force: 用户驱动的刷新(页面出现)传 true,绕过防抖;后台/联网触发用默认 false。
    func sync(entities: [String] = SyncOutbox.allEntities, force: Bool = false) async {
        guard TokenManager.shared.isLoggedIn else { return }
        if isSyncing { return }
        if !force && Date().timeIntervalSince(lastSyncAt) < minInterval { return }
        isSyncing = true
        defer { isSyncing = false; lastSyncAt = Date() }
        logger.info("sync 周期开始 force=\(force) entities=\(entities)")
        await drainOutbox()
        await pull(entities: entities)
        logger.info("sync 周期完成")
    }
}
