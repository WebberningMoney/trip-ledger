#!/bin/bash
# 解除安裝.command：雙擊移除 TripLedger。
#
# 會先問你確定要移除 App，再另外問要不要刪除帳本資料（預設不刪）。
# 你原本的收據照片在哪裡就在哪裡，不會被動到。

pause() { echo; read -n 1 -s -r -p "按任意鍵關閉這個視窗…"; echo; }
DATA="$HOME/Library/Application Support/TripLedger"

read -r -p "確定要從「應用程式」移除 TripLedger 嗎？(y/N) " answer
if [ "${answer}" != "y" ] && [ "${answer}" != "Y" ]; then echo "已取消。"; pause; exit 0; fi
rm -rf /Applications/TripLedger.app && echo "✅ 已移除 App。"

if [ -d "${DATA}" ]; then
  echo
  echo "帳本資料（行程、消費、App 複製的收據照片、記住的店家）在："
  echo "  ${DATA}"
  read -r -p "要一起刪除嗎？刪除後無法復原。(y/N) " answer
  if [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
    rm -rf "${DATA}" && echo "✅ 已刪除帳本資料。"
  else
    echo "保留帳本資料。之後重新安裝，資料還會在。"
  fi
fi
pause
