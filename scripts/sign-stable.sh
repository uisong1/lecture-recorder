#!/usr/bin/env bash
# 빌드된 앱을 "빌드가 바뀌어도 같은 앱"으로 인식되도록 다시 서명한다 (DECISIONS.md 2026-11-07).
#   scripts/sign-stable.sh <LectureRecorder.app 경로>
# ad-hoc 서명의 기본 지정 요구사항(designated requirement)은 빌드마다 달라지는 코드 해시(cdhash)라서,
# 마이크·알림 같은 권한이 빌드/업데이트마다 새 앱으로 취급되어 다시 물어본다.
# 요구사항을 "번들 ID가 같으면 같은 앱"으로 고정하면 권한이 유지된다. 권한(entitlements)은 그대로 둔다.
set -euo pipefail
APP="${1:?앱 경로가 필요해요}"
BUNDLE_ID="com.uisong.LectureRecorder"
codesign --force --deep --sign - --preserve-metadata=entitlements,flags \
  -r="designated => identifier \"$BUNDLE_ID\"" "$APP"
codesign --verify --deep "$APP"
REQ="$(codesign -d -r- "$APP" 2>&1 | grep '^designated' || true)"
case "$REQ" in
  *"identifier \"$BUNDLE_ID\""*) ;;
  *) echo "❌ 지정 요구사항이 고정되지 않았어요: $REQ"; exit 1 ;;
esac
case "$REQ" in *cdhash*) echo "❌ 지정 요구사항에 cdhash가 남아 있어요: $REQ"; exit 1 ;; esac
echo "✅ 서명 고정: $REQ"
