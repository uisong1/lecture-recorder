#!/usr/bin/env bash
# macOS CI: 패키지 단위 테스트 → 앱 빌드 → (UI 테스트 타깃이 있으면) 전체 테스트 → 실행 확인.
# 실패한 줄은 GitHub annotation(::error::)으로도 남겨 로그 없이도 원인을 볼 수 있게 한다.
set -uo pipefail

report() {
  local log="$1"
  grep -E "error:|warning: .*Swift 6|FAILED|failed|✘|Fatal|fatal" "$log" | head -40 | while IFS= read -r line; do
    echo "::error::${line//$'\n'/ }"
  done
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
grep -E "NSMicrophoneUsageDescription|audio-input|app-sandbox" /tmp/ci-inspect.log | while IFS= read -r line; do echo "::notice::${line}"; done
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
