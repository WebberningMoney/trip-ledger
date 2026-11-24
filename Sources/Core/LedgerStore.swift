// LedgerStore.swift：把帳本存到電腦裡、讀回來。
//
// 所有資料都在這個資料夾（只在這台 Mac 上，不會上傳）：
//   ~/Library/Application Support/TripLedger/
//   ├── trips/<行程編號>.json      每個行程一個檔（消費明細）
//   ├── photos/<行程編號>/...     匯入時複製進來的收據照片（原始照片不會被修改）
//   └── merchants.json            記住的店家（使用者改過的店名與類別）
//
// 刪除行程或消費時，只刪 App 自己複製的照片，絕不碰使用者原本的照片。

import Foundation

enum LedgerStore {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TripLedger", isDirectory: true)
    }
    static var tripsDir: URL { root.appendingPathComponent("trips", isDirectory: true) }
    static var photosRoot: URL { root.appendingPathComponent("photos", isDirectory: true) }
    static var merchantsFile: URL { root.appendingPathComponent("merchants.json") }

    static func photosDir(for trip: Trip) -> URL {
        photosRoot.appendingPathComponent(trip.id.uuidString, isDirectory: true)
    }

    static func photoURL(_ receipt: Receipt, in trip: Trip) -> URL {
        photosDir(for: trip).appendingPathComponent(receipt.photoFile)
    }

    static func ensureFolders() {
        for dir in [root, tripsDir, photosRoot] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - 行程

    static func loadTrips() -> [Trip] {
        ensureFolders()
        let files = (try? FileManager.default.contentsOfDirectory(at: tripsDir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Trip.self, from: Data(contentsOf: $0)) }
            .sorted { $0.created > $1.created }
    }

    static func save(_ trip: Trip) {
        ensureFolders()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(trip) else { return }
        try? data.write(to: tripsDir.appendingPathComponent(trip.id.uuidString + ".json"), options: .atomic)
    }

    /// 刪除行程：行程檔和 App 複製的照片（使用者原本的照片不受影響）。
    static func delete(_ trip: Trip) {
        try? FileManager.default.removeItem(at: tripsDir.appendingPathComponent(trip.id.uuidString + ".json"))
        try? FileManager.default.removeItem(at: photosDir(for: trip))
    }

    /// 刪除一筆消費時，刪掉 App 複製的那張照片。
    static func deletePhoto(_ receipt: Receipt, in trip: Trip) {
        try? FileManager.default.removeItem(at: photoURL(receipt, in: trip))
    }

    // MARK: - 照片

    /// 把照片複製到 App 的資料夾（原始照片只讀取、不修改），回傳新檔名。
    static func copyPhoto(from source: URL, into trip: Trip, id: UUID) throws -> String {
        let dir = photosDir(for: trip)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension.lowercased()
        let name = id.uuidString + "." + ext
        try FileManager.default.copyItem(at: source, to: dir.appendingPathComponent(name))
        return name
    }

    /// 從「照片」App 挑的照片是資料（不是檔案），直接寫一份到 App 的資料夾。
    static func writePhoto(_ data: Data, ext: String, into trip: Trip, id: UUID) throws -> String {
        let dir = photosDir(for: trip)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = id.uuidString + "." + (ext.isEmpty ? "jpg" : ext)
        try data.write(to: dir.appendingPathComponent(name))
        return name
    }

    // MARK: - 記住的店家

    static func loadMerchants() -> [String: MerchantInfo] {
        guard let data = try? Data(contentsOf: merchantsFile),
              let map = try? JSONDecoder().decode([String: MerchantInfo].self, from: data) else { return [:] }
        return map
    }

    static func saveMerchants(_ map: [String: MerchantInfo]) {
        ensureFolders()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(map) else { return }
        try? data.write(to: merchantsFile, options: .atomic)
    }

    // MARK: - 匯出檔名

    /// 檔名重複時自動加上編號（例如「2026 釜山 2.xlsx」），絕不覆蓋已有的檔案。
    static func uniqueURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            let candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
