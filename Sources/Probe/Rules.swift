// Rules.swift：用固定規則從收據文字讀出「日期、時間、金額、卡號前 6 碼、付款方式」。
//
// 這些欄位都是數字，所以不交給 AI 判斷（AI 可能會「猜」出看起來合理但錯的數字），
// 而是用正規表示式（一種描述「文字長什麼樣子」的寫法）直接比對。
//
// 判讀方式（白話）：
// - 日期：找 2026-10-10、2026/10/13、2026.10.14、2026년 10월 11일、26/10/11 這些寫法；
//   優先用「同一行後面就有時間」的那個（例如「거래일시 2026-10-10 18:14:59」），
//   這樣可以避開「退換貨期限 2026-10-25」這類沒有時間的日期。
// - 金額：先找有關鍵字的那一行（승인금액、결제금액、Payment amount、합계…），
//   依關鍵字的優先順序取那一行最大的金額；含「부가세、할인、Refund、Tax」等字的行不算。
//   都找不到時，改用整張收據最常出現的金額。
// - 卡號前 6 碼：找「4 位數字＋2 位數字，後面接著 * 號」的寫法（例如 5483-68**、548368*****）。
// - 付款方式：出現 LINE Pay／라인페이 就是 LINE Pay；出現 현금（現金）且沒有卡號就是現金；其他有卡號的算刷卡。

import Foundation

/// 規則讀出來的結果；讀不到的欄位是 nil。
struct Extracted: Codable {
    var date: String? = nil        // yyyy-MM-dd
    var time: String? = nil        // HH:mm
    var amount: Int? = nil         // 實際付款金額（原幣）
    var cardPrefix: String? = nil  // 卡號前 6 碼
    var pay: String? = nil         // card／linepay／cash
}

enum Rules {
    static func extract(rows: [String]) -> Extracted {
        var result = Extracted()
        let dt = dateTime(rows)
        result.date = dt.date
        result.time = dt.time
        result.amount = amount(rows)
        let all = rows.joined(separator: "\n")
        result.cardPrefix = cardPrefix(all)
        result.pay = pay(all, cardPrefix: result.cardPrefix)
        return result
    }

    // MARK: - 日期與時間

    /// (正規表示式, 年份是不是 4 位數)
    private static let datePatterns: [(String, Bool)] = [
        (#"(20\d{2})\s*[-./년]\s*(\d{1,2})\s*[-./월]\s*(\d{1,2})(?!\d)"#, true),
        (#"(?<![\d-])(\d{2})[-/](\d{1,2})[-/](\d{1,2})(?![\d-])"#, false),
    ]
    private static let timePattern = #"(?<!\d)([01]?\d|2[0-3])\s?:\s?([0-5]\d)"#

    static func dateTime(_ rows: [String]) -> (date: String?, time: String?) {
        var firstDateWithoutTime: String? = nil
        for row in rows {
            let ns = row as NSString
            for (pattern, fourDigitYear) in datePatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in regex.matches(in: row, range: NSRange(location: 0, length: ns.length)) {
                    guard let y = Int(ns.substring(with: match.range(at: 1))),
                          let m = Int(ns.substring(with: match.range(at: 2))),
                          let d = Int(ns.substring(with: match.range(at: 3))) else { continue }
                    let year = fourDigitYear ? y : 2000 + y
                    guard (2020...2035).contains(year), (1...12).contains(m), (1...31).contains(d) else { continue }
                    let date = String(format: "%04d-%02d-%02d", year, m, d)
                    let rest = ns.substring(from: match.range.location + match.range.length)
                    if let time = firstTime(in: rest) {
                        return (date, time)
                    }
                    if firstDateWithoutTime == nil { firstDateWithoutTime = date }
                }
            }
        }
        return (firstDateWithoutTime, nil)
    }

    static func firstTime(in text: String) -> String? {
        guard let match = firstMatch(timePattern, in: text),
              let h = Int(match[1]), let m = Int(match[2]) else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    // MARK: - 金額

    /// 關鍵字（已去掉空白、轉小寫），越前面越優先。
    private static let amountKeywords = [
        "면세환급후", "승인금액", "결제금액", "purchaseprice", "paymentamount", "paidamt",
        "받은금액", "cardpayment", "creditcard", "linepay", "신용카드", "매출합계", "판매합계",
        "총금액", "총액", "합계", "total", "받을금액", "판매금액", "salesamount",
    ]
    /// 含這些字的行不是「實際付款金額」（稅金、折扣、退稅、找零、單價…）。
    private static let excludedWords = [
        "부가세", "vat", "taxtotal", "과세물품", "과세합", "과세금액", "공급가", "할인", "refund", "환급액", "즉시환급",
        "단가", "거스름", "면세합", "administrative", "제비용", "환급전",
    ]
    private static let moneyPattern =
        #"(?<![\d,.])(\d{1,3}(?:[,.]\d{3})+|\d+(?=\s*(?:원|won|\(won\))))"#

    static func amount(_ rows: [String]) -> Int? {
        var best: (rank: Int, value: Int)? = nil
        for row in rows {
            let key = normalized(row)
            if excludedWords.contains(where: { key.contains($0) }) { continue }
            guard let rank = amountKeywords.firstIndex(where: { key.contains($0) }) else { continue }
            guard let value = moneyValues(in: row).max() else { continue }
            if best == nil || rank < best!.rank { best = (rank, value) }
        }
        if let best = best { return best.value }
        // 找不到關鍵字：用最常出現的金額（一樣多時取比較大的）。
        var counts: [Int: Int] = [:]
        for row in rows where !excludedWords.contains(where: { normalized(row).contains($0) }) {
            for value in moneyValues(in: row) where value >= 100 { counts[value, default: 0] += 1 }
        }
        return counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }

    static func moneyValues(in row: String) -> [Int] {
        allMatches(moneyPattern, in: row, caseInsensitive: true).compactMap { match in
            Int(match[1].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: ""))
        }
    }

    // MARK: - 卡號與付款方式

    private static let cardPattern = #"(?<!\d)(\d{4})[\s-]?(\d{2})(?:\d{2})?[\s-]?[*＊xX※]"#

    static func cardPrefix(_ text: String) -> String? {
        guard let match = firstMatch(cardPattern, in: text) else { return nil }
        return match[1] + match[2]
    }

    static func pay(_ text: String, cardPrefix: String?) -> String? {
        let key = normalized(text)
        if key.contains("linepay") || key.contains("라인페이") { return "linepay" }
        if key.contains("현금") && cardPrefix == nil { return "cash" }
        if cardPrefix != nil || key.contains("카드") || key.contains("card") { return "card" }
        return nil
    }

    // MARK: - 小工具

    /// 去掉空白、轉小寫（收據常把「합 계」字距拉開）。
    static func normalized(_ s: String) -> String {
        s.lowercased().components(separatedBy: .whitespaces).joined()
    }

    static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        allMatches(pattern, in: text, caseInsensitive: false).first
    }

    static func allMatches(_ pattern: String, in text: String, caseInsensitive: Bool) -> [[String]] {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { i in
                let range = match.range(at: i)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
        }
    }
}
