# CLAUDE.md

이 파일은 Claude Code가 이 저장소에서 작업할 때 따르는 안내서다.

## 프로젝트 개요

**LectureRecorder**: 대학생 한 명이 혼자 쓰는 macOS용 수업 녹음 앱.

### 목표
- **MVP**: 녹음 버튼 하나로 녹음 → 시간표 기준으로 과목 자동 분류 → 과목별 목록에서 재생
- **나중에**: 음성→텍스트 변환(STT), AI 요약, 중요 구간 북마크

### 하지 않는 것
- 서버, 회원가입, 동기화, 다중 사용자 기능 (혼자 쓰는 로컬 앱)
- iOS 등 다른 플랫폼 지원 (지금은 macOS만)

## 기술 스택

| 영역 | 선택 | 이유 |
|---|---|---|
| 언어 / UI | Swift 6 + SwiftUI | macOS 네이티브 앱의 표준. 코드가 적고 미리보기로 빠르게 확인 가능 |
| 최소 OS | macOS 14 (Sonoma) 이상 | SwiftData, `@Observable` 사용 가능 |
| 녹음 / 재생 | AVFoundation (`AVAudioRecorder`, `AVAudioPlayer`) | macOS 기본 프레임워크라 외부 의존성 없음 |
| 오디오 포맷 | AAC `.m4a` | 용량 대비 음질이 좋음 (90분 수업 약 40MB) |
| 메타데이터 저장 | SwiftData | 과목·시간표·녹음 정보를 로컬 DB에 저장. 서버 불필요 |
| 파일 저장 | `~/Library/Application Support/LectureRecorder/Recordings/<학기>/<과목>/<날짜 요일 시작시각>.m4a` | 앱 샌드박스 안의 표준 위치 |
| 테스트 | Swift Testing (`@Test`), UI는 XCTest | Xcode 기본 도구 |
| 구조 | 앱 타깃 + 로컬 Swift 패키지 `LectureCore` | 핵심 로직을 UI 없이 `swift test`로 빠르게 테스트 |
| STT (나중) | Apple `Speech` 프레임워크 → 필요하면 WhisperKit | 한국어 지원, 기기 안에서 처리 |
| AI 요약 (나중) | Claude API | 긴 강의 텍스트 요약에 적합. API 키는 Keychain에 저장 |

## 폴더 구조

```
lecture-recorder/
├── CLAUDE.md                     # 이 파일
├── TODO.md                       # 작업 체크리스트
├── README.md
├── LectureRecorder.xcodeproj
├── LectureRecorder/              # 앱 타깃: 화면과 앱 진입점만
│   ├── App/                      # LectureRecorderApp.swift, 의존성 조립
│   ├── Views/                    # SwiftUI 화면 (Recording/, Library/, Schedule/, Settings/)
│   └── Resources/                # Assets, Info.plist, entitlements
├── Packages/
│   └── LectureCore/              # 로직 패키지 (SwiftUI import 금지)
│       ├── Package.swift
│       ├── Sources/LectureCore/
│       │   ├── Models/           # Subject, TimeSlot, Recording, Bookmark
│       │   ├── Schedule/         # 현재 시각 → 과목 판별
│       │   ├── Recording/        # 녹음 서비스 (프로토콜 + AVFoundation 구현)
│       │   ├── Playback/         # 재생 서비스
│       │   └── Storage/          # 파일 경로, 저장/이동/삭제
│       └── Tests/LectureCoreTests/
└── LectureRecorderUITests/       # 주요 흐름 UI 테스트
```

## 명령어

```bash
# 로직 단위 테스트 (가장 자주 실행, 빠름)
swift test --package-path Packages/LectureCore

# 앱 빌드
xcodebuild -scheme LectureRecorder -destination 'platform=macOS' build

# 전체 테스트 (단위 + UI)
xcodebuild -scheme LectureRecorder -destination 'platform=macOS' test

# 실행: Xcode에서 ⌘R
# 또는 빌드 결과물 실행
open "$(xcodebuild -scheme LectureRecorder -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/LectureRecorder.app"
```

