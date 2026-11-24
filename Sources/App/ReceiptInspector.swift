// ReceiptInspector.swift：右邊的面板——收據照片和可以修改的欄位。
//
// - 上半部是收據照片；按「用預覽程式打開」可以放大看。
// - 下半部是欄位。改完按「儲存」；按「確認這筆」代表這筆沒問題（紅字會消失）。
//   改了中文店名或類別，App 會記住這家店，下次遇到同一家店自動套用（同一個行程裡還沒確認的也會一起改）。
// - 規則讀不到日期、時間或金額時，會顯示「AI 看照片的猜測」，只供參考，要按按鈕才會填入。
// - 最下面可以展開「文字辨識讀到的內容」，方便對照。
//
// 因為只有命令列開發者工具（不能用 @State），編輯中的內容放在 Draft 這個物件裡。

import SwiftUI
import AppKit

/// 右邊面板正在編輯的內容（還沒按「儲存」前，不會改到帳本）。
final class Draft: ObservableObject {
    @Published var date = ""
    @Published var time = ""
    @Published var amount = ""
    @Published var cardPrefix = ""
    @Published var pay = ""
    @Published var storeZh = ""
    @Published var itemsZh = ""
    @Published var category = ""
    @Published var note = ""
    @Published var image: NSImage? = nil

    private(set) var sourceID: UUID? = nil
    private var snapshot: [String] = []

    var values: [String] { [date, time, amount, cardPrefix, pay, storeZh, itemsZh, category, note] }
    /// 使用者改了東西但還沒儲存。
    var isDirty: Bool { values != snapshot }

    func load(_ receipt: Receipt?, photo: URL?) {
        if receipt?.id != sourceID {
            image = photo.flatMap { NSImage(contentsOf: $0) }
        }
        sourceID = receipt?.id
        date = receipt?.date ?? ""
        time = receipt?.time ?? ""
        amount = receipt?.amount.map { String($0) } ?? ""
        cardPrefix = receipt?.cardPrefix ?? ""
        pay = receipt?.pay ?? ""
        storeZh = receipt?.storeZh ?? ""
        itemsZh = receipt?.itemsZh ?? ""
        category = receipt?.category ?? ""
        note = receipt?.note ?? ""
        snapshot = values
    }

