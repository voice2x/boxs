import Foundation
import GRDB
import os.log

/// 同步引擎:本地写 → 发件箱;周期 = drain(推送) → pull(拉取)。
/// 冲突由服务端 LWW 裁决;本地采纳返回的胜出版本。
actor SyncEngine {
    static let shared = SyncEngine()

    private let api = APIClient.shared
    private let logger = Logger(subsystem: "com.boxs.app", category: "SyncEngine")
    private let batchSize = 50
    private let maxAttempts = 10
    private let minInterval: TimeInterval = 30
    private var lastSyncAt: Date = .distantPast
    private var isSyncing = false

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
        guard let db = try? AppDatabase.shared.getDB() else { return }
        _ = try? await db.write { try SyncOutbox.enqueue($0, entity: entity, recordKey: key, payload: payload) }
    }

    // MARK: - 本地读写助手

    private func saveLocal<T: PersistableRecord & Sendable>(_ rec: T) async {
        guard let db = try? AppDatabase.shared.getDB() else { return }
        _ = try? await db.write { db in var r = rec; try r.save(db) }
    }
    private func fetch<T>(_ type: T.Type, id: String) async -> T? where T: FetchableRecord & PersistableRecord & Sendable {
        guard let db = try? AppDatabase.shared.getDB() else { return nil }
        return try? await db.read { try T.fetchOne($0, key: id) }
    }

    // MARK: - drain(推送)

    func drainOutbox() async {
        await drainExpenses(); await drainTodos(); await drainHabits(); await drainCheckins()
    }

    private func drainExpenses() async {
        guard let (rows, changes) = await collect("expenses", as: ExpenseChange.self), !changes.isEmpty else { return }
        do {
            let results: [BatchResult<ExpenseDTO>] = try await api.request(Endpoints.expenseBatch, body: BatchRequest(changes: changes))
            await reconcile(rows, results) { await self.applyExpense($0) }
        } catch {
            await bumpAttempts(ids: rows.map { $0.id }); logger.warning("drain expenses 失败: \(error.localizedDescription)")
        }
    }
    private func drainTodos() async {
        guard let (rows, changes) = await collect("todos", as: TodoChange.self), !changes.isEmpty else { return }
        do {
            let results: [BatchResult<TodoDTO>] = try await api.request(Endpoints.todoBatch, body: BatchRequest(changes: changes))
            await reconcile(rows, results) { await self.applyTodo($0) }
        } catch {
            await bumpAttempts(ids: rows.map { $0.id }); logger.warning("drain todos 失败: \(error.localizedDescription)")
        }
    }
    private func drainHabits() async {
        guard let (rows, changes) = await collect("habits", as: HabitChange.self), !changes.isEmpty else { return }
        do {
            let results: [BatchResult<HabitDefinitionDTO>] = try await api.request(Endpoints.habitBatch, body: BatchRequest(changes: changes))
            await reconcile(rows, results) { await self.applyHabit($0) }
        } catch {
            await bumpAttempts(ids: rows.map { $0.id }); logger.warning("drain habits 失败: \(error.localizedDescription)")
        }
    }
    private func drainCheckins() async {
        guard let (rows, changes) = await collect("habit_checkins", as: CheckinChange.self), !changes.isEmpty else { return }
        do {
            let results: [BatchResult<HabitRecordDTO>] = try await api.request(Endpoints.checkinBatch, body: BatchRequest(changes: changes))
            await reconcile(rows, results) { await self.applyCheckin($0) }
        } catch {
            await bumpAttempts(ids: rows.map { $0.id }); logger.warning("drain checkins 失败: \(error.localizedDescription)")
        }
    }

    /// 取某实体一批待发,payload 解码失败的行整体跳过(保持 rows 与 changes 一一对齐)
    private func collect<C: Decodable>(_ entity: String, as: C.Type) async -> ([SyncOutbox], [C])? {
        guard let db = try? AppDatabase.shared.getDB() else { return nil }
        let rows: [SyncOutbox]
        do { rows = try await db.read { try SyncOutbox.pending($0, entity: entity, limit: batchSize) } }
        catch { return nil }
        var out: [SyncOutbox] = []; var changes: [C] = []
        for r in rows {
            guard let c = try? JSONDecoder.boxs.decode(C.self, from: r.payload) else { continue }
            out.append(r); changes.append(c)
        }
        return (out, changes)
    }

    /// 逐条把服务端返回(胜出版本)写回本地,删除对应 outbox 行
    private func reconcile<D>(_ rows: [SyncOutbox], _ results: [BatchResult<D>], apply: (D) async -> Void) async {
        for (i, row) in rows.enumerated() where i < results.count {
            await apply(results[i].record)        // applied 与 conflict 都采纳服务端版本
            await deleteOutbox(id: row.id)
        }
    }

    private func deleteOutbox(id: Int64?) async {
        guard let id, let db = try? AppDatabase.shared.getDB() else { return }
        _ = try? await db.write { try SyncOutbox.deleteOne($0, key: id) }
    }
    private func bumpAttempts(ids: [Int64?]) async {
        guard let db = try? AppDatabase.shared.getDB() else { return }
        _ = try? await db.write { db in
            for id in ids.compactMap({ $0 }) {
                guard var r = try SyncOutbox.fetchOne(db, key: id) else { continue }
                r.attempts += 1
                if r.attempts >= maxAttempts { r.dead = true }   // 死信:标记而非删除,供 UI 提示
                try r.update(db)
            }
        }
    }

    /// 死信数量(供 UI 展示"有同步失败")
    func deadLetterCount() async -> Int {
        guard let db = try? AppDatabase.shared.getDB() else { return 0 }
        return (try? await db.read { try SyncOutbox.deadCount($0) }) ?? 0
    }

    /// 重试全部死信(清标记,重新进入待发)
    func retryDeadLetters() async {
        guard let db = try? AppDatabase.shared.getDB() else { return }
        _ = try? await db.write { try SyncOutbox.resetDead($0) }
        await sync(force: true)
    }

    // MARK: - apply(同步回写:delete+insert,绕过 willUpdate,保留服务端 updatedAt)

    // 若该记录在本地尚有未推送的 outbox 行(待 drain),跳过——下个周期 drain 会以本地 updated_at 重新裁决,避免瞬时覆盖本地编辑。

    private func applyExpense(_ dto: ExpenseDTO) async {
        if await hasPending("expenses", key: dto.id) { return }
        await replaceLocal(ExpenseMapper.toLocal(dto), id: dto.id)
    }
    private func applyTodo(_ dto: TodoDTO) async {
        if await hasPending("todos", key: dto.id) { return }
        await replaceLocal(TodoMapper.toLocal(dto), id: dto.id)
    }
    private func applyHabit(_ dto: HabitDefinitionDTO) async {
        if await hasPending("habits", key: dto.id) { return }
        await replaceLocal(HabitMapper.toLocal(dto), id: dto.id)
    }
    private func applyCheckin(_ dto: HabitRecordDTO) async {
        let key = "\(dto.habit_id)|\(dto.record_date)"
        if await hasPending("habit_checkins", key: key) { return }
        guard let db = try? AppDatabase.shared.getDB() else { return }
        _ = try? await db.write { db in
            var rec = HabitRecordMapper.toLocal(dto)
            try HabitRecord
                .filter(Column("habitId") == rec.habitId && Column("recordDate") == rec.recordDate)
                .deleteAll(db)
            try rec.insert(db)
        }
    }

    /// 本地是否仍有该记录的待推送变更(未 drain)
    private func hasPending(_ entity: String, key: String) async -> Bool {
        guard let db = try? AppDatabase.shared.getDB() else { return false }
        let n = (try? await db.read { db in
            try SyncOutbox
                .filter(Column("entity") == entity && Column("recordKey") == key)
                .fetchCount(db)
        }) ?? 0
        return n > 0
    }
    /// 按 id 删旧 + insert 服务端记录(insert 不触发 willUpdate,保留 updatedAt)
    private func replaceLocal<T: PersistableRecord & Sendable>(_ rec: T, id: String) async {
        guard let db = try? AppDatabase.shared.getDB() else { return }
        _ = try? await db.write { db in
            try db.execute(sql: "DELETE FROM \(T.databaseTableName) WHERE id = ?", arguments: [id])
            var r = rec; try r.insert(db)
        }
    }

    // MARK: - pull(增量)

    func pullAll() async { await pull(entities: SyncOutbox.allEntities) }

    /// 只拉取指定实体(页面按需调用,减少请求数);drain 始终推送全部 pending
    func pull(entities: [String]) async {
        for e in entities {
            switch e {
            case "expenses": await pullExpenses()
            case "todos": await pullTodos()
            case "habits": await pullHabits()
            case "habit_checkins": await pullCheckins()
            default: break
            }
        }
    }
    private func pullExpenses() async {
        await pullLoop(entity: "expenses", endpoint: { Endpoints.expenseChanges(cursor: $0) }, apply: { await self.applyExpense($0) })
    }
    private func pullHabits() async {
        await pullLoop(entity: "habits", endpoint: { Endpoints.habitChanges(cursor: $0) }, apply: { await self.applyHabit($0) })
    }
    private func pullCheckins() async {
        await pullLoop(entity: "habit_checkins", endpoint: { Endpoints.checkinChanges(cursor: $0) }, apply: { await self.applyCheckin($0) })
    }
    private func pullTodos() async {
        await pullLoop(entity: "todos", endpoint: { Endpoints.todoChanges(cursor: $0) }, apply: { await self.applyTodo($0) })
    }

    /// 翻页拉取直到 next_cursor == nil;每页 upsert 后存新游标
    private func pullLoop<D: Decodable & Sendable>(
        entity: String,
        endpoint: (String?) -> Endpoint,
        apply: (D) async -> Void
    ) async {
        var cursor = await readCursor(entity)
        repeat {
            let resp: ChangesResponse<D>
            do { resp = try await api.request(endpoint(cursor)) }
            catch { logger.warning("pull \(entity) 失败: \(error.localizedDescription)"); return }
            for item in resp.items { await apply(item) }
            cursor = resp.next_cursor
            await writeCursor(entity, cursor)
        } while cursor != nil
    }

    private func readCursor(_ entity: String) async -> String? {
        guard let db = try? AppDatabase.shared.getDB() else { return nil }
        return try? await db.read { try SyncCursor.get($0, entity: entity) }
    }
    private func writeCursor(_ entity: String, _ cursor: String?) async {
        guard let db = try? AppDatabase.shared.getDB() else { return }
        _ = try? await db.write { try SyncCursor.set($0, entity: entity, cursor: cursor) }
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
