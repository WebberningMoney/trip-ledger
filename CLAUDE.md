# 給 AI 助理（Claude 等）的協作守則

> 這份檔案是寫給「幫忙改這個專案的 AI 助理」看的。每次開始工作前請先讀完並照做。
> 一般使用者不需要看這份，請看 [README](README.md)。

## 1. 開始工作前：先設定 git

在這個專案資料夾執行：

```bash
git config core.hooksPath scripts/git-hooks      # 啟用專案內建的自動檢查
git config commit.gpgsign false                  # 不要自動簽章
git config user.name  "$(git log -1 --format=%an origin/main)"   # 作者＝專案擁有者（Webber Huang）
git config user.email "$(git log -1 --format=%ae origin/main)"
git config tripledger.owneremail "$(git log -1 --format=%ae origin/main)"
git config core.quotepath false                  # 讓中文檔名正常顯示
```

為什麼：

- **作者必須是專案擁有者**，AI 助理只放在 commit 訊息最後的 `Co-Authored-By:`。
  雲端沙盒的預設 git 身分是 Claude，在擁有者的其他專案曾讓一整串 commit 的作者都變成 Claude，事後得改寫歷史。
- **不要簽章**。沙盒會用它自己的金鑰簽 commit，那把金鑰沒有登記在擁有者的 GitHub 帳號，GitHub 會標成 **Unverified**。
- `scripts/git-hooks/` 的檢查會在 commit 和 push 前擋下上面兩種情況；推送後請再用
  `gh api repos/WebberningMoney/trip-ledger/commits --jq '.[0] | .author.login, .commit.verification.reason'` 確認（應為擁有者、`unsigned`）。
- 需要改寫歷史或強制推送時，**一定要先問擁有者**。

## 2. 每次改了程式或畫面：一定要重新檢查文件與註解

**每一次**變更程式碼或畫面，都要 review 並更新相關說明。請照這個順序做：

1. **程式註解**：改到的檔案，開頭那段白話說明還正確嗎？改到的函式，註解有沒有過時？
2. **畫面文字**：新增的選項有沒有用 `.help(...)` 加上滑鼠停留說明？提示文字是不是白話？
3. **README.md**：每天怎麼用、支援的銀行與幣別、分類說明、名詞小辭典、效果與限制、隱私、常見問題、檔案列表。
   - 畫面有變時，示意圖也要更新。
     **README 一律用示意圖**：真的截圖會露出擁有者的消費紀錄、卡號、店家與行程等個人資料，不要拿擁有者傳來的截圖放進 README。
     只有擁有者明確提供「用假資料拍的截圖」並同意放上去時，才換成真的截圖。
4. **docs/ARCHITECTURE.md**：Mermaid 架構圖／流程圖、比對規則怎麼判斷、用到哪些技術、檔案一覽、設計決定。
   改完圖請確認 GitHub 上能正常顯示（語法錯誤時 GitHub 會顯示錯誤訊息）。
5. **CHANGELOG.md**：在 `[Unreleased]` 記下這次改了什麼（用使用者看得懂的話）。
6. **測試**：在 Mac 上執行 `bash scripts/build.sh && bash scripts/selftest.sh`（發佈新版時也會自動跑）。

commit 時如果改了程式卻沒有動到任何文件，`pre-commit` 會擋下來。

## 3. 寫作風格

- 所有文件、註解、畫面文字都用**繁體中文**，而且要**最白話**：讓沒有程式或會計背景的人也能輕鬆看懂。
- 專業名詞第一次出現要解釋，或改用白話說法（例：OCR →「文字辨識（從照片讀出字）」、reconcile →「對帳」）。
- 判斷與建議一律寫成「可能」「可以試試」，不要把推測寫成定論。
  **沒有在真的 Mac 上量過的數字（辨識正確率、速度）不要寫成事實。**
- 畫面要簡單乾淨：細節收進說明文字或 README。

## 4. 工作方式

- 需求有疑問時，**先跟擁有者釐清再動手寫程式**。
- 這個專案只能在 Mac（Apple 晶片、macOS 27 以上、已開啟 Apple Intelligence）上編譯和執行：
  文字辨識（Vision）、裝置端 AI（Foundation Models）、翻譯（Translation）都是 macOS 內建功能，
  雲端沙盒（Linux）**沒辦法編譯也沒辦法測試**。修改後要誠實說明「哪些已在 Mac 上驗證、哪些還沒有」，
  並請擁有者執行 `bash scripts/build.sh && bash scripts/selftest.sh`，或讀取 `build/build_log.txt` 確認結果。
- 擁有者的 Mac **只有「命令列開發者工具」，沒有完整 Xcode**：不要用需要 Xcode 外掛的 Swift 巨集
  （SwiftUI 的 `@State`、`@Observable`、`@Bindable`、`#Preview`，SwiftData 的 `@Model`，Foundation Models 的 `@Generable`、`@Guide` 等）。
  - 畫面狀態請用 `ObservableObject`＋`@Published`＋`@StateObject`。
  - 裝置端 AI 請 AI 回傳 JSON，再用 `Codable` 解析並由程式檢查格式；解析失敗就當成「需要人工確認」。
  - 資料儲存用不需要巨集的方式（例如 `Codable` 存成 JSON 檔，或 SQLite）。
- 因為沙盒不能編譯，改 Swift 時要自己多檢查一次：**新加的函式有沒有放在對的型別（class／struct）裡**、呼叫的地方能不能找得到。
- **金額、日期、卡號前綴一律用程式規則讀取，不交給 AI 判斷**。AI 只負責店名翻譯、品項濃縮、消費分類這類文字工作；
  AI 的結果都要能在畫面上被使用者修改。
- **絕不修改、覆蓋或刪除使用者的原始檔案**（收據照片、對帳單 PDF）。匯入時只讀取；匯出一律寫成新檔，檔名重複時自動加上編號。
- **對帳單 PDF 的密碼只在當次使用，絕不儲存**（不寫入檔案、偏好設定或紀錄）。
- **銀行規則要集中管理**：每家銀行的對帳單格式與手續費規則放在各自的解析檔裡，README「支援的銀行」表格要同步更新。
  手續費規則要以真實對帳單驗證過才寫成事實。
- **測試資料不能有真實個資**：放進 `test/` 的收據與對帳單，必須是程式產生的假資料，或已完全遮蔽卡號、護照號碼、姓名、簽名、地址的檔案。
  擁有者傳來的真實收據只能在本機測試，**絕不 commit**。
- 這個工具**完全不連網**。若要新增任何對外連線（例如查匯率、查店家），先問擁有者，並寫進 README 的「隱私」一節。
- 不可復原的動作（例如刪除行程、解除安裝）在 App 和腳本裡都要有確認步驟。