빌드와 테스트는 Xcode가 설치된 macOS에서만 된다.

## 코딩 규칙

### 작업 흐름
1. `TODO.md`에서 맨 위의 미완료 항목 **하나**를 고른다.
2. 테스트를 먼저 쓰거나 기능과 함께 쓴다.
3. `swift test --package-path Packages/LectureCore`가 통과하는지 확인한다.
4. TODO 항목을 `[x]`로 체크하고 **그 항목 하나만** 커밋한다.

### 커밋
- 작게 커밋한다. TODO 한 항목 = 커밋 1개 이상. 여러 항목을 한 커밋에 섞지 않는다.
- 메시지 형식: `<type>: <요약>` (예: `feat: 현재 시각으로 과목 찾기`)
  - `feat` 기능, `fix` 버그 수정, `test` 테스트, `refactor` 구조 개선, `docs` 문서, `chore` 설정
- 테스트가 실패하는 상태로 커밋하지 않는다.

### 테스트
- 기능마다 테스트를 쓴다. 로직은 `LectureCore`에 두고 단위 테스트한다.
- 시간이 걸리는 로직은 `now: Date`와 `Calendar`를 인자로 받는다. `Date()`를 직접 호출하지 않는다.
- 녹음/재생/파일 시스템은 프로토콜(`AudioRecording`, `AudioPlaying`, `FileStoring`) 뒤에 두고, 테스트에서는 가짜 구현을 쓴다.
- 경계값을 꼭 테스트한다: 수업 시작/종료 시각 정각, 수업 없는 시간, 겹치는 시간표.

### 코드
- 뷰에는 로직을 넣지 않는다. 뷰는 `@Observable` 뷰모델의 상태를 보여주기만 한다.
- `LectureCore`는 SwiftUI를 import하지 않는다.
- 실패 상황을 무시하지 않는다: 마이크 권한 거부, 저장 공간 부족, 녹음 중 앱 종료. 사용자에게 알리고 로그를 남긴다.
- 강제 언래핑(`!`)과 `try!`는 테스트 코드 밖에서 쓰지 않는다.
- UI 문구는 한국어로 쓴다.
- 모든 화면 작업은 `DESIGN.md`를 따른다. 색·글자·모서리는 `LectureRecorder/Views/Design/DesignSystem.swift`의 토큰만 쓰고, 강조색은 Action Blue 하나, 그림자는 쓰지 않는다.
- API 키 같은 비밀값은 코드나 저장소에 넣지 않고 Keychain에 저장한다.

## 기능 범위
- 무엇을 만들지는 REQUIREMENTS.md를 따른다. 거기 없는 큰 기능은 TODO "확인 필요"에 제안만 한다.
- 받아쓰기, 요약, 유료 API는 사용하지 않는다.

## 품질 기준 (녹음 앱이므로 안정성이 최우선)
- 녹음 중 앱이 꺼지거나 맥이 잠자기에 들어가도 그때까지의 녹음은 보존되어야 한다.
- 녹음 중에는 맥이 잠자기에 들어가지 않게 한다.
- 3시간 녹음 기준 파일 크기를 합리적으로 유지한다 (압축 포맷 사용).
- 모든 기능에 테스트를 작성하고 CI가 통과해야 머지한다.

## 사용자 피드백
- FEEDBACK.md에 사용자가 직접 쓴 피드백은 가장 높은 우선순위로 반영한다.
- 반영한 항목은 FEEDBACK.md에서 "반영됨" 표시를 한다.

## 결정 기록
- 기술적 결정(라이브러리 선택, 저장 방식, 구조 변경)을 하면 DECISIONS.md에 날짜, 결정, 이유를 남긴다.
