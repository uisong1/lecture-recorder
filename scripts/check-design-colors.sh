#!/usr/bin/env bash
# 화면 코드에 .red/.orange 같은 색 직접 지정이 없는지 본다. 오류 색은 Design.Palette.danger를 쓴다.
# 과목 색 변환(SubjectColor+Color.swift)만 예외다.
set -uo pipefail
hits=$(grep -rnE '\.(red|orange)\b' LectureRecorder --include=*.swift | grep -v 'SubjectColor+Color.swift' || true)
if [ -n "$hits" ]; then
  while IFS= read -r line; do echo "::error::색 직접 지정: $line"; done <<< "$hits"
  exit 1
fi
echo "색 직접 지정 점검 통과"
