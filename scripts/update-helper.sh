#!/bin/bash
# 앱 안 "업데이트" 버튼이 부르는 도우미. 샌드박스 밖에서 새 앱을 받고 바꿔 끼운다.
# install.sh가 이 파일을 ~/Library/Application Scripts/com.uisong.LectureRecorder/update.sh 로 복사해 둔다.
#   update.sh download <zip 주소> <sha256> <빌드번호>   새 앱을 받아 검증해 둔다 (앱은 그대로)
#   update.sh install  <빌드번호> <앱 프로세스 번호> <앱 경로>   앱이 끝나면 바꿔 끼우고 다시 연다
# 녹음 파일과 설정은 앱 밖(~/Library/Containers/com.uisong.LectureRecorder)에 있어 건드리지 않는다.
set -euo pipefail

BUNDLE_ID="com.uisong.LectureRecorder"
URL_PREFIX="https://github.com/uisong1/lecture-recorder/releases/download/"
HOME_DIR="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true)"
HOME_DIR="${HOME_DIR:-$HOME}"
STAGE="$HOME_DIR/Library/Caches/LectureRecorderUpdate"
LOG="$HOME_DIR/Library/Logs/LectureRecorder-update.log"
JOB_LABEL="com.uisong.LectureRecorder.update"
mkdir -p "$STAGE" "$(dirname "$LOG")"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"; }

# 종료 코드: 10 받기 실패 / 11 체크섬 불일치 / 12 앱 검증 실패 / 13 받아 둔 앱 없음 / 14 바꾸기 실패 / 2 잘못된 인자
require_build() { [[ "${1:-}" =~ ^[0-9]+$ ]] || { log "잘못된 빌드 번호: ${1:-}"; exit 2; }; }

do_download() {
  local url="${1:-}" sha="${2:-}" build="${3:-}"
  require_build "$build"
  [[ "$url" == "$URL_PREFIX"* && "$url" != *[[:space:]]* ]] || { log "허용하지 않는 주소: $url"; exit 2; }
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { log "잘못된 체크섬"; exit 2; }
  local dir="$STAGE/$build"
  rm -rf "$dir"; mkdir -p "$dir"
  log "받기 시작: build $build"
  # curl로 받은 파일에는 격리(quarantine) 표시가 붙지 않는다.
  curl -fL --retry 3 --connect-timeout 20 -o "$dir/app.zip" "$url" >>"$LOG" 2>&1 || { log "받기 실패"; rm -rf "$dir"; exit 10; }
  local actual
  actual="$(shasum -a 256 "$dir/app.zip" | awk '{print $1}')"
  [ "$actual" = "$sha" ] || { log "체크섬 불일치: $actual"; rm -rf "$dir"; exit 11; }
  ditto -x -k "$dir/app.zip" "$dir/out" >>"$LOG" 2>&1 || { log "압축 풀기 실패"; rm -rf "$dir"; exit 12; }
  local app="$dir/out/LectureRecorder.app"
  [ -d "$app" ] || { log "앱이 없음"; rm -rf "$dir"; exit 12; }
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null)" = "$BUNDLE_ID" ] || { log "번들 ID 불일치"; rm -rf "$dir"; exit 12; }
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist" 2>/dev/null)" = "$build" ] || { log "빌드 번호 불일치"; rm -rf "$dir"; exit 12; }
  codesign --verify --deep "$app" >>"$LOG" 2>&1 || { log "서명 검증 실패"; rm -rf "$dir"; exit 12; }
  rm -f "$dir/app.zip"
  touch "$dir/READY"
  log "받기 완료: build $build"
}

# 실제 교체. 앱이 끝난 뒤에 한다.
do_apply() {
  local build="$1" pid="$2" target="$3"
  local new="$STAGE/$build/out/LectureRecorder.app"
  [ -f "$STAGE/$build/READY" ] && [ -d "$new" ] || { log "받아 둔 앱이 없음"; exit 13; }
  # 앱이 스스로 끝나기를 기다린다. 녹음 종료 확인에서 사용자가 취소하면 바꾸지 않고 그만둔다 (강제 종료 안 함).
  for _ in $(seq 1 180); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    log "앱이 끝나지 않아 업데이트를 취소함"
    launchctl remove "$JOB_LABEL" 2>/dev/null || true
    exit 0
  fi
  local backup="$target.old"
  rm -rf "$backup"
  if ! mv "$target" "$backup" 2>>"$LOG"; then
    log "기존 앱을 옮기지 못함(권한?): $target"
    open "$target" 2>/dev/null || true
    exit 14
  fi
  if ! ditto "$new" "$target" >>"$LOG" 2>&1; then
    log "새 앱 복사 실패, 원래대로 되돌림"
    rm -rf "$target"; mv "$backup" "$target"
    open "$target" 2>/dev/null || true
    exit 14
  fi
  xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
  rm -rf "$backup" "$STAGE"
  log "교체 완료: build $build"
  open "$target"
  launchctl remove "$JOB_LABEL" 2>/dev/null || true
}

do_install() {
  local build="${1:-}" pid="${2:-}" target="${3:-}"
  require_build "$build"; require_build "$pid"
  [[ "$target" == /*/LectureRecorder.app && "$target" != *..* ]] || { log "허용하지 않는 앱 경로: $target"; exit 2; }
  [ -f "$STAGE/$build/READY" ] || { log "받아 둔 앱이 없음"; exit 13; }
  launchctl remove "$JOB_LABEL" 2>/dev/null || true
  # 이 앱이 끝나도 계속 돌도록 launchd에 맡긴다. 안 되면 nohup으로 대신한다.
  if ! launchctl submit -l "$JOB_LABEL" -o "$LOG" -e "$LOG" -- /bin/bash "$0" apply "$build" "$pid" "$target" 2>>"$LOG"; then
    nohup /bin/bash "$0" apply "$build" "$pid" "$target" >>"$LOG" 2>&1 </dev/null &
    disown || true
  fi
  log "교체 예약: build $build"
}

case "${1:-}" in
  download) shift; do_download "$@" ;;
  install)  shift; do_install "$@" ;;
  apply)    shift; do_apply "$@" ;;
  *) echo "사용법: update.sh download|install ..." >&2; exit 2 ;;
esac
