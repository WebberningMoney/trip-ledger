// ContentView.swift：主畫面。
//
// ┌ 行程（左）┬ 消費表格（中，和花費表一樣） ┬ 收據照片＋可修改的欄位（右）┐
//
// - 左邊：行程清單。按右鍵可以重新命名或刪除；左下角「新增行程」。
// - 中間：這個行程的每一筆消費。需要確認的那筆「項目」是紅字。可以把照片或資料夾直接拖進來匯入。
// - 右邊：見 ReceiptInspector.swift。
// - 上方工具列：匯入照片、從「照片」App 挑選、匯出 Excel。

import SwiftUI
import PhotosUI
import Translation
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var ui: UIState

    var body: some View {
        NavigationSplitView {
            TripSidebar()
                .navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } content: {
            ReceiptTable()
                .navigationSplitViewColumnWidth(min: 520, ideal: 640)
        } detail: {
            ReceiptInspector()
        }
        .toolbar {
            ToolbarItemGroup {
                if model.isProcessing || !model.progressText.isEmpty {
                    ProgressView().controlSize(.small)
                    Text(model.progressText).font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    ui.showImporter = true
                } label: {
                    Label("匯入照片…", systemImage: "square.and.arrow.down")
                }
                .help("選擇收據照片或整個資料夾匯入到目前的行程。原始照片不會被修改，App 會複製一份。")
                .disabled(model.currentTrip == nil)

                PhotosPicker(selection: $ui.photoItems, matching: .images) {
                    Label("從「照片」挑選", systemImage: "photo.on.rectangle")
                }
                .help("從 Mac 的「照片」App 挑選收據照片（iPhone 拍的照片有開 iCloud 同步就會在這裡）。")
                .disabled(model.currentTrip == nil)

                Button {
                    model.exportCurrentTrip()
                } label: {
                    Label("匯出 Excel…", systemImage: "tablecells")
                }
                .help("把這個行程匯出成 Excel 檔。需要確認的那筆會用紅字，不會覆蓋已有的檔案。")
                .disabled(model.currentTrip?.receipts.isEmpty ?? true)
            }
        }
        .fileImporter(isPresented: $ui.showImporter,
                      allowedContentTypes: [.image, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importFiles(urls) }
        }
        .onChange(of: ui.photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [(data: Data, ext: String)] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                        loaded.append((data: data, ext: ext))
                    }
                }
                ui.photoItems = []
                model.importPhotoData(loaded)
            }
        }
        .translationTask(model.translationConfig) { session in
            await model.runTranslations(session)
        }
        .alert("新增行程", isPresented: $ui.showNewTrip) {
            TextField("行程名稱（例：2026 釜山）", text: $ui.newTripName)
            Button("建立") {
                model.addTrip(name: ui.newTripName)
                ui.newTripName = ""
            }
            Button("取消", role: .cancel) { ui.newTripName = "" }
        }
        .alert("重新命名行程", isPresented: Binding(get: { ui.renameTripID != nil },
                                                set: { if !$0 { ui.renameTripID = nil } })) {
            TextField("行程名稱", text: $ui.renameText)
            Button("儲存") {
                if let id = ui.renameTripID { model.renameTrip(id, to: ui.renameText) }
                ui.renameTripID = nil
            }
            Button("取消", role: .cancel) { ui.renameTripID = nil }
        }
        .confirmationDialog("確定要刪除這個行程嗎？",
                            isPresented: Binding(get: { ui.tripToDelete != nil },
                                                 set: { if !$0 { ui.tripToDelete = nil } }),
                            presenting: ui.tripToDelete) { id in
            Button("刪除行程", role: .destructive) { model.deleteTrip(id) }
        } message: { _ in
            Text("會刪除這個行程的所有消費紀錄，以及 App 複製的收據照片。你原本的照片不會被刪除。這個動作無法復原。")
        }
        .confirmationDialog("確定要刪除這筆消費嗎？",
                            isPresented: Binding(get: { ui.receiptToDelete != nil },
                                                 set: { if !$0 { ui.receiptToDelete = nil } }),
                            presenting: ui.receiptToDelete) { id in
            Button("刪除", role: .destructive) { model.deleteReceipt(id) }
        } message: { _ in
            Text("會刪除這筆紀錄和 App 複製的收據照片。你原本的照片不會被刪除。這個動作無法復原。")
        }
        .confirmationDialog("要重新辨識這張收據嗎？",
                            isPresented: Binding(get: { ui.receiptToReread != nil },
                                                 set: { if !$0 { ui.receiptToReread = nil } }),
                            presenting: ui.receiptToReread) { id in
            Button("重新辨識") { model.reread(id) }
        } message: { _ in
            Text("會重新讀這張照片，你在這筆改過的欄位都會被覆蓋（記住的店家不受影響）。")
        }
        .alert("提醒", isPresented: Binding(get: { model.message != nil },
                                          set: { if !$0 { model.message = nil } })) {
            Button("好") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
    }
}

