# 更新紀錄

這裡記錄每一版改了什麼。格式參考 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)。

## [Unreleased]

### 新增
- **階段 0：收據辨識測試工具**（`收據測試.command`、`build/receipt-probe`）。
  在寫正式 App 之前，先測試 Mac 內建的文字辨識和 AI 讀韓文收據準不準：
  - 方法 A：文字辨識讀出收據上的字，再用固定規則讀日期、時間、金額、卡號前 6 碼、付款方式；AI 只負責店名翻譯、品項和消費類別。
  - 方法 B：照片直接交給 AI 讀全部欄位，拿來和方法 A 比較。
  - 和標準答案比對後，產生正確率報告（只存在自己的 Mac 上）。
- 規則的自我測試（`scripts/selftest.sh`），用假的收據文字檢查 7 種常見寫法。
- 編譯腳本 `scripts/build.sh`：只需要命令列開發者工具；方法 B 編譯不過時，會自動改成只編譯方法 A。
- 說明文件：README、`docs/ARCHITECTURE.md`、給 AI 助理的協作守則 `CLAUDE.md`。

### 尚未在 Mac 上驗證
- 以上程式都是在雲端寫的，**還沒有在真的 Mac 上編譯和執行過**。
