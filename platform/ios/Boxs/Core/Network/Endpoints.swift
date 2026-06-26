import Foundation

/// API 路径常量
enum Endpoints {
    // MARK: - Auth
    static let register = Endpoint(method: .POST, path: "/api/auth/register", requiresAuth: false)
    static let login = Endpoint(method: .POST, path: "/api/auth/login", requiresAuth: false)
    static let refresh = Endpoint(method: .POST, path: "/api/auth/refresh", requiresAuth: false)
    static let logout = Endpoint(method: .POST, path: "/api/auth/logout")
    static let me = Endpoint(method: .GET, path: "/api/auth/me")
    static let changePassword = Endpoint(method: .POST, path: "/api/auth/change-password")

    // MARK: - NLU
    static func classify(body: NLUPayload) -> Endpoint {
        Endpoint(method: .POST, path: "/api/nlu/classify")
    }
    static let query = Endpoint(method: .POST, path: "/api/nlu/query")
    static let correct = Endpoint(method: .POST, path: "/api/nlu/correct")

    // MARK: - Expenses
    static let expenses = Endpoint(method: .GET, path: "/api/data/expenses")
    static let createExpense = Endpoint(method: .POST, path: "/api/data/expenses")
    static func updateExpense(id: String) -> Endpoint {
        Endpoint(method: .PUT, path: "/api/data/expenses/\(id)")
    }
    static func deleteExpense(id: String) -> Endpoint {
        Endpoint(method: .DELETE, path: "/api/data/expenses/\(id)")
    }
    static let expenseStats = Endpoint(method: .GET, path: "/api/data/expenses/stats")

    // MARK: - Habits
    static let habits = Endpoint(method: .GET, path: "/api/data/habits")
    static let createHabit = Endpoint(method: .POST, path: "/api/data/habits")
    static func updateHabit(id: String) -> Endpoint {
        Endpoint(method: .PUT, path: "/api/data/habits/\(id)")
    }
    static func deleteHabit(id: String) -> Endpoint {
        Endpoint(method: .DELETE, path: "/api/data/habits/\(id)")
    }
    static let habitCheckin = Endpoint(method: .POST, path: "/api/data/habits/checkin")
    static let habitCalendar = Endpoint(method: .GET, path: "/api/data/habits/calendar")

    // MARK: - Todos
    static let todos = Endpoint(method: .GET, path: "/api/data/todos")
    static let createTodo = Endpoint(method: .POST, path: "/api/data/todos")
    static func updateTodo(id: String) -> Endpoint {
        Endpoint(method: .PUT, path: "/api/data/todos/\(id)")
    }
    static func deleteTodo(id: String) -> Endpoint {
        Endpoint(method: .DELETE, path: "/api/data/todos/\(id)")
    }
    static func completeTodo(id: String) -> Endpoint {
        Endpoint(method: .POST, path: "/api/data/todos/\(id)/complete")
    }
}

/// NLU 请求体
struct NLUPayload: Encodable {
    let text: String
}

/// App 全局配置
enum AppConfiguration {
    #if DEBUG
    static let apiBaseURL = "http://boxs.voice2x.com"
    #else
    static let apiBaseURL = "https://api.boxs.app"
    #endif

    static let sttWebSocketURL: String = {
        #if DEBUG
        return "ws://boxs.voice2x.com/ws/stt"
        #else
        return "wss://api.boxs.app/ws/stt"
        #endif
    }()
}
