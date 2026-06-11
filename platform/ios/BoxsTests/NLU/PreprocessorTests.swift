import Testing
import Foundation
@testable import Boxs

@Suite("预处理器测试")
struct PreprocessorTests {
    let preprocessor = Preprocessor()

    @Test("去除前后噪音字符")
    func testNoiseRemoval() {
        let result = preprocessor.process("啊午饭35呢")
        #expect(result.contains("午"))
    }

    @Test("合并多余空格")
    func testWhitespace() {
        let result = preprocessor.process("午饭  35")
        #expect(!result.contains("  "))
    }

    @Test("空字符串处理")
    func testEmpty() {
        let result = preprocessor.process("")
        #expect(result.isEmpty)
    }
}
