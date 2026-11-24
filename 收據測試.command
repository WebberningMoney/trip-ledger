#!/bin/bash
# 收據測試.command：雙擊執行「階段 0」的收據辨識測試。
#
# 會依序：① 編譯測試工具 ② 跑規則自我測試 ③ 讀 private/receipts 裡的每一張收據，
# 和 private/expected.json 的標準答案比對 ④ 打開報告 private/results/report-latest.md。
# 收據照片只會被讀取，不會被修改；報告只存在這台 Mac 的 private/ 裡，不會上傳到 GitHub。

cd "$(dirname "$0")" || exit 1
pause() { echo; read -n 1 -s -r -p "按任意鍵關閉這個視窗…"; echo; }

echo "① 編譯測試工具"
if ! bash scripts/build.sh; then pause; exit 1; fi

echo
echo "② 規則自我測試"
bash scripts/selftest.sh || echo "⚠️ 自我測試有題目沒通過，仍繼續跑收據測試。"

echo
if [ ! -d private/receipts ]; then
  echo "找不到 private/receipts 資料夾：請把收據照片放進去再執行一次。"
  pause; exit 1
fi
echo "③ 讀收據並比對標準答案（每張可能要幾秒到幾十秒）"
build/receipt-probe private/receipts --expected private/expected.json --out private/results 2>&1 | tee build/probe_log.txt

echo
echo "④ 打開報告"
open private/results/report-latest.md 2>/dev/null || echo "報告在 private/results/ 裡。"
pause
