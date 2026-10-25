#!/usr/bin/env bash
# macOS CI: 패키지 단위 테스트 → 앱 빌드 → (UI 테스트 타깃이 있으면) 전체 테스트 → 실행 확인.
# 실패한 줄은 GitHub annotation(::error::)으로도 남겨 로그 없이도 원인을 볼 수 있게 한다.
set -uo pipefail

report() {
  local log="$1"
  grep -E "error:|warning: .*Swift 6|FAILED|failed|✘|Fatal|fatal" "$log" | awk '!seen[$0]++' | head -40 | while IFS= read -r line; do
    echo "::error::${line//$'\n'/ }"
  done
  # 크래시처럼 오류 줄이 없을 때를 위해 마지막 몇 줄도 남긴다.
  tail -8 "$log" | while IFS= read -r line; do echo "::warning::tail: ${line}"; done
}

run() {
  local name="$1"; shift
  local log="/tmp/ci-${name}.log"
  echo "::group::${name}"
  "$@" 2>&1 | tee "$log"
  local status=${PIPESTATUS[0]}
  echo "::endgroup::"
  if [ "$status" -ne 0 ]; then
    echo "::error::${name} 실패 (exit ${status})"
    report "$log"
    exit "$status"
  fi
}

DEST='platform=macOS'
XCB=(xcodebuild -project LectureRecorder.xcodeproj -scheme LectureRecorder -destination "$DEST" -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES)

run entitlements scripts/check-entitlements.sh

if [ -d Packages/LectureCore ]; then
  run package-test swift test --package-path Packages/LectureCore
fi

run app-build "${XCB[@]}" build

if [ -d LectureRecorderUITests ]; then
  run app-test "${XCB[@]}" test
fi

APP="build/Build/Products/Debug/LectureRecorder.app"
run inspect bash -c "plutil -p '$APP/Contents/Info.plist'; codesign -d --entitlements - '$APP'"
# 확인용 요약을 annotation(notice)으로 남긴다. GitHub는 step당 notice를 10개까지만 보여주므로 요약 줄만 남긴다.
# 빌드 산출물에 실제로 서명된 권한도 확인한다 (파일에는 있어도 빌드에서 빠지면 내보내기가 막힌다).
for key in app-sandbox device.audio-input files.user-selected.read-write; do
  if ! grep -q "com.apple.security.$key" /tmp/ci-inspect.log; then
    echo "::error::빌드된 앱에 권한이 없음: com.apple.security.$key"
    exit 1
  fi
done
grep -E "NSMicrophoneUsageDescription|audio-input|app-sandbox|user-selected" /tmp/ci-inspect.log | while IFS= read -r line; do echo "::notice::${line}"; done
for f in /tmp/ci-package-test.log /tmp/ci-app-test.log; do
  [ -f "$f" ] && grep -E "Test run with|Executed [0-9]+ tests?,|TEST SUCCEEDED" "$f" | tail -3 | while IFS= read -r line; do echo "::notice::$(basename "$f"): ${line}"; done
done

# 실행 확인: 앱이 떠서 5초 동안 살아 있는지 본다.
"$APP/Contents/MacOS/LectureRecorder" -UITesting &
PID=$!
sleep 5
if ! kill -0 "$PID" 2>/dev/null; then
  echo "::error::앱이 실행 직후 종료됨"
  exit 1
fi
kill "$PID"
echo "앱 실행 확인 완료"
