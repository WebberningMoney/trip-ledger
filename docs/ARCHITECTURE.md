# 架構說明（給想看懂程式的人）

> 目前只有「階段 0：收據辨識測試工具」。正式的 App 還沒開始寫，這份文件會隨著開發補充。

## 1. 階段 0 在做什麼

在寫正式 App 之前，先回答一個問題：**Mac 內建的文字辨識和 AI，讀韓文熱感紙收據到底準不準？**

做法是拿作者 2026 年 10 月釜山旅遊的 37 張真實收據（只放在作者自己 Mac 的 `private/` 資料夾，不上傳），
用兩種方法讀出欄位，再和人工確認過的「標準答案」比對。

```mermaid
flowchart TD
    P[收據照片<br/>private/receipts] --> V[文字辨識<br/>Vision]
    V --> R[同一橫排接成一行<br/>OCR.rows]
    R --> RU[規則讀數字欄位<br/>日期・時間・金額・卡號・付款方式<br/>Rules.swift]
    R --> AT[裝置端 AI 讀文字<br/>店名・品項・類別<br/>AI.describe]
    P --> AI2[裝置端 AI 直接看照片<br/>全部欄位<br/>AI.readImage]
    RU --> C{和標準答案比對<br/>private/expected.json}
    AT --> C
    AI2 --> C
    C --> REP[報告<br/>private/results/report-latest.md]

    subgraph A[方法 A]
        V
        R
        RU
        AT
    end
    subgraph B[方法 B（只拿來比較）]
        AI2
    end
```

## 2. 為什麼數字欄位不交給 AI

AI 讀不清楚的時候，可能會「猜」出一個看起來合理、但其實是錯的數字，而且很難被發現。
金額、日期、卡號這些欄位的格式很固定，用規則讀比較可靠；讀不到就留空，讓使用者確認，不會悄悄填錯。
AI 只做它比較擅長、而且錯了也容易看出來的文字工作：店名翻成中文、品項濃縮、判斷消費類別。

方法 B 讓 AI 讀全部欄位，只是為了比較：如果 AI 直接看照片其實更準，之後可以考慮讓它當「第二意見」，
例如規則讀不到時，把 AI 的答案標成紅字請使用者確認。

## 3. 規則怎麼判斷（Rules.swift）

| 欄位 | 怎麼找 | 例子 |
|---|---|---|
| 日期 | 2026-10-10、2026/10/13、2026.10.14、2026년 10월 11일、26/10/11、26-10-12；也接受文字辨識讀錯的 202610~12、2026-1013、2026-10-1112:56 | 優先用「同一行後面就有時間」的日期，避開退換貨期限這類日期 |
| 時間 | 日期後面的「時:分」 | `2026-10-10 18:14:59` → 18:14 |
| 金額 | 有關鍵字的那一行，取最大的金額（那一行沒數字就看下一行）；關鍵字有先後順序 | 면세환급후 → 승인금액 → 결제금액 → Payment amount … → 합계 → Total |
| 金額（稅金檢查） | 有好幾個候選時，優先選收據上找得到「稅金≈總額÷11」或「未稅≈總額−稅金」的 | 照片拍歪讓「승인금액」對到稅金 5,544 時，仍會選對得上稅金的 61,000 |
| 金額（排除） | 含 부가세、할인、Refund、Tax total、공급가、匯率（EXCHANGE、JPY）等字的行不算 | 退稅單上的「合計稅額 6,952」不會被當成消費金額 |
| 卡號前 6 碼 | 「4 位數＋2 位數」後面接著 `*` 號（被讀成 # ※ x 也算） | `5483-68**`、`548368*****`、`4147-63**` |
| 付款方式 | LINE Pay／라인페이 → LINE Pay；현금且沒有卡號 → 現金；其他有卡號 → 刷卡 | |

收據常把「합 계」的字距拉開，所以比對關鍵字前會先去掉空白、轉小寫。

