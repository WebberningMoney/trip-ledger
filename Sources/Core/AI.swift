// AI.swift：用 Mac 內建的裝置端 AI（Apple Foundation Models）整理收據文字。
//
// 方法 A：先用文字辨識讀出收據上的字，再交給 AI 做「文字工作」——
//         找出收據上印的店名、品項濃縮、判斷消費類別。金額日期不交給 AI（由 Rules.swift 負責）。
//         App 裡：AI 給的店名一定要真的出現在收據上才採用（見 Merchants.appearsOnReceipt），
//         中文店名改用 Mac 內建的翻譯，類別由 Merchants.normalizeCategory 對應到八類。
// 方法 B：直接把照片交給 AI，請它讀出全部欄位（包含金額、日期）。
//         階段 0 實測數字常錯、還會編店名，所以 App 只在「規則讀不到」時，把它的答案當參考（第二意見）。
//         方法 B 用到 macOS 27 才有的「AI 直接看圖片」功能，放在 AI_IMAGE_INPUT 開關裡：
//         編譯不過時，build.sh 會自動改成只編譯方法 A。
//
// 這裡不用 @Generable 這類 Swift 巨集（只有命令列開發者工具時可能編譯不過），
// 而是請 AI 回傳 JSON 文字，再由程式解析；解析失敗就當成「需要人工確認」。

import Foundation
import FoundationModels
import CoreGraphics

/// AI 回傳並解析後的欄位（全部都可能是 nil）。
struct AIFields: Codable, Equatable {
    var storeKo: String? = nil
    var storeZh: String? = nil
    var itemsZh: String? = nil
    var category: String? = nil
    // 以下只有方法 B 會填
    var date: String? = nil
    var time: String? = nil
    var amount: Int? = nil
    var cardPrefix: String? = nil
    var pay: String? = nil
}

/// 一次 AI 呼叫的結果：解析好的欄位、AI 原始回覆、花了幾秒、錯誤訊息。
struct AIRun: Codable, Equatable {
    var fields: AIFields? = nil
    var raw: String = ""
    var seconds: Double = 0
    var error: String? = nil
}

enum AI {
    /// 裝置端 AI 現在能不能用（例如沒有開啟 Apple Intelligence 就不能用）。
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }
    static var statusText: String { "\(SystemLanguageModel.default.availability)" }

    static let categoryGuide = """
    category must be exactly one of: 食 衣 住 行 樂 奢 他
    食 = food, drinks, cafe, restaurant, convenience store, supermarket, snacks
    衣 = clothes, cosmetics, skincare, beauty, accessories
    住 = lodging
    行 = transport, subway, taxi, train
    樂 = tickets, attractions, activities, amusement
    奢 = luxury brand goods
    他 = medicine, pharmacy, other
    """

    static let textInstructions = """
    You read the OCR text of one shop receipt from Korea and describe it for a Traditional Chinese (Taiwan) travel expense sheet.
    Reply with ONLY one JSON object and nothing else, using these keys:
    {"storeKo": the shop or brand name copied exactly as printed on the receipt (the shop name with its branch, for example "미피 해운대점"; not the operating company in parentheses, not "(주)" or "주식회사"), "storeZh": short shop name in Traditional Chinese (keep famous brand names such as Starbucks as 星巴克, Olive Young as Olive Young), "itemsZh": the main items bought, in Traditional Chinese, under 12 characters, only items that are printed on the receipt, "category": one character}
    \(categoryGuide)
    Do not include prices, dates or card numbers.
    """

    static let imageInstructions = """
    You read a photo of one shop receipt from Korea for a Traditional Chinese (Taiwan) travel expense sheet.
    Reply with ONLY one JSON object and nothing else, using these keys:
    {"storeKo": shop name as printed, "storeZh": short shop name in Traditional Chinese, "itemsZh": main items in Traditional Chinese under 12 characters, "category": one character,
     "date": "YYYY-MM-DD" of the purchase, "time": "HH:MM" of the purchase, "amount": the amount actually paid as an integer without commas,
     "cardPrefix": the first 6 digits of the card number or null, "pay": "card" or "linepay" or "cash" or null}
    \(categoryGuide)
    """

    /// 方法 A 的 AI 部分：給它收據文字，請它回傳店名、品項、類別。
    static func describe(rows: [String]) async -> AIRun {
        let start = Date()
        var run = AIRun()
        do {
            let session = LanguageModelSession(instructions: textInstructions)
            let prompt = "Receipt OCR text:\n" + rows.joined(separator: "\n")
            let response = try await session.respond(to: prompt)
            run.raw = response.content
            run.fields = parse(response.content)
            if run.fields == nil { run.error = "AI 回覆不是可以解析的 JSON" }
        } catch {
            run.error = "\(error)"
        }
        run.seconds = Date().timeIntervalSince(start)
        return run
    }

    /// 方法 B：直接把照片交給 AI。
    static func readImage(_ image: CGImage) async -> AIRun {
        #if AI_IMAGE_INPUT
        let start = Date()
        var run = AIRun()
        do {
            let session = LanguageModelSession(instructions: imageInstructions)
            // 寫法依 macOS 27 SDK 的介面檔（build/fm_image_api.txt）：圖片要包成 Attachment 才能放進提問。
            // 編譯不過時 build.sh 會改成不含方法 B。
            let photo = FoundationModels.Attachment<ImageAttachmentContent>(image)
            let response = try await session.respond {
                "Read this receipt photo."
                photo
            }
            run.raw = response.content
            run.fields = parse(response.content)
            if run.fields == nil { run.error = "AI 回覆不是可以解析的 JSON" }
        } catch {
            run.error = "\(error)"
        }
        run.seconds = Date().timeIntervalSince(start)
        return run
        #else
        return AIRun(error: "這次編譯沒有包含方法 B（見 build/build_log.txt）")
        #endif
    }

    static var imageInputCompiled: Bool {
        #if AI_IMAGE_INPUT
        return true
        #else
        return false
        #endif
    }

    /// 從 AI 的回覆裡找出 JSON 物件並解析；數字欄位接受「12,500」這種字串寫法。
    static func parse(_ text: String) -> AIFields? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let data = String(text[open...close]).data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func string(_ key: String) -> String? {
            if let s = object[key] as? String, !s.isEmpty, s.lowercased() != "null" { return s }
            if let n = object[key] as? NSNumber { return n.stringValue }
            return nil
        }
        var fields = AIFields()
        fields.storeKo = string("storeKo")
        fields.storeZh = string("storeZh")
        fields.itemsZh = string("itemsZh")
        fields.category = string("category")
        fields.date = string("date")
        fields.time = string("time")
        fields.cardPrefix = string("cardPrefix")
        fields.pay = string("pay")
        if let s = string("amount") {
            fields.amount = Int(s.filter { $0.isNumber })
        }
        return fields
    }
}
