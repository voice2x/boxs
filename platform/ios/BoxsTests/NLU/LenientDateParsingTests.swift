import Testing
import Foundation
@testable import Boxs

@Suite("remind_at 容错解析测试")
struct LenientDateParsingTests {

    @Test("ISO8601 含/不含毫秒可解析")
    func iso8601() {
        #expect(LenientDateParser.parse("2026-06-16T09:00:00Z") != nil)
        #expect(LenientDateParser.parse("2026-06-16T09:00:00.123Z") != nil)
    }

    @Test("常见绝对格式可解析")
    func absoluteFormats() {
        #expect(LenientDateParser.parse("2026-06-16 09:00") != nil)
        #expect(LenientDateParser.parse("2026-06-16 09:00:00") != nil)
        #expect(LenientDateParser.parse("2026/06/16") != nil)
    }

    @Test("相对/中文表述与空值返回 nil")
    func unparsable() {
        #expect(LenientDateParser.parse("明天上午9点") == nil)
        #expect(LenientDateParser.parse("随便一串") == nil)
        #expect(LenientDateParser.parse("") == nil)
        #expect(LenientDateParser.parse(nil) == nil)
    }

    @Test("坏 remind_at 不应拖垮整条响应解码")
    func malformedRemindAtDoesNotBreakDecode() throws {
        // remind_at 是非 ISO8601 字符串；过去会让整条 NLUClassifyResponse 解码失败、
        // 整条意图回退成 unknown。容错后应解码成功，坏值降级为 nil。
        let json = """
        {
          "intent": "todo_add",
          "confidence": 0.9,
          "amount": null,
          "category": null,
          "note": null,
          "merchant": null,
          "habit_name": null,
          "habit_value": null,
          "content": "买牛奶",
          "remind_at": "明天上午9点",
          "reply": null,
          "items": null
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder.boxs.decode(NLUClassifyResponse.self, from: json)
        #expect(resp.intent == "todo_add")
        #expect(resp.content == "买牛奶")
        #expect(resp.remind_at == nil)
    }

    @Test("正常 ISO8601 remind_at 可解析回 Date")
    func validRemindAtParses() throws {
        let json = """
        {
          "intent": "todo_add", "confidence": 0.9,
          "amount": null, "category": null, "note": null, "merchant": null,
          "habit_name": null, "habit_value": null, "content": "开会",
          "remind_at": "2026-06-16T09:00:00Z", "reply": null, "items": null
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder.boxs.decode(NLUClassifyResponse.self, from: json)
        #expect(resp.remind_at != nil)
    }
}

@Suite("数值字段 amount/confidence 容错解码测试")
struct NumberLeniencyTests {

    @Test("amount 为字符串可转成数字")
    func amountStringParses() throws {
        let json = """
        { "intent": "expense", "confidence": 0.9,
          "amount": "35.5", "category": "餐饮", "note": "午饭",
          "merchant": null, "habit_name": null, "habit_value": null,
          "content": null, "remind_at": null, "reply": null, "items": null }
        """.data(using: .utf8)!
        let resp = try JSONDecoder.boxs.decode(NLUClassifyResponse.self, from: json)
        #expect(resp.amount == 35.5)
        #expect(resp.category == "餐饮")
    }

    @Test("confidence 为字符串可转成数字")
    func confidenceStringParses() throws {
        let json = """
        { "intent": "expense", "confidence": "0.9",
          "amount": 35, "category": null, "note": null,
          "merchant": null, "habit_name": null, "habit_value": null,
          "content": null, "remind_at": null, "reply": null, "items": null }
        """.data(using: .utf8)!
        let resp = try JSONDecoder.boxs.decode(NLUClassifyResponse.self, from: json)
        #expect(resp.confidence == 0.9)
    }

    @Test("amount/confidence 同时为字符串仍正常解码，不回退 unknown")
    func stringNumbersDoNotBreakDecode() throws {
        let json = """
        { "intent": "expense", "confidence": "0.85",
          "amount": "35", "category": "餐饮", "note": "午饭",
          "merchant": null, "habit_name": null, "habit_value": null,
          "content": null, "remind_at": null, "reply": null, "items": null }
        """.data(using: .utf8)!
        let resp = try JSONDecoder.boxs.decode(NLUClassifyResponse.self, from: json)
        #expect(resp.intent == "expense")
        #expect(resp.amount == 35.0)
        #expect(resp.confidence == 0.85)
        #expect(resp.category == "餐饮")
    }

    @Test("amount 缺省/为 null/非数字均返回 nil")
    func invalidAmountIsNil() throws {
        let nullJSON = """
        { "intent": "expense", "confidence": 0.9,
          "amount": null, "category": null, "note": null, "merchant": null,
          "habit_name": null, "habit_value": null, "content": null,
          "remind_at": null, "reply": null, "items": null }
        """.data(using: .utf8)!
        #expect(try JSONDecoder.boxs.decode(NLUClassifyResponse.self, from: nullJSON).amount == nil)

        let nonNumericJSON = """
        { "intent": "expense", "confidence": 0.9,
          "amount": "免费", "category": null, "note": null, "merchant": null,
          "habit_name": null, "habit_value": null, "content": null,
          "remind_at": null, "reply": null, "items": null }
        """.data(using: .utf8)!
        #expect(try JSONDecoder.boxs.decode(NLUClassifyResponse.self, from: nonNumericJSON).amount == nil)
    }
}
