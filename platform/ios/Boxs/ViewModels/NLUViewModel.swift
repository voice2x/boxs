import Foundation
import Observation
import GRDB

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

    // MARK: - 处理文字输入

    func processText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isProcessing = true
        errorMessage = nil
        recognizedText = trimmed

        do {
            let result = try await orchestrator.process(trimmed)
            self.nluResult = result
            self.showConfirmSheet = true
        } catch {
            print("[NLUViewModel] processText 失败: \(error)")
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
        guard let result = nluResult else { return }

        do {
            let db = try AppDatabase.shared.getDB()

            switch result.intent {
            case "expense":
                try await saveExpense(result, db: db)
            case "habit_checkin":
                try await saveHabitCheckin(result, db: db)
            case "todo_add":
                try await saveTodo(result, db: db)
            case "multiple":
                if let items = result.items {
                    for item in items {
                        switch item.intent {
                        case "expense": try await saveExpense(item, db: db)
                        case "habit_checkin": try await saveHabitCheckin(item, db: db)
                        case "todo_add": try await saveTodo(item, db: db)
                        default: break
                        }
                    }
                }
            default:
                break
            }

            showConfirmSheet = false
            nluResult = nil
            recognizedText = nil
        } catch {
            print("[NLUViewModel] confirmAndSave 保存失败: \(error)")
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
            try await db.write { db in
                try record.insert(db)
            }
        }
    }

    private func saveTodo(_ result: NLUResult, db: DatabaseQueue) async throws {
        let record = TodoRecord.create(content: result.content ?? "")
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
