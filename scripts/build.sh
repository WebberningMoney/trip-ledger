#!/bin/bash
# build.sh：編譯 TripLedger。會做出兩個東西：
#   build/TripLedger.app   ← Mac App（階段 1）
#   build/receipt-probe    ← 收據辨識測試工具（階段 0，命令列）
#
# 只能在 Apple 晶片、macOS 27 以上的 Mac 上執行；只需要「命令列開發者工具」，不需要 Xcode。
# 「AI 直接看照片」（第二意見）的寫法用到 macOS 27 的新功能，編譯不過時會自動改成不含這個功能，
# 錯誤訊息留在 build/build_log.txt。

set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
LOG=build/build_log.txt
: > "${LOG}"
say() { echo "$@" | tee -a "${LOG}"; }

say "== 編譯 TripLedger（$(date '+%Y-%m-%d %H:%M')） =="

if [ "$(uname)" != "Darwin" ]; then say "✋ 這個專案只能在 Mac 上編譯。"; exit 1; fi
if [ "$(uname -m)" != "arm64" ]; then say "✋ 需要 Apple 晶片（M1 以後）的 Mac。"; exit 1; fi
ver="$(sw_vers -productVersion)"
if [ "${ver%%.*}" -lt 27 ]; then say "✋ 需要 macOS 27 以上，這台是 ${ver}。"; exit 1; fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
  say "找不到 Swift 編譯器，正在請 macOS 安裝「命令列開發者工具」。"
  say "裝好之後（約 5～10 分鐘）請再執行一次。"
  xcode-select --install >/dev/null 2>&1
  exit 1
fi

SDK="$(xcrun --show-sdk-path)"
say "macOS ${ver}｜$(xcrun swiftc --version 2>&1 | head -1)"

# 把 SDK 裡 Foundation Models 和「圖片」有關的寫法存下來，「AI 直接看照片」編譯不過時用來修正。
FM_IF="$(find "${SDK}/System/Library/Frameworks/FoundationModels.framework" -name '*.swiftinterface' 2>/dev/null | grep -m1 arm64)"
if [ -n "${FM_IF}" ]; then
  grep -n -i -E 'image|attachment|PromptRepresentable' "${FM_IF}" > build/fm_image_api.txt 2>/dev/null
fi

FLAGS=(-O -swift-version 5 -sdk "${SDK}" -target arm64-apple-macos27.0)

# 先試著連「AI 直接看照片」一起編譯，不行就不含這個功能。
# 用法：compile 名稱 輸出檔 [其他參數…] -- 原始碼…
compile() {
  local name="$1" out="$2"; shift 2
  local extra=()
  while [ "$1" != "--" ]; do extra+=("$1"); shift; done
  shift
  say ""
  say "-- 編譯 ${name} --"
  if xcrun swiftc "${FLAGS[@]}" ${extra[@]+"${extra[@]}"} -D AI_IMAGE_INPUT "$@" -o "${out}" >>"${LOG}" 2>&1; then
    say "✅ ${name}：完成（含 AI 看照片的第二意見）"
    return 0
  fi
  say "⚠️ ${name}：「AI 看照片」的寫法編譯不過，改成不含這個功能（錯誤訊息在 ${LOG}）"
  if xcrun swiftc "${FLAGS[@]}" ${extra[@]+"${extra[@]}"} "$@" -o "${out}" >>"${LOG}" 2>&1; then
    say "✅ ${name}：完成（不含 AI 看照片）"
    return 0
  fi
  say "❌ ${name}：編譯失敗。請把 ${LOG} 提供給開發者。"
  return 1
}

compile "收據測試工具 receipt-probe" build/receipt-probe -- Sources/Core/*.swift Sources/Probe/*.swift || exit 1

APP=build/TripLedger.app
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
compile "App：TripLedger" "${APP}/Contents/MacOS/TripLedger" -parse-as-library -- Sources/Core/*.swift Sources/App/*.swift || exit 1
cp Resources/Info.plist "${APP}/Contents/Info.plist"
cp Resources/chains.json "${APP}/Contents/Resources/chains.json"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"; fi
# 免費的臨時簽章（ad-hoc）：讓 macOS 願意執行；不需要 Apple 開發者帳號。
codesign --force --sign - "${APP}" >>"${LOG}" 2>&1 || say "⚠️ 臨時簽章失敗（通常不影響在這台 Mac 上使用）"
say ""
say "✅ App 放在 ${APP}"
