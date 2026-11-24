// TripLedgerApp.swift：App 的入口。開一個視窗，裡面是 ContentView。
//
// 選單列「檔案 → 新增行程…」（⌘N）可以建立新行程。

import SwiftUI
import PhotosUI

/// 畫面上的暫時狀態（哪個視窗要打開、正在確認刪除哪一筆…）。
/// 因為只有命令列開發者工具，不能用 @State，所以集中放在這個物件裡。
final class UIState: ObservableObject {
    @Published var showNewTrip = false
    @Published var newTripName = ""
    @Published var renameTripID: UUID? = nil
    @Published var renameText = ""
    @Published var tripToDelete: UUID? = nil
    @Published var receiptToDelete: UUID? = nil
    @Published var receiptToReread: UUID? = nil
    @Published var showImporter = false
    @Published var photoItems: [PhotosPickerItem] = []
}

@main
struct TripLedgerApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var ui = UIState()

    var body: some Scene {
        WindowGroup("TripLedger 旅帳本") {
            ContentView()
                .environmentObject(model)
                .environmentObject(ui)
                .frame(minWidth: 1100, minHeight: 650)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新增行程…") { ui.showNewTrip = true }
                    .keyboardShortcut("n")
            }
        }
    }
}
