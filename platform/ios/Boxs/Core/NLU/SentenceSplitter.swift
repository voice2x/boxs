import Foundation

/// 分句切割器
/// 优先按显式分隔符切，切不动就按模式边界切
final class SentenceSplitter {

    /// 显式分隔符列表
    private let delimiters = [
        "，", ",", "。", "；", ";",
        "然后", "还有", "另外", "接着", "还有个", "对了",
        "顺便", "以及", "、",
    ]

    // MARK: - 切割主入口

    func split(_ text: String) -> [String] {
        // 第一步：按显式分隔符切割
        var segments = splitByDelimiters(text)

        // 第二步：对每个段再做模式边界切割
        return segments.flatMap { splitByPattern($0) }
    }

    // MARK: - 按分隔符切割

    private func splitByDelimiters(_ text: String) -> [String] {
        var result = [text]

        for delim in delimiters {
            var expanded: [String] = []
            for segment in result {
                expanded.append(contentsOf: segment.components(separatedBy: delim))
            }
            result = expanded
        }

        return result
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - 按模式边界切割

    /// 处理无分隔符的情况："午饭35打车28" → ["午饭35", "打车28"]
    private func splitByPattern(_ segment: String) -> [String] {
        if segment.count <= 4 { return [segment] }

        var results: [String] = []

        // 模式：「非数字关键词」+「金额」出现多次
        guard let pattern = try? NSRegularExpression(
            pattern: "([^\\d，。；,;]+?)(\\d+(?:\\.\\d+)?)(?:块|元|块钱)?",
            options: []
        ) else { return [segment] }

        let nsRange = NSRange(segment.startIndex..., in: segment)
        let matches = pattern.matches(in: segment, range: nsRange)

        // 如果只匹配到 1 个或更少，不需要切割
        guard matches.count > 1 else { return [segment] }

        var lastEnd = segment.startIndex
        for match in matches {
            if let range = Range(match.range, in: segment) {
                if range.lowerBound > lastEnd {
                    let prefix = segment[lastEnd..<range.lowerBound]
                        .trimmingCharacters(in: .whitespaces)
                    if !prefix.isEmpty { results.append(String(prefix)) }
                }
                results.append(String(segment[range]))
                lastEnd = range.upperBound
            }
        }

        if lastEnd < segment.endIndex {
            let tail = segment[lastEnd...].trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { results.append(String(tail)) }
        }

        return results.isEmpty ? [segment] : results
    }
}
