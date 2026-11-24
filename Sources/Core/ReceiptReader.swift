// ReceiptReader.swift：讀一張收據的完整流程。
//
// 1. 文字辨識（OCR.swift）：讀出收據上的字，必要時自動換照片方向再讀。
// 2. 規則（Rules.swift）：日期、時間、金額、卡號前 6 碼、付款方式、營業登記號碼。
// 3. 裝置端 AI（AI.swift）：找出收據上印的店名（要真的在收據上才採用）、品項、類別。
// 4. 店名與類別（Merchants.swift）：記住的店家 → 常見連鎖店清單 → 等待翻譯。
// 5. 規則讀不到日期、時間或金額時，請 AI 直接看照片，答案存成「第二意見」給使用者參考，不會自動填入。
//
// 中文店名的翻譯不在這裡做：Mac 內建的翻譯需要從畫面啟動（第一次會跳出下載語言包的視窗），
// 由 AppModel 另外處理。

import Foundation
import CoreGraphics

enum ReceiptReader {
    static func read(photo url: URL,
                     receipt: Receipt,
                     memory: [String: MerchantInfo],
                     chains: [ChainEntry],
                     useAI: Bool) async -> Receipt {
        var r = receipt
        guard let image = OCR.loadImage(url) else {
            r.status = "failed"
            return r
        }
        // 文字辨識比較花時間，放到背景做，畫面才不會卡住。
        let ocr = await Task.detached(priority: .userInitiated) { () -> (rows: [String], orientation: String)? in
            try? OCR.recognizeBestOrientation(image)
        }.value
        guard let ocr = ocr else {
            r.status = "failed"
            return r
        }
        r.ocrRows = ocr.rows

        let found = Rules.extract(rows: ocr.rows)
        r.date = found.date
        r.time = found.time
        r.amount = found.amount
        r.cardPrefix = found.cardPrefix
        r.pay = found.pay
        r.businessNumber = Rules.businessNumber(ocr.rows)

        let aiReady = useAI && AI.isAvailable
        var ai: AIFields? = nil
        if aiReady {
            ai = await AI.describe(rows: ocr.rows).fields
        }
        if let name = ai?.storeKo, Merchants.appearsOnReceipt(name, rows: ocr.rows) {
            r.storeKo = name
        }
        r.itemsZh = ai?.itemsZh
        let aiCategory = Merchants.normalizeCategory(ai?.category)

        let keys = Merchants.memoryKeys(businessNumber: r.businessNumber, storeKo: r.storeKo)
        if let remembered = keys.compactMap({ memory[$0] }).first {
            r.storeZh = remembered.storeZh
            r.category = remembered.category ?? aiCategory
            r.nameSource = "memory"
        } else if let chain = Merchants.findChain(ocr.rows, in: chains) {
            r.storeZh = chain.name
            r.category = chain.category ?? aiCategory
            r.nameSource = "chain"
        } else {
            r.storeZh = nil
            r.category = aiCategory
            // 有原文店名的話，等一下交給翻譯；沒有的話就請使用者填。
            r.nameSource = r.storeKo == nil ? nil : "translation"
        }

        if aiReady && AI.imageInputCompiled && (r.date == nil || r.time == nil || r.amount == nil) {
            r.secondOpinion = await AI.readImage(image).fields
        }
        r.status = "done"
        return r
    }
}
