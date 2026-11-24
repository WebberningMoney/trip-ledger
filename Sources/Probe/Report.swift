// Report.swift：把每張收據的辨識結果和「標準答案」比對，寫成報告。
//
// 標準答案放在 private/expected.json（作者人工確認過的值），一張收據一筆。
// 報告也寫在 private/ 裡，因為裡面有真實的店家、金額和辨識出來的收據文字，**不會上傳到 GitHub**。
//
// 產生三個檔案（檔名帶時間，另外複製一份 latest.*）：
// - report-日期時間.md：給人看的報告（每個欄位對錯、正確率、AI 取的名稱、辨識出的原始文字）
// - results-日期時間.csv：可以用 Excel／Numbers 打開的表格
// - results-日期時間.json：完整資料（之後用來改進規則）

import Foundation

/// 標準答案（private/expected.json 裡的一筆）。
struct Expected: Codable {
    let file: String
    let date: String
    let time: String?
    let amount: Int
    let cardPrefix: String?
    let pay: String?
    let store: String
    let nameZh: String
    let category: String
}

/// 一張收據的全部結果。
struct ReceiptResult: Codable {
    var file: String
    var expected: Expected?
    var ocrRows: [String] = []
    var ocrSeconds: Double = 0
    var ocrError: String? = nil
    var rules = Extracted()
    var aiText = AIRun()
    var aiImage = AIRun()
}

enum Report {
    /// 欄位比對：標準答案沒有這個值時回傳 nil（不計分）。
    static func check(_ expected: String?, _ got: String?) -> Bool? {
        guard let expected = expected else { return nil }
        return expected == got
    }

    static func mark(_ ok: Bool?) -> String {
        switch ok { case .some(true): return "✅"; case .some(false): return "❌"; case .none: return "—" }
    }

    static func show(_ s: String?) -> String { (s ?? "（無）").replacingOccurrences(of: "|", with: "／") }
    static func show(_ n: Int?) -> String { n.map { String($0) } ?? "（無）" }

    /// 一張收據在某個方法下，五個數字欄位的對錯。
    static func fieldChecks(_ e: Expected, date: String?, time: String?, amount: Int?, card: String?, pay: String?) -> [Bool?] {
        [
            check(e.date, date),
            check(e.time, time),
            check(String(e.amount), amount.map { String($0) }),
            check(e.cardPrefix, card),
            check(e.pay, pay),
        ]
    }

