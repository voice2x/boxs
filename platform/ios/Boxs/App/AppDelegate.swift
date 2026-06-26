import SwiftUI

/// AppDelegate — 处理应用生命周期事件
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 初始化数据库
        do {
            try AppDatabase.shared.setup()
        } catch {
            assertionFailure("数据库初始化失败: \(error)")
        }

        // 已登录时触发初始同步
        if TokenManager.shared.isLoggedIn {
            Task {
                await SyncEngine.shared.sync()
            }
        }
        BackgroundSync.shared.register()

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundSync.shared.scheduleAppRefresh()
    }
}