// MARK: - 左邊：行程清單

struct TripSidebar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var ui: UIState

    var body: some View {
        List(selection: $model.selectedTripID) {
            Section("行程") {
                ForEach(model.trips) { trip in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.name)
                        Text("\(trip.receipts.count) 筆")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(trip.id))
                    .contextMenu {
                        Button("重新命名…") {
                            ui.renameText = trip.name
                            ui.renameTripID = trip.id
                        }
                        Button("刪除行程…", role: .destructive) { ui.tripToDelete = trip.id }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                ui.showNewTrip = true
            } label: {
                Label("新增行程", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("建立一個新的行程，例如「2026 釜山」。")
        }
    }
}

// MARK: - 中間：消費表格

struct ReceiptTable: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var ui: UIState

    var body: some View {
        if let trip = model.currentTrip {
            let rows = trip.sortedReceipts
            let numbers = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0 + 1) })
            VStack(spacing: 0) {
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label("還沒有收據", systemImage: "doc.text.viewfinder")
                    } description: {
                        Text("按上方「匯入照片…」或「從「照片」挑選」，也可以直接把照片或資料夾拖到這裡。")
                    }
                } else {
                    Table(rows, selection: $model.selectedReceiptID) {
                        TableColumn("#") { (r: Receipt) in
                            Text("\(numbers[r.id] ?? 0)").foregroundStyle(.secondary)
                        }
                        .width(30)
                        TableColumn("日期") { (r: Receipt) in Text(Self.shortDate(r.date)) }
                            .width(48)
                        TableColumn("時間") { (r: Receipt) in Text(r.time ?? "") }
                            .width(44)
                        TableColumn("項目") { (r: Receipt) in
                            Text(Self.rowTitle(r))
                                .foregroundStyle(r.needsReview ? Color.red : Color.primary)
                                .help(r.needsReview ? "待確認：" + r.problems.joined(separator: "、") : r.title)
                        }
                        TableColumn("付款") { (r: Receipt) in Text(PayMethod.label(r.pay)) }
                            .width(66)
                        TableColumn("金額") { (r: Receipt) in
                            Text(r.amount.map { $0.formatted() } ?? "").monospacedDigit()
                        }
                        .width(76)
                        TableColumn("分類") { (r: Receipt) in Text(r.category ?? "") }
                            .width(36)
                    }
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        if let id = ids.first {
                            Button("重新辨識…") { ui.receiptToReread = id }
                            Button("刪除這筆…", role: .destructive) { ui.receiptToDelete = id }
                        }
                    }
                }
                Divider()
                footer(trip)
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.importFiles(urls)
                return true
            }
            .navigationTitle(trip.name)
        } else {
            ContentUnavailableView {
                Label("還沒有行程", systemImage: "suitcase")
            } description: {
                Text("按左下角「新增行程」開始，例如「2026 釜山」。")
            }
        }
    }

    private func footer(_ trip: Trip) -> some View {
        let total = trip.receipts.compactMap { $0.amount }.reduce(0, +)
        let review = trip.receipts.filter { $0.needsReview }.count
        return HStack {
            Text("\(trip.receipts.count) 筆")
            if review > 0 {
                Text("・\(review) 筆待確認").foregroundStyle(.red)
                    .help("紅字的消費有欄位讀不到，或店名、類別是自動判斷的。點一下那筆，在右邊確認或修改。")
            }
            Spacer()
            Text("合計 \(trip.currency) \(total.formatted())").monospacedDigit()
                .help("目前所有消費的原幣金額加總（讀不到金額的不算）。")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    static func shortDate(_ date: String?) -> String {
        guard let date = date else { return "" }
        let parts = date.split(separator: "-").compactMap { Int($0) }
        return parts.count == 3 ? "\(parts[1])/\(parts[2])" : date
    }

    static func rowTitle(_ r: Receipt) -> String {
        switch r.status {
        case "waiting": return "等待辨識…"
        case "reading": return "辨識中…"
        case "failed": return "照片讀不到（\(r.originalName)）"
        default: return r.title
        }
    }
}