**照片方向**：先把照片當成正的讀；讀不到日期或金額時，再當成倒過來、向右轉、向左轉各讀一次，
取規則讀到最多欄位的那一次（`OCR.recognizeBestOrientation`）。第一次實測就有一張正放的收據被 Vision 讀成倒過來的字。

文字辨識會把「左邊標籤、右邊數字」拆成兩段，`OCR.rows` 依上下位置把同一橫排接回一行。
照片拍歪時，標籤和數字可能被分到不同行，這是規則讀錯的可能原因之一，報告裡會附上原始辨識內容方便檢查。

## 4. 用到的技術

| 技術 | 用途 | 說明 |
|---|---|---|
| Vision（`VNRecognizeTextRequest`） | 文字辨識 | macOS 內建，支援韓文；用「精準」模式 |
| Foundation Models（`LanguageModelSession`） | 裝置端 AI | macOS 內建的 Apple Intelligence 模型，需要開啟 Apple Intelligence |
| `NSRegularExpression` | 規則比對 | 正規表示式：描述「文字長什麼樣子」的寫法 |
| Swift 命令列工具 | 測試工具本身 | 只用命令列開發者工具編譯，不需要 Xcode |

**為什麼不用 `@Generable`**：Foundation Models 最方便的寫法要用 Swift 巨集，只有命令列開發者工具時可能編譯不過
（作者的另一個專案就遇過 SwiftUI 的 `@State` 編譯失敗）。所以改成請 AI 回傳 JSON 文字，再由程式解析。

**方法 B 的寫法還沒確認**：「AI 直接看圖片」是 macOS 27 的新功能，寫法是依公告推測的。
`scripts/build.sh` 會先試著連方法 B 一起編譯，失敗就改成只編譯方法 A，
並把 SDK 裡和圖片有關的寫法存到 `build/fm_image_api.txt`，下一版再依此修正。

## 5. 檔案一覽

| 檔案 | 內容 |
|---|---|
| `Sources/Probe/main.swift` | 測試工具的主流程：讀照片、跑兩種方法、寫報告 |
| `Sources/Probe/OCR.swift` | 文字辨識、同一橫排接成一行 |
| `Sources/Probe/Rules.swift` | 規則：日期、時間、金額、卡號前 6 碼、付款方式 |
| `Sources/Probe/AI.swift` | 裝置端 AI：方法 A 的文字整理、方法 B 的直接看照片、解析 AI 回傳的 JSON |
| `Sources/Probe/Report.swift` | 和標準答案比對、寫成 Markdown／CSV／JSON 報告 |
| `Sources/Probe/SelfTest.swift` | 規則的自我測試（假資料） |
| `scripts/build.sh` | 編譯 |
| `scripts/selftest.sh` | 自我測試 |
| `收據測試.command` | 雙擊執行：編譯＋自我測試＋跑收據＋打開報告 |
| `private/`（不上傳） | 真實收據照片、標準答案 `expected.json`、測試報告 |

## 6. 標準答案的格式（private/expected.json）

一張收據一筆，`file` 對應 `private/receipts/` 裡的檔名。下面是假資料範例：

```json
[
  {
    "file": "r01.jpg",
    "date": "2026-10-10",
    "time": "18:14",
    "amount": 30500,
    "cardPrefix": "541234",
    "pay": "card",
    "store": "가상상점",
    "nameZh": "假商店-飲料2杯",
    "category": "食"
  }
]
```

- `amount`：實際付款的原幣金額（整數，不含逗號）；退稅單寫「結帳金額」，不是退稅前的總額。
- `cardPrefix`、`pay`：收據上沒有印的寫 `null`，這一欄就不計分。
- `pay`：`card`（刷卡）、`linepay`（LINE Pay）、`cash`（現金）。

## 7. 設計決定

- **報告只存在本機**：報告裡有真實的店家、金額和收據原文，所以寫在 `private/results/`，`.gitignore` 會排除。
- **自我測試用假資料**：`SelfTest.swift` 的收據文字是照真實收據格式編的，卡號用常見的測試號碼。
- **照片只讀不寫**：測試工具不會修改、移動或刪除任何照片。
