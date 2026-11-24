// AppModel.swift：App 的「大腦」——保存目前的行程、處理匯入、修改、記住店家、翻譯和匯出。
//
// 畫面（ContentView.swift）只負責顯示和把使用者的動作交給這裡。
// 因為只有命令列開發者工具（沒有 Xcode），這裡用 ObservableObject＋@Published，不用 @Observable 巨集。
//
// 匯入流程：照片先複製到 App 的資料夾（原始照片只讀不改）→ 列在表格上顯示「辨識中」→
// 一張一張交給 ReceiptReader 讀 → 讀完存檔 → 需要翻譯店名的，交給 Mac 內建翻譯。

import Foundation
import SwiftUI
import Translation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var selectedTripID: UUID? = nil {
        didSet { if oldValue != selectedTripID { selectedReceiptID = nil } }
    }
    @Published var selectedReceiptID: UUID? = nil
    @Published var isProcessing = false
    @Published var progressText = ""
    @Published var message: String? = nil
    /// 需要翻譯時設定；畫面上的 .translationTask 看到它就會開始翻譯（第一次會跳出下載語言包的視窗）。
    @Published var translationConfig: TranslationSession.Configuration? = nil

    private var memory: [String: MerchantInfo] = LedgerStore.loadMerchants()
    private let chains: [ChainEntry] = Merchants.loadChains()
    private var queue: [(tripID: UUID, receiptID: UUID)] = []

    init() {
        trips = LedgerStore.loadTrips()
        selectedTripID = trips.first?.id
        // 上次關掉 App 時還沒辨識完的，重新排隊。
        for trip in trips {
            for r in trip.receipts where r.status == "waiting" || r.status == "reading" {
                queue.append((tripID: trip.id, receiptID: r.id))
            }
        }
        if !queue.isEmpty { Task { await processQueue() } }
        requestTranslationIfNeeded()
    }

    // MARK: - 目前選到的東西

    var currentTrip: Trip? {
        guard let id = selectedTripID else { return nil }
        return trips.first { $0.id == id }
    }

    var currentReceipt: Receipt? {
        guard let trip = currentTrip, let id = selectedReceiptID else { return nil }
        return trip.receipts.first { $0.id == id }
    }

    private func tripIndex(_ id: UUID) -> Int? { trips.firstIndex { $0.id == id } }

    private func update(tripID: UUID, receiptID: UUID, _ change: (inout Receipt) -> Void) {
        guard let t = tripIndex(tripID), let r = trips[t].receipts.firstIndex(where: { $0.id == receiptID }) else { return }
        change(&trips[t].receipts[r])
        LedgerStore.save(trips[t])
    }

    // MARK: - 行程

    func addTrip(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trip = Trip(name: clean.isEmpty ? "新的行程" : clean)
        trips.insert(trip, at: 0)
        LedgerStore.save(trip)
        selectedTripID = trip.id
        selectedReceiptID = nil
    }

    func renameTrip(_ id: UUID, to name: String) {
        guard let t = tripIndex(id) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        trips[t].name = clean
        LedgerStore.save(trips[t])
    }

    /// 刪除行程（畫面上會先請使用者確認）。只刪 App 自己的資料，原始照片不受影響。
    func deleteTrip(_ id: UUID) {
        guard let t = tripIndex(id) else { return }
        LedgerStore.delete(trips[t])
        trips.remove(at: t)
        queue.removeAll { $0.tripID == id }
        if selectedTripID == id { selectedTripID = trips.first?.id }
    }

    /// 刪除一筆消費（畫面上會先請使用者確認）。只刪 App 複製的那張照片。
    func deleteReceipt(_ receiptID: UUID) {
        guard let trip = currentTrip, let t = tripIndex(trip.id),
              let r = trips[t].receipts.firstIndex(where: { $0.id == receiptID }) else { return }
        LedgerStore.deletePhoto(trips[t].receipts[r], in: trips[t])
        trips[t].receipts.remove(at: r)
        LedgerStore.save(trips[t])
        queue.removeAll { $0.receiptID == receiptID }
        if selectedReceiptID == receiptID { selectedReceiptID = nil }
    }

    // MARK: - 匯入

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff"]

    /// 匯入檔案或資料夾（資料夾會找出裡面所有的照片）。
    func importFiles(_ urls: [URL]) {
        guard let trip = currentTrip else {
            message = "請先在左邊建立或選擇一個行程。"
            return
        }
        var photos: [URL] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                photos += items.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else if Self.imageExtensions.contains(url.pathExtension.lowercased()) {
                photos.append(url)
            }
        }
        var added = 0
        for photo in photos {
            let scoped = photo.startAccessingSecurityScopedResource()
            defer { if scoped { photo.stopAccessingSecurityScopedResource() } }
            let id = UUID()
            guard let file = try? LedgerStore.copyPhoto(from: photo, into: trip, id: id) else { continue }
            addReceipt(Receipt(id: id, photoFile: file, originalName: photo.lastPathComponent), to: trip.id)
            added += 1
        }
        if added == 0 { message = "沒有找到可以匯入的照片（支援 JPG、PNG、HEIC）。" }
        Task { await processQueue() }
    }

    /// 匯入從「照片」App 挑選的照片。
    func importPhotoData(_ items: [(data: Data, ext: String)]) {
        guard let trip = currentTrip else {
            message = "請先在左邊建立或選擇一個行程。"
            return
        }
        for (index, item) in items.enumerated() {
            let id = UUID()
            guard let file = try? LedgerStore.writePhoto(item.data, ext: item.ext, into: trip, id: id) else { continue }
            addReceipt(Receipt(id: id, photoFile: file, originalName: "照片 \(index + 1)"), to: trip.id)
        }
        Task { await processQueue() }
    }

    private func addReceipt(_ receipt: Receipt, to tripID: UUID) {
        guard let t = tripIndex(tripID) else { return }
        trips[t].receipts.append(receipt)
        LedgerStore.save(trips[t])
        queue.append((tripID: tripID, receiptID: receipt.id))
    }

    /// 重新辨識一筆（例如想用新版規則再讀一次）。使用者改過的欄位會被覆蓋，畫面上會先請使用者確認。
    func reread(_ receiptID: UUID) {
        guard let trip = currentTrip else { return }
        update(tripID: trip.id, receiptID: receiptID) { r in
            r = Receipt(id: r.id, photoFile: r.photoFile, originalName: r.originalName, imported: r.imported)
        }
        queue.append((tripID: trip.id, receiptID: receiptID))
        Task { await processQueue() }
    }

    /// 一張一張辨識排隊中的收據。
    func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false; progressText = "" }
        var done = 0
        while !queue.isEmpty {
            let job = queue.removeFirst()
            guard let t = tripIndex(job.tripID),
                  let receipt = trips[t].receipts.first(where: { $0.id == job.receiptID }) else { continue }
            done += 1
            progressText = "辨識中：第 \(done) 張，還有 \(queue.count) 張"
            update(tripID: job.tripID, receiptID: job.receiptID) { $0.status = "reading" }
            let url = LedgerStore.photoURL(receipt, in: trips[t])
            var result = await ReceiptReader.read(photo: url, receipt: receipt, memory: memory, chains: chains, useAI: true)
            result.status = result.status == "failed" ? "failed" : "done"
            update(tripID: job.tripID, receiptID: job.receiptID) { $0 = result }
        }
        requestTranslationIfNeeded()
    }

    // MARK: - 修改

    /// 修改一筆消費的欄位。改了店名或類別時，會記住這家店，並套用到同一家店、還沒確認過的其他筆。
    func edit(_ receiptID: UUID, _ change: (inout Receipt) -> Void) {
        guard let trip = currentTrip else { return }
        let before = trip.receipts.first { $0.id == receiptID }
        update(tripID: trip.id, receiptID: receiptID, change)
        guard let before = before, let after = currentTrip?.receipts.first(where: { $0.id == receiptID }) else { return }
        if before.itemsZh != after.itemsZh {
            update(tripID: trip.id, receiptID: receiptID) { $0.itemsFromAI = nil }
        }
        if before.storeZh != after.storeZh || before.category != after.category {
            remember(after)
        }
    }

    /// 按「確認」：這筆的店名和類別視為正確，並記住這家店。
    func confirm(_ receiptID: UUID) {
        edit(receiptID) { $0.confirmed = true }
        if let r = currentTrip?.receipts.first(where: { $0.id == receiptID }) { remember(r) }
    }

    private func remember(_ receipt: Receipt) {
        guard let name = receipt.storeZh?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
        let info = MerchantInfo(storeZh: name, category: receipt.category)
        let keys = Merchants.memoryKeys(businessNumber: receipt.businessNumber, storeKo: receipt.storeKo)
        guard !keys.isEmpty else { return }
        for key in keys { memory[key] = info }
        LedgerStore.saveMerchants(memory)
        if let t = tripIndex(selectedTripID ?? UUID()) {
            if let own = trips[t].receipts.firstIndex(where: { $0.id == receipt.id }) {
                trips[t].receipts[own].nameSource = "user"
            }
            // 同一家店、還沒確認過的其他筆，一起套用。
            for i in trips[t].receipts.indices where trips[t].receipts[i].id != receipt.id && !trips[t].receipts[i].confirmed {
                let otherKeys = Merchants.memoryKeys(businessNumber: trips[t].receipts[i].businessNumber,
                                                     storeKo: trips[t].receipts[i].storeKo)
                if !Set(otherKeys).isDisjoint(with: keys) {
                    trips[t].receipts[i].storeZh = info.storeZh
                    trips[t].receipts[i].category = info.category
                    trips[t].receipts[i].nameSource = "memory"
                }
            }
            LedgerStore.save(trips[t])
        }
    }

    // MARK: - 翻譯（Mac 內建，第一次會跳出下載語言包的視窗）

    private var pendingTranslations: [(tripID: UUID, receiptID: UUID, text: String)] {
        trips.flatMap { trip in
            trip.receipts.filter { $0.nameSource == "translation" && $0.storeZh == nil && $0.storeKo != nil }
                .map { (tripID: trip.id, receiptID: $0.id, text: $0.storeKo ?? "") }
        }
    }

    func requestTranslationIfNeeded() {
        guard !pendingTranslations.isEmpty else { return }
        if translationConfig == nil {
            translationConfig = TranslationSession.Configuration(source: Locale.Language(identifier: "ko"),
                                                                 target: Locale.Language(identifier: "zh-Hant"))
        } else {
            translationConfig?.invalidate()
        }
    }

    /// 由畫面上的 .translationTask 呼叫。
    func runTranslations(_ session: TranslationSession) async {
        let jobs = pendingTranslations
        guard !jobs.isEmpty else { return }
        progressText = "翻譯店名中（\(jobs.count) 筆）…"
        defer { if !isProcessing { progressText = "" } }
        let requests = jobs.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.receiptID.uuidString) }
        do {
            let responses = try await session.translations(from: requests)
            for response in responses {
                guard let id = response.clientIdentifier.flatMap(UUID.init(uuidString:)),
                      let job = jobs.first(where: { $0.receiptID == id }) else { continue }
                update(tripID: job.tripID, receiptID: id) { r in
                    if r.storeZh == nil { r.storeZh = response.targetText }
                }
            }
        } catch {
            message = "店名翻譯沒有完成：\(error.localizedDescription)\n可以到「系統設定 → 一般 → 語言與地區 → 翻譯語言」下載韓文和繁體中文後再試。"
        }
    }

    // MARK: - 匯出

    func exportCurrentTrip() {
        guard let trip = currentTrip else { return }
        let panel = NSSavePanel()
        panel.title = "匯出 Excel"
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.nameFieldStringValue = trip.name + ".xlsx"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let written = try XLSXExport.export(trip, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([written])
        } catch {
            message = "匯出失敗：\(error)"
        }
    }
}