    /// 格式不對時回傳白話的錯誤說明；沒問題回傳 nil。
    func validationError() -> String? {
        let d = date.trimmingCharacters(in: .whitespaces)
        if !d.isEmpty && d.range(of: #"^\d{4}-\d{1,2}-\d{1,2}$"#, options: .regularExpression) == nil {
            return "日期請寫成「2026-10-12」這樣的格式。"
        }
        let t = time.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty && t.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) == nil {
            return "時間請寫成「21:38」這樣的格式。"
        }
        let a = amount.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        if !a.isEmpty && Int(a) == nil {
            return "金額請只填數字（可以有逗號），例如「12,500」。"
        }
        return nil
    }

    /// 把編輯中的內容寫回這筆消費（先呼叫 validationError 確認格式）。
    func apply(to r: inout Receipt) {
        func clean(_ s: String) -> String? {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }
        if let d = clean(date) {
            let p = d.split(separator: "-").compactMap { Int($0) }
            r.date = String(format: "%04d-%02d-%02d", p[0], p[1], p[2])
        } else {
            r.date = nil
        }
        if let t = clean(time) {
            let p = t.split(separator: ":").compactMap { Int($0) }
            r.time = String(format: "%02d:%02d", p[0], p[1])
        } else {
            r.time = nil
        }
        r.amount = clean(amount.replacingOccurrences(of: ",", with: "")).flatMap { Int($0) }
        r.cardPrefix = clean(cardPrefix)
        r.pay = clean(pay)
        r.storeZh = clean(storeZh)
        r.itemsZh = clean(itemsZh)
        r.category = clean(category)
        r.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ReceiptInspector: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var ui: UIState
    @StateObject private var draft = Draft()

    var body: some View {
        Group {
            if let trip = model.currentTrip, let receipt = model.currentReceipt {
                content(trip: trip, receipt: receipt)
            } else {
                ContentUnavailableView {
                    Label("選一筆消費", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("點中間表格裡的一筆，這裡會顯示收據照片和可以修改的欄位。")
                }
            }
        }
        .onAppear { reload(force: true) }
        .onChange(of: model.selectedReceiptID) { _, _ in reload(force: true) }
        .onChange(of: model.currentReceipt) { _, _ in reload(force: false) }
    }

    /// 換了一筆就重新載入；同一筆的內容變了（例如辨識完成），只有在使用者沒有改到一半時才重新載入。
    private func reload(force: Bool) {
        let receipt = model.currentReceipt
        if !force && receipt?.id == draft.sourceID && draft.isDirty { return }
        let photo = model.currentTrip.flatMap { trip in receipt.map { LedgerStore.photoURL($0, in: trip) } }
        draft.load(receipt, photo: photo)
    }

    @ViewBuilder
    private func content(trip: Trip, receipt: Receipt) -> some View {
        VSplitView {
            photoView(trip: trip, receipt: receipt)
                .frame(minHeight: 200, idealHeight: 340)
            Form {
                if receipt.status == "waiting" || receipt.status == "reading" {
                    Section {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("辨識中…完成後欄位會自動填入。")
                        }
                    }
                }
                if !receipt.problems.isEmpty {
                    Section {
                        Text("待確認：" + receipt.problems.joined(separator: "、"))
                            .foregroundStyle(.red)
                    }
                }
                Section("店家") {
                    TextField("中文店名", text: $draft.storeZh)
                        .help("會顯示在「項目」欄的前半段。改了之後按「儲存」，App 會記住這家店。")
                    LabeledContent("收據上的店名", value: receipt.storeKo ?? "（讀不到）")
                    if let biz = receipt.businessNumber {
                        LabeledContent("營業登記號碼", value: biz)
                            .help("用來辨認同一家店。")
                    }
                    TextField("品項", text: $draft.itemsZh)
                        .help("會顯示在「項目」欄的後半段，例如「熬湯2碗+煎餃」。")
                    Picker("分類", selection: $draft.category) {
                        Text("—").tag("")
                        ForEach(SpendCategory.all, id: \.self) { c in
                            Text("\(c)（\(SpendCategory.help[c] ?? "")）").tag(c)
                        }
                    }
                    .help("改了之後按「儲存」，App 會記住這家店的分類。")
                    LabeledContent("店名來源", value: Self.sourceLabel(receipt.nameSource))
                }
                Section("日期與金額") {
                    TextField("日期", text: $draft.date, prompt: Text("2026-10-12"))
                    TextField("時間", text: $draft.time, prompt: Text("21:38"))
                    TextField("金額（\(trip.currency)）", text: $draft.amount, prompt: Text("12500"))
                }
                Section("付款") {
                    Picker("付款方式", selection: $draft.pay) {
                        Text("—").tag("")
                        ForEach(PayMethod.all, id: \.self) { p in Text(PayMethod.label(p)).tag(p) }
                    }
                    TextField("卡號前 6 碼", text: $draft.cardPrefix, prompt: Text("548368"))
                        .help("用來判斷是哪一張卡（之後和信用卡對帳單比對時會用到）。")
                }
                Section("備註") {
                    TextField("備註", text: $draft.note)
                }
                if let guess = receipt.secondOpinion {
                    Section("AI 看照片的猜測（只供參考）") {
                        Text("日期 \(guess.date ?? "—")　時間 \(guess.time ?? "—")　金額 \(guess.amount.map { String($0) } ?? "—")")
                            .font(.callout)
                        Text("階段 0 實測 AI 直接看照片的日期、金額常常讀錯，請對照照片再決定要不要用。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("把猜測填進空白的欄位") {
                            if draft.date.isEmpty, let d = guess.date { draft.date = d }
                            if draft.time.isEmpty, let t = guess.time { draft.time = t }
                            if draft.amount.isEmpty, let a = guess.amount { draft.amount = String(a) }
                        }
                        .help("只會填入目前空白的欄位，填完還要按「儲存」。")
                    }
                }
                Section {
                    HStack {
                        Button("儲存") { save(receipt) }
                            .keyboardShortcut("s")
                            .disabled(!draft.isDirty)
                            .help("儲存這筆的修改（⌘S）。")
                        Button("確認這筆") {
                            if save(receipt) { model.confirm(receipt.id) }
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("代表這筆的內容都正確，紅字會消失（⌘Return）。也會記住這家店的名稱和分類。")
                        Spacer()
                        Button("重新辨識…") { ui.receiptToReread = receipt.id }
                        Button("刪除…", role: .destructive) { ui.receiptToDelete = receipt.id }
                    }
                }
                Section {
                    DisclosureGroup("文字辨識讀到的內容") {
                        Text(receipt.ocrRows.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func photoView(trip: Trip, receipt: Receipt) -> some View {
        VStack(spacing: 6) {
            if let image = draft.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("沒有照片").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text(receipt.originalName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("用預覽程式打開") {
                    NSWorkspace.shared.open(LedgerStore.photoURL(receipt, in: trip))
                }
                .controlSize(.small)
                .help("在「預覽程式」打開這張收據，可以放大看清楚。")
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
    }

    /// 儲存；格式不對會跳出提醒並回傳 false。
    @discardableResult
    private func save(_ receipt: Receipt) -> Bool {
        if let error = draft.validationError() {
            model.message = error
            return false
        }
        model.edit(receipt.id) { draft.apply(to: &$0) }
        reload(force: true)
        return true
    }

    static func sourceLabel(_ source: String?) -> String {
        switch source {
        case "memory": return "記住的店家"
        case "chain": return "常見連鎖店清單"
        case "translation": return "翻譯收據上的店名"
        case "ai": return "AI 判斷"
        case "user": return "你改過的"
        default: return "—"
        }
    }
}
