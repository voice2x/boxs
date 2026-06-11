import Testing
import Foundation
@testable import Boxs

@Suite("多意图引擎测试")
struct MultiIntentTests {
    let engine = MultiIntentEngine()

    @Test("多意图: 午饭35，打车28 → 2×expense")
    func testTwoExpenses() {
        let result = engine.tryMatch("午饭35，打车28")
        #expect(result != nil)
        #expect(result?.intent == "multiple")
        #expect(result?.items?.count == 2)
    }

    @Test("多意图: 午饭35，跑步5公里 → expense+habit")
    func testExpenseAndHabit() {
        let result = engine.tryMatch("午饭35，跑步5公里")
        #expect(result != nil)
        #expect(result?.items?.count == 2)
        #expect(result?.items?[0].intent == "expense")
        #expect(result?.items?[1].intent == "habit_checkin")
    }

    @Test("单意图不是多意图: 午饭35 → nil")
    func testSingleNotMultiple() {
        let result = engine.tryMatch("午饭35")
        #expect(result == nil)
    }

    @Test("某段失败降级: 午饭35，这个月花了多少 → nil")
    func testPartialFailure() {
        let result = engine.tryMatch("午饭35，这个月花了多少")
        #expect(result == nil)
    }
}
