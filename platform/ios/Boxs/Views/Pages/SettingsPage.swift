import SwiftUI

/// 设置页
struct SettingsPage: View {
    @State private var authViewModel = AuthViewModel()
    @State private var showLoginSheet = false
    @State private var syncFailures = 0
    @State private var pendingCount = 0
    @AppStorage("isDarkMode") private var isDarkMode = false

    @Environment(\.appColors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 用户区域
            userSection

            if syncFailures > 0 {
                AppDivider()
                deadLetterBanner
            } else if pendingCount > 0 {
                AppDivider()
                pendingBanner
            }

            AppDivider()

            // 设置列表
            settingsList

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.background)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            syncFailures = await SyncEngine.shared.deadLetterCount()
            pendingCount = await SyncEngine.shared.pendingCount()
        }
        .sheet(isPresented: $showLoginSheet) {
            loginSheet
        }
    }

    // MARK: - 用户区域

    private var userSection: some View {
        VStack(spacing: 8) {
            if authViewModel.isLoggedIn {
                HStack {
                    Circle()
                        .fill(c.primary.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(c.primary)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已登录")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(c.textPrimary)
                        Text("免费版")
                            .font(.system(size: 12))
                            .foregroundStyle(c.textSecondary)
                    }
                    Spacer()
                    Button("退出") {
                        authViewModel.logout()
                    }
                    .buttonStyle(ActionButtonStyle(kind: .secondary))
                }
            } else {
                Button(action: { showLoginSheet = true }) {
                    HStack {
                        Image(systemName: "person.circle")
                            .font(.system(size: 20))
                        Text("登录 / 注册")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(c.primary)
                }
            }
        }
        .padding(S.page)
    }

    // MARK: - 死信提示

    private var deadLetterBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(c.expense)
            Text("\(syncFailures) 条数据同步失败")
                .font(.system(size: 13))
                .foregroundStyle(c.textPrimary)
            Spacer()
            Button("重试") {
                Task {
                    await SyncEngine.shared.retryDeadLetters()
                    syncFailures = await SyncEngine.shared.deadLetterCount()
                }
            }
            .buttonStyle(ActionButtonStyle(kind: .secondary))
        }
        .padding(S.page)
    }

    private var pendingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(c.textSecondary)
            Text("\(pendingCount) 条数据排队待发")
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
            Spacer()
        }
        .padding(S.page)
    }

    // MARK: - 设置列表

    private var settingsList: some View {
        VStack(spacing: 0) {
            // 暗色模式
            settingRow(icon: "moon.fill", title: "暗色模式") {
                Toggle("", isOn: $isDarkMode)
                    .labelsHidden()
            }

            AppDivider()

            // 关于
            settingRow(icon: "info.circle", title: "关于 Boxs") {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(c.textHint)
            }

            AppDivider()

            // 版本
            settingRow(icon: "number", title: "版本") {
                Text("1.0.0")
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)
            }
        }
        .padding(.horizontal, S.page)
    }

    private func settingRow<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: Sz.icon))
                .foregroundStyle(c.textSecondary)
                .frame(width: Sz.emoji)
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(c.textPrimary)
            Spacer()
            trailing()
        }
        .frame(height: Sz.listItem)
    }

    // MARK: - 登录弹窗

    private var loginSheet: some View {
        VStack(spacing: S.section) {
            Text("登录 Boxs")
                .font(.system(size: 18, weight: .semibold))

            TextField("邮箱", text: $authViewModel.email)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)

            SecureField("密码", text: $authViewModel.password)
                .textFieldStyle(.roundedBorder)

            if let error = authViewModel.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(c.expense)
            }

            HStack(spacing: S.row) {
                Button("注册") {
                    Task { await authViewModel.register() }
                }
                .buttonStyle(ActionButtonStyle(kind: .secondary))

                Button("登录") {
                    Task { await authViewModel.login() }
                }
                .buttonStyle(ActionButtonStyle(kind: .primary))
            }

            Spacer()
        }
        .padding(S.page)
        .presentationDetents([.medium])
    }
}
