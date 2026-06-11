import Foundation
import Observation
import GRDB
import os.log

/// NLU 处理状态管理
@Observable
@MainActor
final class NLUViewModel {
    // MARK: - 状态
    var isProcessing = false
    var recognizedText: String?
    var nluResult: NLUResult?
    var errorMessage: String?
    var showConfirmSheet = false

    // MARK: - 依赖
    private let orchestrator = NLUOrchestrator()
    private let logger = Logger(subsystem: "com.boxs.app", category: "NLUViewModel")

    // MARK: - 处理文字输入

    func processText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        logger.info("processText 开始: \"\(trimmed)\"")
        isProcessing = true
        errorMessage = nil
        recognizedText = trimmed

        do {
            let result = try await orchestrator.process(trimmed)
            logger.info("processText 成功: intent=\(result.intent), confidence=\(result.confidence), source=\(result.source)")
            self.nluResult = result
            self.showConfirmSheet = true
        } catch {
            logger.error("processText 失败: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
        self.isProcessing = false
    }

    // MARK: - 处理语音识别结果

    func processSTTResult(_ text: String) async {
        guard !text.isEmpty else {
            errorMessage = "语音识别结果为空"
            return
        }
        await processText(text)
    }

    // MARK: - 确认保存

    func confirmAndSave() async {
        guard let result = nluResult else {
            logger.warning("confirmAndSave: nluResult 为 nil，跳过")
            return
        }

        logger.info("confirmAndSave 开始: intent=\(result.intent)")

        do {
            let db = try AppDatabase.shared.getDB()
            logger.info("confirmAndSave: 数据库连接成功")

            switch result.intent {
            case "expense":
                logger.info("confirmAndSave: 保存记账 amount=\(result.amount ?? 0), category=\(result.category ?? "nil"), note=\(result.note ?? "nil")")
                try await saveExpense(result, db: db)
                logger.info("confirmAndSave: 记账保存成功")
            case "habit_checkin":
                logger.info("confirmAndSave: 保存打卡 habit=\(result.habitName ?? "nil")")
                try await saveHabitCheckin(result, db: db)
                logger.info("confirmAndSave: 打卡保存成功")
            case "todo_add":
                logger.info("confirmAndSave: 保存待办 content=\(result.content ?? "nil")")
                try await saveTodo(result, db: db)
                logger.info("confirmAndSave: 待办保存成功")
            case "multiple":
                let count = result.items?.count ?? 0
                logger.info("confirmAndSave: 多意图保存, \(count) 条")
                if let items = result.items {
                    for (index, item) in items.enumerated() {
                        logger.info("confirmAndSave: 多意图[\(index)] intent=\(item.intent)")
                        switch item.intent {
                        case "expense": try await saveExpense(item, db: db)
                        case "habit_checkin": try await saveHabitCheckin(item, db: db)
                        case "todo_add": try await saveTodo(item, db: db)
                        default: break
                        }
                    }
                }
                logger.info("confirmAndSave: 多意图全部保存成功")
            default:
                logger.warning("confirmAndSave: 未知 intent=\(result.intent)，跳过保存")
            }

            showConfirmSheet = false
            nluResult = nil
            recognizedText = nil
            logger.info("confirmAndSave: 完成，关闭弹窗")
        } catch {
            logger.error("confirmAndSave 保存失败: \(error)")
            errorMessage = "保存失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 保存方法

    private func saveExpense(_ result: NLUResult, db: DatabaseQueue) async throws {
        let amountCents = Int((result.amount ?? 0) * 100)
        let record = ExpenseRecord.create(
            type: "expense",
            amountCents: max(amountCents, 0),
            category: result.category ?? "其他",
            note: result.note,
            merchant: result.merchant,
            source: "text"
        )
        logger.debug("saveExpense: id=\(record.id), amountCents=\(record.amountCents), category=\(record.category)")
        try await db.write { db in
            try record.insert(db)
        }
    }

    private func saveHabitCheckin(_ result: NLUResult, db: DatabaseQueue) async throws {
        let habitName = result.habitName ?? ""
        let habit = try await db.read { db in
            try HabitDefinition
                .filter(Column("name") == habitName)
                .fetchOne(db)
        }

        if let habit {
            let record = HabitRecord.create(habitId: habit.id, value: result.habitValue)
            logger.debug("saveHabitCheckin: habitId=\(record.habitId), value=\(record.value ?? "nil")")
            try await db.write { db in
                try record.insert(db)
            }
        } else {
            logger.warning("saveHabitCheckin: 未找到习惯定义 name=\(habitName)")
        }
    }

    private func saveTodo(_ result: NLUResult, db: DatabaseQueue) async throws {
        let record = TodoRecord.create(content: result.content ?? "")
        logger.debug("saveTodo: id=\(record.id), content=\(record.content)")
        try await db.write { db in
            try record.insert(db)
        }
    }

    // MARK: - 取消

    func dismiss() {
        showConfirmSheet = false
        nluResult = nil
        recognizedText = nil
        errorMessage = nil
    }
}