    static func write(results: [ReceiptResult], header: [String], to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp: String = {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmm"; return f.string(from: Date())
        }()
        let fieldNames = ["日期", "時間", "金額", "卡號前6碼", "付款方式"]

        var md: [String] = ["# 階段 0：收據辨識測試報告", ""]
        md += header.map { "- " + $0 }
        md.append("")

        // 正確率統計
        var aRight = [Int](repeating: 0, count: 5), aTotal = [Int](repeating: 0, count: 5)
        var bRight = [Int](repeating: 0, count: 5), bTotal = [Int](repeating: 0, count: 5)
        var categoryRight = 0, categoryTotal = 0
        for r in results {
            guard let e = r.expected else { continue }
            let a = fieldChecks(e, date: r.rules.date, time: r.rules.time, amount: r.rules.amount,
                                card: r.rules.cardPrefix, pay: r.rules.pay)
            for (i, ok) in a.enumerated() { if let ok = ok { aTotal[i] += 1; if ok { aRight[i] += 1 } } }
            if let f = r.aiImage.fields {
                let b = fieldChecks(e, date: f.date, time: f.time, amount: f.amount, card: f.cardPrefix, pay: f.pay)
                for (i, ok) in b.enumerated() { if let ok = ok { bTotal[i] += 1; if ok { bRight[i] += 1 } } }
            }
            if let c = r.aiText.fields?.category { categoryTotal += 1; if c == e.category { categoryRight += 1 } }
        }
        func pct(_ r: Int, _ t: Int) -> String { t == 0 ? "（沒有資料）" : "\(r)/\(t)（\(Int((Double(r) / Double(t) * 100).rounded()))%）" }

        md += ["## 正確率", "", "| 欄位 | 方法 A：文字辨識＋規則 | 方法 B：AI 直接看照片 |", "|---|---|---|"]
        for i in 0..<5 { md.append("| \(fieldNames[i]) | \(pct(aRight[i], aTotal[i])) | \(pct(bRight[i], bTotal[i])) |") }
        md.append("| 消費類別（方法 A 的 AI） | \(pct(categoryRight, categoryTotal)) | |")
        md += ["", "「—」表示標準答案沒有這個值（例如收據上沒印卡號），不計分。", ""]

        // 每張收據
        md += ["## 每張收據", "",
               "| 檔案 | 日期 | 時間 | 金額 | 卡號 | 付款 | 方法 A 讀到的 | 方法 B 讀到的 | 秒數（辨識／AI-A／AI-B） |",
               "|---|---|---|---|---|---|---|---|---|"]
        for r in results {
            guard let e = r.expected else {
                md.append("| \(r.file) | 沒有標準答案 | | | | | | | |"); continue
            }
            let a = fieldChecks(e, date: r.rules.date, time: r.rules.time, amount: r.rules.amount,
                                card: r.rules.cardPrefix, pay: r.rules.pay)
            let f = r.aiImage.fields
            let b = f.map { fieldChecks(e, date: $0.date, time: $0.time, amount: $0.amount, card: $0.cardPrefix, pay: $0.pay) }
            let cells = (0..<5).map { i in "A\(mark(a[i])) B\(b.map { mark($0[i]) } ?? "—")" }
            let aText = "\(show(r.rules.date)) \(show(r.rules.time)) \(show(r.rules.amount)) \(show(r.rules.cardPrefix)) \(show(r.rules.pay))"
            let bText = f.map { "\(show($0.date)) \(show($0.time)) \(show($0.amount)) \(show($0.cardPrefix)) \(show($0.pay))" }
                ?? show(r.aiImage.error)
            let secs = String(format: "%.1f／%.1f／%.1f", r.ocrSeconds, r.aiText.seconds, r.aiImage.seconds)
            md.append("| \(r.file) | \(cells.joined(separator: " | ")) | \(aText) | \(bText) | \(secs) |")
        }

        // AI 取的名稱
        md += ["", "## AI 取的名稱與類別（和花費表比較）", "",
               "| 檔案 | 花費表的名稱 | 類別 | 方法 A：店名－品項 | 類別 | 方法 B：店名－品項 | 類別 |",
               "|---|---|---|---|---|---|---|"]
        for r in results {
            let e = r.expected
            let a = r.aiText.fields, b = r.aiImage.fields
            let aName = a.map { "\(show($0.storeZh))-\(show($0.itemsZh))" } ?? show(r.aiText.error)
            let bName = b.map { "\(show($0.storeZh))-\(show($0.itemsZh))" } ?? "—"
            md.append("| \(r.file) | \(show(e?.nameZh)) | \(show(e?.category)) | \(aName) | \(show(a?.category)) | \(bName) | \(show(b?.category)) |")
        }

        // 原始辨識文字（方便找出規則判斷錯的原因）
        md += ["", "## 文字辨識讀到的原始內容", ""]
        for r in results {
            md += ["<details><summary>\(r.file)</summary>", "", "```"]
            md += r.ocrError.map { ["辨識失敗：" + $0] } ?? r.ocrRows
            md += ["```", ""]
            if !r.aiText.raw.isEmpty { md += ["AI（方法 A）原始回覆：", "```", r.aiText.raw, "```", ""] }
            if !r.aiImage.raw.isEmpty { md += ["AI（方法 B）原始回覆：", "```", r.aiImage.raw, "```", ""] }
            md += ["</details>", ""]
        }

        // CSV
        func csv(_ s: String?) -> String { "\"" + (s ?? "").replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["檔案,答案日期,答案時間,答案金額,答案卡號,答案付款,A日期,A時間,A金額,A卡號,A付款,B日期,B時間,B金額,B卡號,B付款,花費表名稱,A店名,A品項,A類別,辨識秒數,AI-A秒數,AI-B秒數"]
        for r in results {
            let e = r.expected, b = r.aiImage.fields, a = r.aiText.fields
            let cols: [String?] = [r.file, e?.date, e?.time, e.map { String($0.amount) }, e?.cardPrefix, e?.pay,
                                   r.rules.date, r.rules.time, r.rules.amount.map { String($0) }, r.rules.cardPrefix, r.rules.pay,
                                   b?.date, b?.time, b?.amount.map { String($0) }, b?.cardPrefix, b?.pay,
                                   e?.nameZh, a?.storeZh, a?.itemsZh, a?.category,
                                   String(format: "%.2f", r.ocrSeconds), String(format: "%.2f", r.aiText.seconds),
                                   String(format: "%.2f", r.aiImage.seconds)]
            lines.append(cols.map(csv).joined(separator: ","))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let json = try encoder.encode(results)

        let files: [(String, Data)] = [
            ("report-\(stamp).md", Data(md.joined(separator: "\n").utf8)),
            ("results-\(stamp).csv", Data(("\u{FEFF}" + lines.joined(separator: "\n")).utf8)),
            ("results-\(stamp).json", json),
        ]
        for (name, data) in files {
            try data.write(to: dir.appendingPathComponent(name))
            let latest = name.replacingOccurrences(of: "-\(stamp)", with: "-latest")
            try data.write(to: dir.appendingPathComponent(latest))
        }
        print("📄 報告：\(dir.appendingPathComponent("report-latest.md").path)")
    }
}
