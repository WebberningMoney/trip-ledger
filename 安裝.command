#!/bin/bash
# 安裝.command：雙擊安裝 TripLedger（開發版）。
#
# 會依序：① 編譯（scripts/build.sh）② 自我測試（scripts/selftest.sh）
# ③ 把 TripLedger 放進「應用程式」資料夾 ④ 打開它。
# 自我測試沒通過就不會安裝。之後正式版會改成從 GitHub Releases 下載，不需要自己編譯。

cd "$(dirname "$0")" || exit 1
pause() { echo; read -n 1 -s -r -p "按任意鍵關閉這個視窗…"; echo; }

echo "① 編譯"
if ! bash scripts/build.sh; then pause; exit 1; fi

echo
echo "② 自我測試"
if ! bash scripts/selftest.sh; then
  echo "❌ 自我測試沒通過，沒有安裝。請把 build/build_log.txt 和上面的畫面提供給開發者。"
  pause; exit 1
fi

echo
echo "③ 放進「應用程式」資料夾"
if [ -d /Applications/TripLedger.app ]; then
  echo "（已經有舊版，換成新版；你的帳本資料不受影響）"
  rm -rf /Applications/TripLedger.app
fi
if ! cp -R build/TripLedger.app /Applications/; then
  echo "❌ 放不進「應用程式」資料夾。可以直接打開 build/TripLedger.app 使用。"
  pause; exit 1
fi

echo
echo "④ 打開 TripLedger"
open /Applications/TripLedger.app
echo "✅ 安裝完成。"
pause
