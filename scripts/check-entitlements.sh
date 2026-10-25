#!/usr/bin/env bash
# 샌드박스 권한 파일 점검: 필요한 키가 있고, 허용하지 않기로 한 키가 없는지 본다.
# 사용법: scripts/check-entitlements.sh [entitlements 경로]
set -uo pipefail

FILE="${1:-LectureRecorder/Resources/LectureRecorder.entitlements}"
REQUIRED=(
  com.apple.security.app-sandbox
  com.apple.security.device.audio-input
  com.apple.security.files.user-selected.read-write
)
# 서버 없는 로컬 앱이라 네트워크 권한은 쓰지 않는다. 사용자가 고른 파일 밖의 넓은 파일 권한도 쓰지 않는다.
FORBIDDEN=(
  com.apple.security.network.client
  com.apple.security.network.server
  com.apple.security.files.all
  com.apple.security.files.downloads.read-write
  com.apple.security.temporary-exception
)

if [ ! -f "$FILE" ]; then
  echo "::error::entitlements 파일이 없음: $FILE"
  exit 1
fi

fail=0
# 키 바로 뒤 값이 <true/>인 것만 켜진 것으로 본다.
enabled() {
  awk -v k="<key>$1" 'index($0,k)==1 || index($0,"\t"k)>0 {getline n; if (n ~ /<true\/>/) found=1} END{exit !found}' "$FILE"
}
present() { grep -q "<key>$1" "$FILE"; }

for key in "${REQUIRED[@]}"; do
  if ! enabled "$key"; then
    echo "::error::필요한 권한이 없거나 꺼져 있음: $key"
    fail=1
  fi
done
for key in "${FORBIDDEN[@]}"; do
  if present "$key"; then
    echo "::error::넣지 않기로 한 권한이 있음: $key"
    fail=1
  fi
done

[ "$fail" -eq 0 ] && echo "entitlements 점검 통과: $FILE"
exit "$fail"
