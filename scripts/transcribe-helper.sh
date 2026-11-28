#!/bin/bash
# 앱의 "전사" 탭이 부르는 도우미. 샌드박스 밖에서 Qwen3-ASR(mlx-audio)로 녹음을 글로 바꾼다.
# install.sh가 이 파일을 ~/Library/Application Scripts/com.uisong.LectureRecorder/transcribe.sh 로,
# transcribe_worker.py를 같은 폴더에 복사해 둔다.
#   transcribe.sh status                                        준비됐으면 0, 아니면 20
#   transcribe.sh setup                                         전사 도구(Python 가상환경 + mlx-audio)를 설치한다
#   transcribe.sh run <녹음> <결과.json> <진행.json> <앱 pid> [<이어하기.json>]
#                                                               녹음 하나를 전사한다 (이어하기 파일이 있으면 끝낸 조각은 건너뛴다)
# 녹음 파일은 읽기만 한다. 결과와 진행 파일은 앱이 알려 준 위치에만 쓴다.
# 종료 코드: 2 잘못된 인자 / 20 도구 없음 / 21 녹음 변환 실패 / 22 모델 불러오기 실패 / 23 전사 실패
#            30 쓸 수 있는 Python 없음 / 31 설치 실패 / 40 취소됨
set -euo pipefail

HOME_DIR="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true)"
HOME_DIR="${HOME_DIR:-$HOME}"
SUPPORT="$HOME_DIR/Library/Application Support/LectureRecorderTranscribe"
VENV="$SUPPORT/venv"
LOG="$HOME_DIR/Library/Logs/LectureRecorder-transcribe.log"
# 사용자가 Mac에서 시험한 버전(2026-11-28). 올릴 때는 품질을 다시 확인한다.
MLX_AUDIO_VERSION="0.6.8"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$SUPPORT" "$(dirname "$LOG")"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"; }

is_ready() {
  [[ -x "$VENV/bin/python" ]] && "$VENV/bin/python" -c "import mlx_audio" >/dev/null 2>&1
}

# mlx-audio는 Python 3.10 이상이 필요하다. macOS 기본 /usr/bin/python3는 3.9라 Homebrew 등을 먼저 찾는다.
find_python() {
  local candidate
  for candidate in \
    /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 /opt/homebrew/bin/python3.10 \
    /opt/homebrew/bin/python3 /usr/local/bin/python3.12 /usr/local/bin/python3.11 /usr/local/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/Current/bin/python3 /usr/bin/python3; do
    if [[ -x "$candidate" ]] && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

do_setup() {
  if is_ready; then
    log "설치: 이미 준비됨"
    return 0
  fi
  local python
  if ! python="$(find_python)"; then
    log "설치 실패: Python 3.10 이상을 찾지 못함 (brew install python@3.12)"
    exit 30
  fi
  log "설치 시작: $python, mlx-audio $MLX_AUDIO_VERSION"
  rm -rf "$VENV"
  if ! "$python" -m venv "$VENV" >>"$LOG" 2>&1; then
    log "설치 실패: 가상환경을 만들지 못함"
    exit 31
  fi
  if ! "$VENV/bin/python" -m pip install --upgrade pip >>"$LOG" 2>&1 \
    || ! "$VENV/bin/python" -m pip install "mlx-audio==$MLX_AUDIO_VERSION" >>"$LOG" 2>&1; then
    log "설치 실패: pip install"
    exit 31
  fi
  is_ready || { log "설치 실패: mlx_audio를 불러오지 못함"; exit 31; }
  log "설치 완료"
}

do_run() {
  local input="${1:-}" output="${2:-}" progress="${3:-}" pid="${4:-}" resume="${5:-}"
  [[ -f "$input" && -n "$output" && -n "$progress" && "$pid" =~ ^[0-9]+$ ]] || { log "잘못된 인자"; exit 2; }
  is_ready || { log "전사 도구가 설치되지 않음"; echo "전사 도구가 설치되지 않음" >>"$progress.log"; exit 20; }
  log "전사 시작: $(basename "$input")"
  set +e
  "$VENV/bin/python" -I "$HERE/transcribe_worker.py" "$input" "$output" "$progress" "$pid" "$resume" 2>>"$LOG"
  local status=$?
  set -e
  log "전사 끝: $(basename "$input") (코드 $status)"
  exit "$status"
}

case "${1:-}" in
  status) is_ready || exit 20 ;;
  setup) do_setup ;;
  run) shift; do_run "$@" ;;
  *) log "알 수 없는 명령: ${1:-}"; exit 2 ;;
esac
