#!/usr/bin/env bash
# Xcode 없는 Linux에서 Docker로 LectureCore 단위 테스트를 돌린다.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
docker run --rm -v "$ROOT":/w -w /w -v lecturecore-build:/w/Packages/LectureCore/.build \
  swift:6.1-noble swift test --package-path Packages/LectureCore "$@"
