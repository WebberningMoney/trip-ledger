#!/bin/bash
# build.sh：編譯階段 0 的收據測試工具 build/receipt-probe。
#
# 只能在 Apple 晶片、macOS 27 以上的 Mac 上執行；只需要「命令列開發者工具」，不需要 Xcode。
# 會先試著連「方法 B（AI 直接看照片）」一起編譯；這段寫法還沒在真的 Mac 上確認過，
# 編譯不過就自動改成只編譯方法 A，並把錯誤訊息留在 build/build_log.txt。

set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
LOG=build/build_log.txt
: > "$LOG"
say() { echo "$@" | tee -a "$LOG"; }

say "== 編譯 receipt-probe（$(date '+%Y-%m-%d %H:%M')） =="

if [ "$(uname)" != "Darwin" ]; then say "✋ 這個工具只能在 Mac 上編譯。"; exit 1; fi
if [ "$(uname -m)" != "arm64" ]; then say "✋ 需要 Apple 晶片（M1 以後）的 Mac。"; exit 1; fi
ver="$(sw_vers -productVersion)"
if [ "${ver%%.*}" -lt 27 ]; then say "✋ 需要 macOS 27 以上，這台是 $ver。"; exit 1; fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
  say "找不到 Swift 編譯器，正在請 macOS 安裝「命令列開發者工具」。"
  say "裝好之後（約 5～10 分鐘）請再執行一次。"
  xcode-select --install >/dev/null 2>&1
  exit 1
fi

SDK="$(xcrun --show-sdk-path)"
say "macOS $ver｜$(xcrun swiftc --version 2>&1 | head -1)"

# 把 SDK 裡 Foundation Models 和「圖片」有關的寫法存下來，方法 B 編譯不過時用來修正。
FM_IF="$(find "$SDK/System/Library/Frameworks/FoundationModels.framework" -name '*.swiftinterface' 2>/dev/null | grep -m1 arm64)"
if [ -n "$FM_IF" ]; then
  grep -n -i -E 'image|attachment|PromptRepresentable' "$FM_IF" > build/fm_image_api.txt 2>/dev/null
  say "已記錄 Foundation Models 和圖片有關的寫法：build/fm_image_api.txt（$(wc -l < build/fm_image_api.txt | tr -d ' ') 行）"
else
  say "⚠️ SDK 裡找不到 Foundation Models 的介面檔。"
fi

SOURCES=(Sources/Probe/*.swift)
FLAGS=(-O -swift-version 5 -sdk "$SDK" -target arm64-apple-macos27.0)

say ""
say "-- 試著連方法 B 一起編譯 --"
if xcrun swiftc "${FLAGS[@]}" -D PROBE_IMAGE_INPUT "${SOURCES[@]}" -o build/receipt-probe >>"$LOG" 2>&1; then
  say "✅ 編譯完成（方法 A＋方法 B）"
  exit 0
fi

say "⚠️ 方法 B 的寫法這台 Mac 編譯不過（錯誤訊息在上面），改成只編譯方法 A。"
say ""
say "-- 只編譯方法 A --"
if xcrun swiftc "${FLAGS[@]}" "${SOURCES[@]}" -o build/receipt-probe >>"$LOG" 2>&1; then
  say "✅ 編譯完成（只有方法 A）"
  exit 0
fi

say "❌ 編譯失敗。請把 build/build_log.txt 提供給開發者。"
exit 1
