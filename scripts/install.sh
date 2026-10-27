#!/usr/bin/env bash
# 앱을 Release로 빌드해 /Applications에 설치한다. Xcode 창을 열 필요 없이 터미널 한 줄로 끝난다.
#   ./scripts/install.sh            빌드 후 /Applications/LectureRecorder.app 으로 설치
#   ./scripts/install.sh --build-only   빌드만 하고 설치하지 않는다 (CI에서 사용)
# 녹음 파일·설정은 앱 밖(~/Library/Containers/com.uisong.LectureRecorder)에 있어서 다시 설치해도 그대로다.
set -euo pipefail

BUILD_ONLY=0
[ "${1:-}" = "--build-only" ] && BUILD_ONLY=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="LectureRecorder"
DEST_DIR="${INSTALL_DIR:-/Applications}"
BUILT="build/install/Build/Products/Release/${APP_NAME}.app"

if [ "$(uname)" != "Darwin" ]; then
  echo "❌ Mac에서만 실행할 수 있어요."
  exit 1
fi

# xcode-select가 Xcode가 아니라 명령줄 도구(CommandLineTools)를 가리키면 xcodebuild가 실패한다.
# sudo 없이 이 실행에서만 Xcode.app을 찾아 DEVELOPER_DIR로 지정한다.
if ! xcodebuild -version >/dev/null 2>&1; then
  XCODE_APP=""
  if [ -d "${DEVELOPER_DIR:-}" ]; then :; else
    for app in /Applications/Xcode.app /Applications/Xcode*.app "$HOME/Applications/Xcode.app" "$HOME/Applications/Xcode*.app"; do
      [ -d "$app/Contents/Developer" ] && { XCODE_APP="$app"; break; }
    done
    if [ -z "$XCODE_APP" ]; then
      XCODE_APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -1)"
    fi
  fi
  if [ -n "$XCODE_APP" ] && [ -d "$XCODE_APP/Contents/Developer" ]; then
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    echo "ℹ️  Xcode를 찾았어요: $XCODE_APP"
  fi
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "❌ Xcode를 찾지 못했어요. App Store에서 Xcode를 설치하고 한 번 열어 라이선스에 동의한 뒤 다시 실행해 주세요."
  exit 1
fi

echo "🔨 앱을 빌드하는 중이에요. 처음엔 몇 분 걸려요…"
LOG="$(mktemp -t lecture-install)"
if ! xcodebuild -project LectureRecorder.xcodeproj -scheme "$APP_NAME" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/install \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build >"$LOG" 2>&1; then
  { grep -E "error:|Fatal|FAILED" "$LOG" | awk '!seen[$0]++' | head -20; } || true
  if ! grep -qE "error:|Fatal|FAILED" "$LOG"; then tail -20 "$LOG"; fi
  echo "❌ 빌드에 실패했어요. 전체 로그: $LOG"
  exit 1
fi
[ -d "$BUILT" ] || { echo "❌ 빌드 결과물을 찾지 못했어요: $BUILT"; exit 1; }
echo "✅ 빌드 완료"

if [ "$BUILD_ONLY" = 1 ]; then
  echo "빌드만 하고 설치는 건너뛰었어요: $BUILT"
  exit 0
fi

# 실행 중이면 정상 종료를 요청한다. 녹음 중이면 앱이 저장하고 끝나도록 충분히 기다린다.
if pgrep -x "$APP_NAME" >/dev/null; then
  echo "⏹  실행 중인 $APP_NAME 을(를) 종료해요. 녹음 중이면 먼저 정지·저장해 주세요."
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    pgrep -x "$APP_NAME" >/dev/null || break
    sleep 1
  done
  if pgrep -x "$APP_NAME" >/dev/null; then
    echo "❌ 앱이 아직 종료되지 않았어요. 앱을 직접 종료한 뒤 다시 실행해 주세요. (녹음 보호를 위해 강제 종료는 하지 않아요.)"
    exit 1
  fi
fi

echo "📦 $DEST_DIR 에 설치하는 중…"
TARGET="$DEST_DIR/${APP_NAME}.app"
if [ -e "$TARGET" ]; then
  rm -rf "$TARGET" 2>/dev/null || sudo rm -rf "$TARGET"
fi
if ! ditto "$BUILT" "$TARGET" 2>/dev/null; then
  echo "관리자 권한이 필요해요. Mac 로그인 암호를 입력해 주세요."
  sudo ditto "$BUILT" "$TARGET"
fi

echo "🎉 설치 완료! Launchpad나 응용 프로그램 폴더에서 $APP_NAME 을(를) 열 수 있어요."
echo "   기존 녹음과 설정은 그대로 유지돼요."
echo "   Dock에 두려면: 앱을 연 뒤 Dock 아이콘 우클릭 → 옵션 → Dock에 유지"
open "$TARGET"
