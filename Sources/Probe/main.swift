// main.swift：receipt-probe —— 階段 0 的收據辨識測試工具（命令列版）。
//
// 目的：在正式寫 App 之前，先確認「Mac 內建的文字辨識和 AI，讀韓文熱感紙收據到底準不準」。
// 做法：把一個資料夾裡的收據照片一張一張讀過，用兩種方法讀出欄位，再和標準答案比對、寫成報告。
//   方法 A：文字辨識（Vision）→ 規則讀日期／時間／金額／卡號（Rules.swift）→ AI 只取名稱和類別（AI.swift）
//   方法 B：照片直接交給 AI 讀全部欄位（只拿來比較，見 AI.swift 的說明）
//
// 用法（在專案資料夾執行；一般人雙擊「收據測試.command」即可）：
//   build/receipt-probe                          用 private/receipts 的照片、private/expected.json 的答案
//   build/receipt-probe 照片資料夾 --expected 答案.json --out 報告資料夾
//   build/receipt-probe --no-ai                  只測文字辨識＋規則（不呼叫 AI，比較快）
//   build/receipt-probe --limit 5                只測前 5 張
//   build/receipt-probe --selftest               只跑規則的自我測試（不需要照片）
//
// 照片只會被讀取，不會被修改。

import Foundation

let arguments = CommandLine.arguments

func option(_ flag: String) -> String? {
    guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

if arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

let valueFlags: Set<String> = ["--expected", "--out", "--limit"]
let positional = arguments.dropFirst().enumerated().filter { index, arg in
    !arg.hasPrefix("--") && !(index > 0 && valueFlags.contains(arguments[index]))
}.map { $0.element }

let receiptsDir = URL(fileURLWithPath: positional.first ?? "private/receipts")
let expectedURL = URL(fileURLWithPath: option("--expected") ?? "private/expected.json")
let outDir = URL(fileURLWithPath: option("--out") ?? "private/results")
let useAI = !arguments.contains("--no-ai")
let limit = option("--limit").flatMap { Int($0) }

// 標準答案（沒有也可以跑，只是不會計分）
var expectedByFile: [String: Expected] = [:]
if let data = try? Data(contentsOf: expectedURL) {
    do {
        for e in try JSONDecoder().decode([Expected].self, from: data) { expectedByFile[e.file] = e }
    } catch {
        print("⚠️ 讀不懂標準答案 \(expectedURL.path)：\(error)")
    }
} else {
    print("⚠️ 找不到標準答案 \(expectedURL.path)，這次只記錄讀到什麼、不計分")
}

// 照片清單
let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
guard let contents = try? FileManager.default.contentsOfDirectory(at: receiptsDir, includingPropertiesForKeys: nil) else {
    print("❌ 打不開照片資料夾：\(receiptsDir.path)")
    exit(1)
}
var images = contents.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
if let limit = limit { images = Array(images.prefix(limit)) }
if images.isEmpty {
    print("❌ \(receiptsDir.path) 裡沒有照片（支援 jpg、png、heic）")
    exit(1)
}

let aiReady = useAI && AI.isAvailable
let header = [
    "測試時間：\(Date())",
    "macOS：\(ProcessInfo.processInfo.operatingSystemVersionString)",
    "照片：\(images.count) 張（\(receiptsDir.path)）",
    "Vision 支援的語言：\(OCR.supportedLanguages().joined(separator: ", "))",
    "裝置端 AI：\(useAI ? (AI.isAvailable ? "可以使用" : "不能使用（\(AI.statusText)）") : "這次不使用（--no-ai）")",
    "方法 B（AI 直接看照片）：\(AI.imageInputCompiled ? "有編譯進來" : "這次沒有編譯進來（見 build/build_log.txt）")",
]
print(header.joined(separator: "\n"))
print("")

var results: [ReceiptResult] = []
for (index, url) in images.enumerated() {
    let name = url.lastPathComponent
    var result = ReceiptResult(file: name, expected: expectedByFile[name])
    print("[\(index + 1)/\(images.count)] \(name) …", terminator: "")
    fflush(stdout)

    guard let image = OCR.loadImage(url) else {
        result.ocrError = "打不開這張照片"
        results.append(result)
        print(" 打不開照片")
        continue
    }

    let start = Date()
    do {
        let ocr = try OCR.recognizeBestOrientation(image)
        result.ocrRows = ocr.rows
        result.ocrOrientation = ocr.orientation
    } catch {
        result.ocrError = "\(error)"
    }
    result.ocrSeconds = Date().timeIntervalSince(start)
    result.rules = Rules.extract(rows: result.ocrRows)

    if aiReady {
        if !result.ocrRows.isEmpty { result.aiText = await AI.describe(rows: result.ocrRows) }
        if AI.imageInputCompiled { result.aiImage = await AI.readImage(image) }
    }

    let r = result.rules
    if result.ocrOrientation != "正" { print("（照片方向：\(result.ocrOrientation)）", terminator: "") }
    print(" A：\(r.date ?? "?") \(r.time ?? "?") \(r.amount.map { String($0) } ?? "?") \(r.cardPrefix ?? "-") \(r.pay ?? "-")"
          + (result.aiText.fields.map { "｜\($0.storeZh ?? "?")-\($0.itemsZh ?? "?")（\($0.category ?? "?")）" } ?? ""))
    results.append(result)
}

do {
    try Report.write(results: results, header: header, to: outDir)
} catch {
    print("❌ 寫報告失敗：\(error)")
    exit(1)
}
