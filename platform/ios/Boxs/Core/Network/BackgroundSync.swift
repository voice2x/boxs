import Foundation
import Network
import BackgroundTasks

/// 联网即触发 drain + 周期后台同步
final class BackgroundSync: @unchecked Sendable {
    static let shared = BackgroundSync()
    static let bgTaskIdentifier = "com.boxs.app.sync"
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.boxs.app.network")
    private init() {}

    func register() {
        startNetworkMonitor()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundSync.bgTaskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(task)
        }
    }

    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { await SyncEngine.shared.sync() }
        }
        monitor.start(queue: queue)
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundSync.bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 15)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        scheduleAppRefresh()
        let op = Task { await SyncEngine.shared.sync() }
        let box = SendableBox(value: task)
        task.expirationHandler = { op.cancel() }
        Task {
            _ = await op.value
            box.value.setTaskCompleted(success: true)
        }
    }
}

/// 包装非 Sendable 值供 @Sendable 闭包捕获(BGTask 非 Sendable)
private struct SendableBox<T>: @unchecked Sendable { let value: T }
