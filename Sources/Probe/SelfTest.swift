// SelfTest.swift：規則（Rules.swift）的自我測試。
//
// 用「假的收據文字」檢查日期、時間、金額、卡號前 6 碼、付款方式有沒有讀對。
// 這裡的文字都是照著真實收據的「格式」編出來的假資料，卡號用的是常見的測試號碼，不含任何真實個資。
// 執行：build/receipt-probe --selftest（scripts/selftest.sh 會呼叫它）。

import Foundation

enum SelfTest {
    struct Case {
        let name: String
        let rows: [String]
        let expect: Extracted
    }

    static let cases: [Case] = [
        Case(name: "一般刷卡收據（日期後面接時間、합계）",
             rows: ["2026-10-10 20:37(토) POS:01 BILL:000123", "합  계 :  8,200", "받은금액 :  8,200",
                    "[해외마스타] 5412-3400-****-****"],
             expect: Extracted(date: "2026-10-10", time: "20:37", amount: 8200, cardPrefix: "541234", pay: "card")),
        Case(name: "兩位數年份、LINE Pay、金額後面有「원」",
             rows: ["라인페이 승인", "판매금액  43,000원", "합 계  43,000원", "4111-11**-****-0000(B)", "거래일시:26-10-12 12:45:35"],
             expect: Extracted(date: "2026-10-12", time: "12:45", amount: 43000, cardPrefix: "411111", pay: "linepay")),
        Case(name: "韓文年月日、金額 0 元、付現金、有折扣",
             rows: ["판매 금액:  0원", "할인 금액:  -24,000원", "결제 수단:  현금", "발권 일자:  2026년 10월 11일 17:47:08"],
             expect: Extracted(date: "2026-10-11", time: "17:47", amount: 0, cardPrefix: nil, pay: "cash")),
        Case(name: "退稅單（不能拿到稅金或退稅額）",
             rows: ["Date of sale  2026-10-11 20:22:44", "총액 Sales amount  76,470", "부가세 V.A.T  6,952",
                    "합계 Tax total  6,952", "환급액 Refund value  5,000"],
             expect: Extracted(date: "2026-10-11", time: "20:22", amount: 76470, cardPrefix: nil, pay: nil)),
        Case(name: "免稅後金額、斜線日期、退換貨期限日期要略過",
             rows: ["교환/반품 기한 2026-10-25", "4000-0012-****-****  /  2026/10/13  21:07:35",
                    "면세환급전금액:  369,600원", "면세 환급 금액:  -23,000원", "면세환급후금액:  346,600원"],
             expect: Extracted(date: "2026-10-13", time: "21:07", amount: 346600, cardPrefix: "400000", pay: "card")),
        Case(name: "點號日期、卡號連在一起",
             rows: ["[POS 1050204]  2026.10.14 12:22:48", "판매 합계  12,000", "해외마스타(신용카드)  541234**********",
                    "승인금액  12,000"],
             expect: Extracted(date: "2026-10-14", time: "12:22", amount: 12000, cardPrefix: "541234", pay: "card")),
        Case(name: "電話號碼、單號不能當成日期或卡號",
             rows: ["TEL: 051-743-7771  877-87-01870", "주문번호 : 202600200011307", "주문일시 : 2026-10-12 21:38:15",
                    "결제금액  12,500", "카드번호 : 411111*********"],
             expect: Extracted(date: "2026-10-12", time: "21:38", amount: 12500, cardPrefix: "411111", pay: "card")),
        // 以下是第一次實機測試後，依文字辨識常見的讀錯加上的題目（文字是假的，只模仿讀錯的樣子）
        Case(name: "「-」被讀成「~」、分隔符號不見、* 被讀成 ※",
             rows: ["[매출일] 202610~12 13:23:53", "승인 일시:  2026-1012 13:23:54", "합계금액  17,000",
                    "카드번호:  5412-34**-***※~***"],
             expect: Extracted(date: "2026-10-12", time: "13:23", amount: 17000, cardPrefix: "541234", pay: "card")),
        Case(name: "日期和時間黏在一起",
             rows: ["[거래일시]  2026-10-1112:56:41", "합계 금액(₩):  30,000", "부가세(₩):  2,727", "판매 금액(₩):  27,273"],
             expect: Extracted(date: "2026-10-11", time: "12:56", amount: 30000, cardPrefix: nil, pay: nil)),
        Case(name: "金額在下一行、逗號後多空白、用稅金挑出正確總額、* 被讀成 #",
             rows: ["2026-10-11 19:58:59", "합계금액", "61, 000", "부가세  5,544", "승인금액:  5,544",
                    "카드번호: 4111-1100-#***"],
             expect: Extracted(date: "2026-10-11", time: "19:58", amount: 61000, cardPrefix: "411111", pay: "card")),
        Case(name: "免稅店匯率不能當成金額",
             rows: ["SaleDT. 2026/10/14 18:00", "CREDIT CARD", "TODAY'S KRW 1,335.80 JPY 158.59"],
             expect: Extracted(date: "2026-10-14", time: "18:00", amount: nil, cardPrefix: nil, pay: "card")),
        Case(name: "電話號碼後面的網址（www）不能當成卡號",
             rows: ["고객센터 : 1577-4887 www.example.com", "2026-10-13 17:21:02", "결제금액  22,800",
                    "[카드번호]  4000-0012-****-****"],
             expect: Extracted(date: "2026-10-13", time: "17:21", amount: 22800, cardPrefix: "400000", pay: "card")),
    ]

    /// 全部通過回傳 true；有錯會印出哪一題、哪個欄位。
    static func run() -> Bool {
        var failed = 0
        for c in cases {
            let got = Rules.extract(rows: c.rows)
            var problems: [String] = []
            if got.date != c.expect.date { problems.append("日期 \(got.date ?? "無") ≠ \(c.expect.date ?? "無")") }
            if got.time != c.expect.time { problems.append("時間 \(got.time ?? "無") ≠ \(c.expect.time ?? "無")") }
            if got.amount != c.expect.amount {
                problems.append("金額 \(got.amount.map { String($0) } ?? "無") ≠ \(c.expect.amount.map { String($0) } ?? "無")")
            }
            if got.cardPrefix != c.expect.cardPrefix {
                problems.append("卡號 \(got.cardPrefix ?? "無") ≠ \(c.expect.cardPrefix ?? "無")")
            }
            if got.pay != c.expect.pay { problems.append("付款 \(got.pay ?? "無") ≠ \(c.expect.pay ?? "無")") }
            if problems.isEmpty {
                print("✅ \(c.name)")
            } else {
                failed += 1
                print("❌ \(c.name)：" + problems.joined(separator: "；"))
            }
        }
        print(failed == 0 ? "規則自我測試：全部 \(cases.count) 題通過" : "規則自我測試：\(failed)／\(cases.count) 題沒通過")
        return failed == 0
    }
}
