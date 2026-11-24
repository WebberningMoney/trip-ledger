// Merchants.swift：店名和類別怎麼決定。
//
// 依這個順序找，找到就停：
// 1. 記住的店家：使用者改過一次店名或類別的店，App 會記住（用營業登記號碼或收據上的店名辨認），
//    下次遇到同一家店直接套用。存在 ~/Library/Application Support/TripLedger/merchants.json。
// 2. 常見連鎖店清單：Resources/chains.json（Olive Young、CU、Daiso、星巴克…），歡迎大家補充。
// 3. 都沒有：AI 只負責找出收據上印的店名（程式會確認那段字真的在收據上，避免 AI 編造）、
//    品項和類別；店名再用 Mac 內建的翻譯翻成中文（見 AppModel 的翻譯部分）。
//
// AI 回答的類別如果不在八類裡（例如「飲」「藥」），由 normalizeCategory 對應到最接近的一類。

import Foundation

/// 一家記住的店（或連鎖店清單裡的一筆）。
struct MerchantInfo: Codable, Equatable {
    var storeZh: String
    var category: String?
}

/// 常見連鎖店清單的一筆：收據上出現任何一個 match 字串，就算是這家店。
struct ChainEntry: Codable {
    let match: [String]
    let name: String
    let category: String?
}

enum Merchants {
    /// 把 AI 回答的類別對應到八類；對應不到回傳 nil（交給使用者決定）。
    static func normalizeCategory(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if SpendCategory.all.contains(text) { return text }
        text = text.lowercased()
        let table: [(String, [String])] = [
            ("代買", ["代買", "代购"]),
            ("食", ["飲", "饮", "食", "餐", "咖啡", "茶", "零食", "超市", "超商", "food", "drink", "cafe"]),
            ("衣", ["衣", "妝", "妆", "美容", "保養", "服", "beauty", "cosmetic", "cloth"]),
            ("住", ["住", "宿", "飯店", "酒店", "hotel", "lodging"]),
            ("行", ["行", "交通", "車", "车", "地鐵", "taxi", "transport"]),
            ("樂", ["樂", "乐", "門票", "门票", "娛樂", "娱乐", "遊", "ticket", "fun"]),
            ("奢", ["奢", "精品", "名牌", "luxury"]),
            ("他", ["他", "藥", "药", "醫", "雜貨", "other", "medicine"]),
        ]
        for (category, words) in table where words.contains(where: { text.contains($0) }) {
            return category
        }
        return nil
    }

    /// 比對用：去掉空白、轉小寫。
    static func key(_ s: String) -> String {
        s.lowercased().components(separatedBy: .whitespacesAndNewlines).joined()
    }

    /// 記住的店家用的索引：有營業登記號碼就用號碼，否則用收據上的店名。
    static func memoryKeys(businessNumber: String?, storeKo: String?) -> [String] {
        var keys: [String] = []
        if let b = businessNumber { keys.append("biz:" + b) }
        if let s = storeKo, !key(s).isEmpty { keys.append("name:" + key(s)) }
        return keys
    }

    /// 在常見連鎖店清單裡找：收據文字（去掉空白、轉小寫）包含任何一個 match 字串就算。
    static func findChain(_ rows: [String], in chains: [ChainEntry]) -> ChainEntry? {
        let text = key(rows.joined(separator: " "))
        return chains.first { entry in entry.match.contains { text.contains(key($0)) } }
    }

    /// AI 說的店名，是不是真的出現在收據上（避免 AI 編造店名）。
    static func appearsOnReceipt(_ name: String, rows: [String]) -> Bool {
        let k = key(name)
        guard k.count >= 2 else { return false }
        return key(rows.joined(separator: " ")).contains(k)
    }

    /// 讀取 App 內建的常見連鎖店清單（Resources/chains.json）。
    static func loadChains() -> [ChainEntry] {
        guard let url = Bundle.main.url(forResource: "chains", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([ChainEntry].self, from: data) else { return [] }
        return list
    }
}
