import Testing
import Foundation
@testable import Boxs

@Suite("分句切割器测试")
struct SentenceSplitterTests {
    let splitter = SentenceSplitter()

    @Test("逗号分隔: 午饭35，打车28 → 2段")
    func testCommaSplit() {
        let segments = splitter.split("午饭35，打车28")
        #expect(segments.count == 2)
        #expect(segments[0] == "午饭35")
        #expect(segments[1] == "打车28")
    }

    @Test("然后分隔: 午饭35然后打车28 → 2段")
    func testThenSplit() {
        let segments = splitter.split("午饭35然后打车28")
        #expect(segments.count == 2)
    }

    @Test("还有分隔: 午饭35还有打车28 → 2段")
    func testAlsoSplit() {
        let segments = splitter.split("午饭35还有打车28")
        #expect(segments.count == 2)
    }

    @Test("单段不切割: 午饭35 → 1段")
    func testSingleSegment() {
        let segments = splitter.split("午饭35")
        #expect(segments.count == 1)
    }

    @Test("模式边界切割: 午饭35打车28 → 2段")
    func testPatternBoundary() {
        let segments = splitter.split("午饭35打车28")
        #expect(segments.count == 2)
    }

    @Test("三段模式: 打车28奶茶15午饭35")
    func testThreePattern() {
        let segments = splitter.split("打车28奶茶15午饭35")
        #expect(segments.count == 3)
    }
}
