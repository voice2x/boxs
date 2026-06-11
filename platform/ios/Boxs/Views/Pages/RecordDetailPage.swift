import SwiftUI

/// 记录详情页
struct RecordDetailPage: View {
    let recordId: String

    @State private var record: ExpenseRecord?
    @State private var showDeleteConfirm = false

    @Environment(\.appColors) private var c
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if let record {
                recordContent(record)
            } else {
                loadingView
            }
        }
        .background(c.background)
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadRecord()
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteRecord() }
        }
    }

    // MARK: - 内容

    private func recordContent(_ record: ExpenseRecord) -> some View {
        VStack(spacing: 0) {
            // 金额
            VStack(spacing: 4) {
                Text(record.signedDisplayAmount)
                    .font(.system(size: 36, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(record.type == "expense" ? c.expense : c.income)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)

            AppDivider()

            // 详情
            VStack(spacing: 0) {
                detailRow(label: "分类", value: "\(ExpenseCategory(rawValue: record.category)?.emoji ?? "📦") \(record.category)")
                detailRow(label: "日期", value: dateFormatter.string(from: record.recordDate))
                if let merchant = record.merchant {
                    detailRow(label: "商家", value: merchant)
                }
                detailRow(label: "来源", value: sourceDisplay(record.source))
                if let note = record.note {
                    detailRow(label: "备注", value: note)
                }

                // 创建时间
                detailRow(label: "创建", value: timeFormatter.string(from: record.createdAt))
            }
            .padding(.horizontal, S.page)

            Spacer()

            // 操作按钮
            HStack(spacing: S.row) {
                Button(action: { /* 编辑 */ }) {
                    Text("编辑")
                }
                .buttonStyle(ActionButtonStyle(kind: .secondary))

                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                    Text("删除")
                }
                .buttonStyle(ActionButtonStyle(kind: .secondary))
            }
            .padding(S.page)
            .padding(.bottom, 20)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(c.textPrimary)
            Spacer()
        }
        .frame(height: Sz.compactRow)
    }

    // MARK: - 空状态

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    // MARK: - 数据操作

    private func loadRecord() {
        do {
            let db = try AppDatabase.shared.getDB()
            record = try db.read { db in
                try ExpenseRecord.fetchOne(db, key: recordId)
            }
        } catch {
            print("加载记录失败: \(error)")
        }
    }

    private func deleteRecord() {
        do {
            let db = try AppDatabase.shared.getDB()
            try db.write { db in
                if var rec = try ExpenseRecord.fetchOne(db, key: recordId) {
                    rec.isDeleted = true
                    rec.deletedAt = Date()
                    try rec.save(db)
                }
            }
            dismiss()
        } catch {
            print("删除记录失败: \(error)")
        }
    }

    private func sourceDisplay(_ source: String) -> String {
        switch source {
        case "voice": return "🎤 语音"
        case "text": return "✏️ 文字"
        case "ocr": return "📷 拍照"
        default: return source
        }
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }
}
