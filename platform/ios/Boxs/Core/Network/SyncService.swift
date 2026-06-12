import Foundation
import GRDB
import os.log

/// 同步服务 — 本地 SQLite 与后端 API 的双向同步
/// Push: 本地保存后 fire-and-forget 到后端
/// Pull: 从后端拉取数据 upsert 到本地 GRDB
actor SyncService {
    static let shared = SyncService()

    private let api = APIClient.shared
    private let logger = Logger(subsystem: "com.boxs.app", category: "Sync")

    private init() {}

    // MARK: - Pull (后端 → 本地)

    /// 同步所有数据
    func syncAll() async {
        logger.info("syncAll 开始")
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.syncExpenses() }
            group.addTask { await self.syncHabits() }
            group.addTask { await self.syncTodos() }
        }
        logger.info("syncAll 完成")
    }

    /// 拉取记账数据并 upsert 到本地
    func syncExpenses(month: String? = nil) async {
        do {
            let currentMonth = month ?? Self.currentMonth()
            let endpoint = Endpoint(
                method: .GET,
                path: "/api/data/expenses",
                queryItems: [URLQueryItem(name: "month", value: currentMonth)],
                requiresAuth: true
            )
            let response: ExpenseListDTO = try await api.request(endpoint)
            let db = try AppDatabase.shared.getDB()

            try await db.write { db in
                for dto in response.items {
                    var record = ExpenseMapper.toLocal(dto)
                    try record.save(db)
                }
            }
            logger.info("syncExpenses 完成: \(response.items.count) 条")
        } catch {
            logger.warning("syncExpenses 失败: \(error.localizedDescription)")
        }
    }

    /// 拉取记账统计（直接使用后端数据，不走本地聚合）
    func getExpenseStats(month: String? = nil) async -> ExpenseStatsDTO? {
        do {
            let currentMonth = month ?? Self.currentMonth()
            let endpoint = Endpoint(
                method: .GET,
                path: "/api/data/expenses/stats",
                queryItems: [URLQueryItem(name: "month", value: currentMonth)],
                requiresAuth: true
            )
            return try await api.request(endpoint)
        } catch {
            logger.warning("getExpenseStats 失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 拉取习惯定义并 upsert 到本地
    func syncHabits() async {
        do {
            let endpoint = Endpoint(
                method: .GET,
                path: "/api/data/habits",
                requiresAuth: true
            )
            let dtos: [HabitDefinitionDTO] = try await api.request(endpoint)
            let db = try AppDatabase.shared.getDB()

            try await db.write { db in
                for dto in dtos {
                    var record = HabitMapper.toLocal(dto)
                    try record.save(db)
                }
            }
            logger.info("syncHabits 完成: \(dtos.count) 条")
        } catch {
            logger.warning("syncHabits 失败: \(error.localizedDescription)")
        }
    }

    /// 拉取待办数据并 upsert 到本地
    func syncTodos(status: String? = "pending") async {
        do {
            var queryItems: [URLQueryItem]? = nil
            if let status {
                queryItems = [URLQueryItem(name: "status", value: status)]
            }
            let endpoint = Endpoint(
                method: .GET,
                path: "/api/data/todos",
                queryItems: queryItems,
                requiresAuth: true
            )
            let dtos: [TodoDTO] = try await api.request(endpoint)
            let db = try AppDatabase.shared.getDB()

            try await db.write { db in
                for dto in dtos {
                    var record = TodoMapper.toLocal(dto)
                    try record.save(db)
                }
            }
            logger.info("syncTodos 完成: \(dtos.count) 条")
        } catch {
            logger.warning("syncTodos 失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Push (本地 → 后端)

    /// 推送记账到后端，返回后端创建的完整记录（含服务端 ID）
    @discardableResult
    func pushExpense(_ local: ExpenseRecord) async -> ExpenseRecord? {
        do {
            let body = ExpenseMapper.toCreateDTO(local)
            let endpoint = Endpoint(method: .POST, path: "/api/data/expenses", requiresAuth: true)
            let dto: ExpenseDTO = try await api.request(endpoint, body: body)

            // 用后端返回的 ID 更新本地记录
            let serverRecord = ExpenseMapper.toLocal(dto)
            let db = try AppDatabase.shared.getDB()
            try await db.write { db in
                // 删除本地旧 ID 记录，插入服务端记录
                try ExpenseRecord.deleteOne(db, key: local.id)
                var newRecord = serverRecord
                try newRecord.insert(db)
            }
            logger.info("pushExpense 成功: \(dto.id)")
            return serverRecord
        } catch {
            logger.warning("pushExpense 失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 推送习惯定义到后端
    @discardableResult
    func pushHabit(_ local: HabitDefinition) async -> HabitDefinition? {
        do {
            let body = HabitMapper.toCreateDTO(local)
            let endpoint = Endpoint(method: .POST, path: "/api/data/habits", requiresAuth: true)
            let dto: HabitDefinitionDTO = try await api.request(endpoint, body: body)

            let serverRecord = HabitMapper.toLocal(dto)
            let db = try AppDatabase.shared.getDB()
            try await db.write { db in
                try HabitDefinition.deleteOne(db, key: local.id)
                var newRecord = serverRecord
                try newRecord.insert(db)
            }
            logger.info("pushHabit 成功: \(dto.id)")
            return serverRecord
        } catch {
            logger.warning("pushHabit 失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 推送习惯打卡到后端
    func pushHabitCheckin(_ local: HabitRecord) async {
        do {
            let body = HabitRecordMapper.toCheckinDTO(local)
            let endpoint = Endpoint(method: .POST, path: "/api/data/habits/checkin", requiresAuth: true)
            let dto: HabitRecordDTO = try await api.request(endpoint, body: body)

            let serverRecord = HabitRecordMapper.toLocal(dto)
            let db = try AppDatabase.shared.getDB()
            try await db.write { db in
                try HabitRecord.deleteOne(db, key: local.id)
                var newRecord = serverRecord
                try newRecord.insert(db)
            }
            logger.info("pushHabitCheckin 成功")
        } catch {
            logger.warning("pushHabitCheckin 失败: \(error.localizedDescription)")
        }
    }

    /// 推送待办到后端
    @discardableResult
    func pushTodo(_ local: TodoRecord) async -> TodoRecord? {
        do {
            let body = TodoMapper.toCreateDTO(local)
            let endpoint = Endpoint(method: .POST, path: "/api/data/todos", requiresAuth: true)
            let dto: TodoDTO = try await api.request(endpoint, body: body)

            let serverRecord = TodoMapper.toLocal(dto)
            let db = try AppDatabase.shared.getDB()
            try await db.write { db in
                try TodoRecord.deleteOne(db, key: local.id)
                var newRecord = serverRecord
                try newRecord.insert(db)
            }
            logger.info("pushTodo 成功: \(dto.id)")
            return serverRecord
        } catch {
            logger.warning("pushTodo 失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 通知后端完成待办
    func pushTodoComplete(id: String) async {
        do {
            let endpoint = Endpoint(method: .POST, path: "/api/data/todos/\(id)/complete", requiresAuth: true)
            let _: TodoDTO = try await api.request(endpoint)
            logger.info("pushTodoComplete 成功: \(id)")
        } catch {
            logger.warning("pushTodoComplete 失败: \(error.localizedDescription)")
        }
    }

    /// 通知后端删除记账（软删除）
    func pushExpenseDelete(id: String) async {
        do {
            let endpoint = Endpoint(method: .DELETE, path: "/api/data/expenses/\(id)", requiresAuth: true)
            let _: EmptyResponse = try await api.request(endpoint)
            logger.info("pushExpenseDelete 成功: \(id)")
        } catch {
            logger.warning("pushExpenseDelete 失败: \(error.localizedDescription)")
        }
    }

    /// 通知后端删除待办（软删除）
    func pushTodoDelete(id: String) async {
        do {
            let endpoint = Endpoint(method: .DELETE, path: "/api/data/todos/\(id)", requiresAuth: true)
            let _: EmptyResponse = try await api.request(endpoint)
            logger.info("pushTodoDelete 成功: \(id)")
        } catch {
            logger.warning("pushTodoDelete 失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 工具

    private static func currentMonth() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }
}

/// 空响应（用于 DELETE 等返回 {"success": true} 的接口）
private struct EmptyResponse: Decodable {}
