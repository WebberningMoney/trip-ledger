// Models.swift：帳本裡的資料長什麼樣子。
//
// - Trip（行程）：例如「2026 釜山」，裡面有很多筆 Receipt（消費）。
// - Receipt（一筆消費）：一張收據照片讀出來的欄位，加上使用者修改過的內容。
//
// 這些資料會存成 JSON 檔（一種純文字的資料格式），放在
// ~/Library/Application Support/TripLedger/ 裡（見 LedgerStore.swift）。

import Foundation

/// 消費類別（和作者花費表的分類一樣）。
enum SpendCategory {
    static let all = ["食", "衣", "住", "行", "樂", "奢", "他", "代買"]

    /// 每個類別的白話說明（畫面上滑鼠停留時顯示）。
    static let help: [String: String] = [
        "食": "餐廳、咖啡、超商、超市、零食",
        "衣": "衣服、美妝、保養品、飾品",
        "住": "住宿",
        "行": "交通：地鐵、計程車、Uber、機票",
        "樂": "門票、遊樂設施、體驗活動",
        "奢": "精品、高價免稅品",
        "他": "藥品、雜貨、其他",
        "代買": "幫別人買的",
    ]
}

/// 付款方式。
enum PayMethod {
    static let all = ["card", "linepay", "cash"]
    static func label(_ key: String?) -> String {
        switch key {
        case "card": return "刷卡"
        case "linepay": return "LINE Pay"
        case "cash": return "現金"
        default: return "—"
        }
    }
}

/// 一個行程。
struct Trip: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var currency: String = "KRW"
    var created = Date()
    var receipts: [Receipt] = []

    /// 依日期、時間排好的消費（沒有日期的放最後）。
    var sortedReceipts: [Receipt] {
        receipts.sorted { a, b in
            let ka = (a.date ?? "9999-99-99") + (a.time ?? "99:99")
            let kb = (b.date ?? "9999-99-99") + (b.time ?? "99:99")
            return ka == kb ? a.imported < b.imported : ka < kb
        }
    }
}

/// 一筆消費（一張收據）。
struct Receipt: Codable, Identifiable, Equatable {
    var id = UUID()
    /// 照片在 App 資料夾裡的檔名（原始照片不會被修改，App 會複製一份）。
    var photoFile: String
    /// 原始照片的檔名（只是給人看，方便對照）。
    var originalName: String
    var imported = Date()

    /// 處理狀態：waiting（等待辨識）、reading（辨識中）、done（完成）、failed（讀不到照片）
    var status: String = "waiting"

    // 規則讀出來、使用者可以修改的欄位
    var date: String? = nil         // yyyy-MM-dd
    var time: String? = nil         // HH:mm
    var amount: Int? = nil          // 原幣金額
    var cardPrefix: String? = nil   // 卡號前 6 碼
    var pay: String? = nil          // card／linepay／cash

    // 店家與品項
    var businessNumber: String? = nil  // 營業登記號碼（辨認同一家店）
    var storeKo: String? = nil         // 收據上印的店名（原文）
    var storeZh: String? = nil         // 中文店名
    var itemsZh: String? = nil         // 品項（中文、簡短）
    var category: String? = nil        // 食衣住行樂奢他代買
    /// 品項是 AI 寫的（還沒被使用者改過或確認）。實測 AI 寫的品項常常不準，所以要標紅字。
    /// （用 Bool? 而不是 Bool：舊版存的帳本沒有這個欄位，讀檔時才不會失敗。）
    var itemsFromAI: Bool? = nil
    /// 店名和類別是從哪裡來的：memory（記住的店家）、chain（常見連鎖店清單）、
    /// translation（翻譯）、ai（AI 猜的）、user（使用者改過）
    var nameSource: String? = nil
    var note: String = ""

    /// 使用者按過「確認」。
    var confirmed = false
    /// 規則讀不到的欄位，AI 直接看照片的猜測（只當參考，不會自動填入）。
    var secondOpinion: AIFields? = nil
    /// 文字辨識讀到的原始內容（方便使用者對照、也方便除錯）。
    var ocrRows: [String] = []

    /// 畫面上顯示的「項目」：店名-品項（和花費表一樣）。
    var title: String {
        let store = storeZh ?? storeKo ?? "（店名未知）"
        if let items = itemsZh, !items.isEmpty { return "\(store)-\(items)" }
        return store
    }

    /// 還需要使用者確認的地方（用白話列出）。空的就代表這筆沒問題。
    var problems: [String] {
        if status == "waiting" || status == "reading" { return [] }
        if status == "failed" { return ["照片讀不到"] }
        var list: [String] = []
        if date == nil { list.append("日期") }
        if time == nil { list.append("時間") }
        if amount == nil { list.append("金額") }
        if confirmed { return list }
        if storeZh == nil { list.append("店名") }
        if category == nil { list.append("類別") }
        if nameSource == "ai" || nameSource == "translation" { list.append("店名和類別是自動判斷的") }
        if itemsFromAI == true { list.append("品項是 AI 寫的") }
        return list
    }

    /// 需要確認（畫面上用紅字）。
    var needsReview: Bool { !problems.isEmpty }
}
