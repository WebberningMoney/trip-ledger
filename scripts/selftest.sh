#!/bin/bash
# selftest.sh：自我測試。目前只檢查「規則」有沒有把假收據文字的日期、時間、金額、卡號、付款方式讀對。
# 不需要照片、不呼叫 AI。要先執行 scripts/build.sh。

cd "$(dirname "$0")/.." || exit 1
if [ ! -x build/receipt-probe ]; then
  echo "找不到 build/receipt-probe，請先執行：bash scripts/build.sh"
  exit 1
fi
build/receipt-probe --selftest 2>&1 | tee build/selftest_log.txt
exit "${PIPESTATUS[0]}"
