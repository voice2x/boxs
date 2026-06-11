import Testing
import Foundation
@testable import Boxs

@Suite("规则引擎测试")
struct RuleEngineTests {
    let engine = SingleIntentRuleEngine()

    // MARK: - 纯金额

    @Test("纯金额匹配: 35 → expense")
    func testPureAmount() {
        let result = engine.tryMatch("35")
        #expect(result != nil)
        #expect(result?.intent == "expense")
        #expect(result?.amount == 35.0)
        #expect(result?.confidence ?? 0 >= 0.85)
    }

    @Test("纯金额匹配: 35块 → expense")
    func testPureAmountWithUnit() {
        let result = engine.tryMatch("35块")
        #expect(result != nil)
        #expect(result?.intent == "expense")
        #expect(result?.amount == 35.0)
    }

    @Test("纯金额匹配: 35.5元 → expense")
    func testPureAmountDecimal() {
        let result = engine.tryMatch("35.5元")
        #expect(result != nil)
        #expect(result?.amount == 35.5)
    }

    // MARK: - 金额 + 备注

    @Test("金额+备注: 午饭35 → expense + note")
    func testAmountWithNote() {
        let result = engine.tryMatch("午饭35")
        #expect(result != nil)
        #expect(result?.intent == "expense")
        #expect(result?.amount == 35.0)
        #expect(result?.note == "午饭")
        #expect(result?.category == "餐饮")
    }

    @Test("金额+备注: 打车28块 → expense + 交通分类")
    func testAmountWithNoteTransport() {
        let result = engine.tryMatch("打车28块")
        #expect(result != nil)
        #expect(result?.amount == 28.0)
        #expect(result?.category == "交通")
    }

    // MARK: - 打卡

    @Test("打卡关键词: 跑步打卡 → habit_checkin")
    func testCheckinKeyword() {
        let result = engine.tryMatch("跑步打卡")
        #expect(result != nil)
        #expect(result?.intent == "habit_checkin")
        #expect(result?.habitName == "跑步")
    }

    @Test("打卡关键词: 喝水 → habit_checkin")
    func testCheckinDrinkWater() {
        let result = engine.tryMatch("喝水")
        #expect(result != nil)
        #expect(result?.intent == "habit_checkin")
    }

    // MARK: - 待办

    @Test("待办关键词: 记得买牛奶 → todo_add")
    func testTodoKeyword() {
        let result = engine.tryMatch("记得买牛奶")
        #expect(result != nil)
        #expect(result?.intent == "todo_add")
        #expect(result?.content == "买牛奶")
    }

    // MARK: - 未命中

    @Test("复杂输入不匹配: 这个月花了多少")
    func testComplexInputReturnsNil() {
        let result = engine.tryMatch("这个月花了多少")
        #expect(result == nil)
    }

    @Test("查询类不匹配: 上周的餐饮花了多少钱")
    func testQueryInputReturnsNil() {
        let result = engine.tryMatch("上周的餐饮花了多少钱")
        #expect(result == nil)
    }

    @Test("修改操作不匹配: 把上一条改成40")
    func testModifyInputReturnsNil() {
        let result = engine.tryMatch("把上一条改成40")
        #expect(result == nil)
    }
}
