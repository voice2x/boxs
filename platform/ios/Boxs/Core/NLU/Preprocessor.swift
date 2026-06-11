import Foundation

/// 文本预处理器：清洗输入 + 中文数字转阿拉伯数字
struct Preprocessor {

    /// 预处理主入口
    func process(_ text: String) -> String {
        var result = text
        result = removeLeadingTrailingNoise(result)
        result = convertChineseNumbers(result)
        result = normalizeWhitespace(result)
        return result
    }

    // MARK: - 清洗

    /// 去除前后噪音字符
    private func removeLeadingTrailingNoise(_ text: String) -> String {
        let noise = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "啊呢吧呀哦哈嗯诶哟"))
        return text.trimmingCharacters(in: noise)
    }

    /// 合并多余空格
    private func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    // MARK: - 中文数字转换

    /// 中文数字 → 阿拉伯数字
    /// "三十五" → "35", "一百二十" → "120", "两块五" → "2.5"
    private func convertChineseNumbers(_ text: String) -> String {
        var result = text

        // 单字数字替换
        let singleDigits: [Character: String] = [
            "零": "0", "一": "1", "二": "2", "两": "2", "三": "3",
            "四": "4", "五": "5", "六": "6", "七": "7", "八": "8", "九": "9",
        ]

        // 逐字替换单字数字
        for (char, digit) in singleDigits {
            result = result.replacingOccurrences(of: String(char), with: digit)
        }

        // 处理 "十" → 10 倍 ("3十" → "30", "十5" → "15")
        result = result.replacingOccurrences(
            of: "(\\d?)十(\\d?)",
            with: "$1$2",
            options: .regularExpression
        )

        // 处理 "百" → 100 倍
        result = result.replacingOccurrences(
            of: "(\\d?)百(\\d?)",
            with: "$1$2",
            options: .regularExpression
        )

        // 处理 "千" → 1000 倍
        result = result.replacingOccurrences(
            of: "(\\d?)千(\\d?)",
            with: "$1$2",
            options: .regularExpression
        )

        // 处理 "万" → 10000 倍（简单场景）
        result = replaceWan(result)

        return result
    }

    /// 处理 "N万" → N*10000
    private func replaceWan(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(\\d+)万", options: []) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        guard !matches.isEmpty else { return text }

        var result = text
        // 从后往前替换，避免偏移
        for match in matches.reversed() {
            guard let numRange = Range(match.range(at: 1), in: text),
                  let num = Int(text[numRange]) else { continue }
            let fullRange = Range(match.range, in: text)!
            result.replaceSubrange(fullRange, with: String(num * 10000))
        }
        return result
    }
}
