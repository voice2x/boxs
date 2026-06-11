import SwiftUI

/// 主页 — 唯一根页面
/// 横向概览卡片 + 记录列表 + 悬浮语音按钮
struct MainPage: View {
    @State private var viewModel = HomeViewModel()
    @State private var nluViewModel = NLUViewModel()
    @State private var showConfirmSheet = false
    @State private var inputText = ""
    @State private var showTextInput = false

    @Environment(\.appColors) private var c

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mainContent

                // 悬浮语音按钮
                VStack {
                    Spacer()
                    VoiceButton(
                        onTap: { showTextInput = true },
                        onLongPress: { /* 长按录音 */ }
                    )
                }
            }
            .background(c.background)
            .navigationDestination(for: NavigationRoute.self) { route in
                switch route {
                case .settings:
                    SettingsPage()
                case .expenseStats:
                    ExpenseStatsPage()
                case .todoList:
                    TodoListPage()
                case .habitCalendar:
                    HabitCalendarPage()
                case .recordDetail(let id):
                    RecordDetailPage(recordId: id)
                }
            }
        }
        .overlay {
            HalfSheet(isPresented: $showConfirmSheet) {
                ConfirmSheet(viewModel: nluViewModel)
            }
        }
        .alert("提示", isPresented: .constant(nluViewModel.errorMessage != nil)) {
            Button("确定") { nluViewModel.errorMessage = nil }
        } message: {
            Text(nluViewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showTextInput) {
            textInputSheet
        }
        .task {
            await viewModel.loadData()
        }
    }

    // MARK: - 主内容

    private var mainContent: some View {
        VStack(spacing: 0) {
            // 顶栏
            topBar

            // 概览卡片
            overviewCards

            // 记录列表
            recordList
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Text(topBarDate)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.textPrimary)

            Spacer()

            NavigationLink(value: NavigationRoute.settings) {
                Image(systemName: "gearshape")
                    .font(.system(size: Sz.icon))
                    .foregroundStyle(c.textSecondary)
            }
        }
        .padding(.horizontal, S.page)
        .frame(height: Sz.topBar)
    }

    private var topBarDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d EEEE"
        return formatter.string(from: Date())
    }

    // MARK: - 概览卡片

    private var overviewCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: S.row) {
                // 待办卡片
                NavigationLink(value: NavigationRoute.todoList) {
                    OverviewCard(
                        emoji: "📋",
                        title: "待办",
                        mainValue: "\(viewModel.todayTodoCompleted)/\(viewModel.todayTodoCount)",
                        subtitle: "今日待办",
                        progress: viewModel.todoProgress
                    )
                }
                .buttonStyle(.plain)

                // 账单卡片
                NavigationLink(value: NavigationRoute.expenseStats) {
                    OverviewCard(
                        emoji: "💰",
                        title: "账单",
                        mainValue: viewModel.monthExpenseDisplay,
                        subtitle: "本月支出",
                        progress: nil
                    )
                }
                .buttonStyle(.plain)

                // 打卡卡片
                NavigationLink(value: NavigationRoute.habitCalendar) {
                    OverviewCard(
                        emoji: "🏃",
                        title: "打卡",
                        mainValue: "\(viewModel.todayHabitChecked)/\(viewModel.todayHabitTotal)",
                        subtitle: viewModel.habitEmojiStatus,
                        progress: nil
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, S.page)
        }
        .frame(height: 80 + S.card)
        .padding(.bottom, S.row)
    }

    // MARK: - 记录列表

    private var recordList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.recentRecords) { item in
                    CompactListItem(
                        emoji: item.emoji,
                        title: item.title,
                        subtitle: item.subtitle,
                        trailing: item.trailing,
                        trailingColor: item.trailingColor
                    ) {
                        // 点击进入详情
                    }
                    if item.id != viewModel.recentRecords.last?.id {
                        AppDivider()
                    }
                }
            }
            .padding(.bottom, 60) // 为语音按钮留空间
        }
    }

    // MARK: - 文字输入弹窗

    private var textInputSheet: some View {
        VStack(spacing: S.section) {
            Text("输入记录")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.textPrimary)

            TextField("例如：午饭35", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15))
                .padding(.horizontal, S.page)

            HStack {
                Button("取消") {
                    showTextInput = false
                    inputText = ""
                }
                .buttonStyle(ActionButtonStyle(kind: .secondary))

                Spacer()

                Button("识别") {
                    Task {
                        await nluViewModel.processText(inputText)
                        showTextInput = false
                        inputText = ""
                        showConfirmSheet = true
                    }
                }
                .buttonStyle(ActionButtonStyle(kind: .primary))
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, S.page)
            .padding(.bottom, 20)
        }
        .padding(.top, 20)
        .presentationDetents([.medium])
    }
}

// MARK: - 导航路由

enum NavigationRoute: Hashable {
    case settings
    case expenseStats
    case todoList
    case habitCalendar
    case recordDetail(String)
}
