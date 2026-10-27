# LectureRecorder

대학생 한 명이 혼자 쓰는 macOS용 수업 녹음 앱. 녹음 버튼 하나로 녹음하면 시간표를 보고 과목별로 자동 분류한다.

자세한 설계와 규칙은 [CLAUDE.md](CLAUDE.md), 작업 목록은 [TODO.md](TODO.md)를 본다. 새 기능을 Mac에서 직접 확인하려면 [CHECKLIST_MAC.md](CHECKLIST_MAC.md)를 따라 한다.

## 요구 사항

- macOS 14 (Sonoma) 이상
- Xcode 16 이상 (Swift 6)

## 빌드와 실행

```bash
# Xcode로 열기 → ⌘R
open LectureRecorder.xcodeproj

# 명령줄 빌드
xcodebuild -scheme LectureRecorder -destination 'platform=macOS' build

# 빌드 결과물 실행
open "$(xcodebuild -scheme LectureRecorder -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/LectureRecorder.app"
```

처음 실행하면 마이크 권한을 묻는다. 거부했다면 시스템 설정 → 개인정보 보호 및 보안 → 마이크에서 다시 켤 수 있다.

## 앱으로 설치하기

Xcode 없이 Launchpad·Dock에서 쓰려면 터미널을 저장소 폴더에서 열고 아래 한 줄을 실행한다.

```bash
git pull && ./scripts/install.sh
```

Release로 빌드해 `/Applications/LectureRecorder.app`에 설치하고 바로 연다. 실행 중이면 먼저 종료하고(녹음 중이면 정지·저장 후 실행), 이미 설치돼 있으면 덮어쓴다. 녹음 파일과 설정은 앱 밖(`~/Library/Containers/com.uisong.LectureRecorder`)에 있어서 다시 설치해도 그대로다. 업데이트할 때도 같은 한 줄을 다시 실행하면 된다. 빌드만 해 보려면 `./scripts/install.sh --build-only`.

## 테스트

```bash
# 로직 단위 테스트 (빠름)
swift test --package-path Packages/LectureCore

# 전체 테스트 (단위 + UI)
xcodebuild -scheme LectureRecorder -destination 'platform=macOS' test
```

Xcode가 없는 Linux에서는 Docker로 `LectureCore` 테스트 중 플랫폼에 독립적인 부분만 돌릴 수 있다.

```bash
scripts/swift-test-linux.sh
```

푸시하면 GitHub Actions(`.github/workflows/ci.yml`)가 macOS에서 빌드, 단위 테스트, UI 테스트를 돌린다.

## 폴더 구조

- `LectureRecorder/`: 앱 타깃 (화면과 앱 진입점)
- `Packages/LectureCore/`: 핵심 로직 패키지 (SwiftUI 없음, 단위 테스트 대상)
- `LectureRecorderUITests/`: UI 테스트
- `scripts/`: CI와 로컬 테스트 스크립트
