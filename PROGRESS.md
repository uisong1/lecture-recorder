# PROGRESS

## 2026-10-25 2-1 Bookmark 모델
- 한 일: `Bookmark`(시점, 메모, 만든 시각) 모델과 `Recording.bookmarks`(녹음 삭제 시 함께 삭제), `BookmarkManager`(추가·메모 수정·삭제). 단위 테스트 6개.
- 다음: 2-2 녹음 중 북마크 추가, 2-3 재생 화면에서 북마크로 이동.

## 2026-10-25 1-16 이름 변경 / 삭제 / 과목 이동
- 한 일: `RecordingManager`(이름 변경·과목 이동·삭제, 파일과 DB 함께 처리)와 `RecordingStorage.moveFile/removeFile`, 목록 행 우클릭 메뉴(이름 변경 창, 삭제 확인 창, 과목 이동). 단위 테스트 9개. 결정은 DECISIONS.md에 기록.
- 확인 필요: 우클릭 메뉴와 대화 상자는 Mac에서 직접 눌러 확인해 주세요.

## 2026-10-25 1-15 탐색 슬라이더와 배속
- 한 일: `AudioPlaying`에 `rate`·`seek(to:)` 추가, `PlaybackController.seek/setRate`와 `PlaybackRate`(1.0/1.25/1.5/2.0), 목록 아래 `PlaybackBar`(슬라이더 + 배속 선택, DESIGN.md 토큰 사용). 단위 테스트 5개 추가.
- 확인 필요: 실제 소리 속도와 슬라이더 드래그는 Mac에서 직접 확인해 주세요 (CI는 빌드·단위 테스트만).

## 2026-10-25 1-14 재생 서비스
- 한 일: `AudioPlaying`·`SystemAudioPlayer`·`PlaybackController`와 목록의 재생/일시정지 버튼은 1-9 때 이미 구현돼 있어 완료 기준을 확인하고 1-14를 체크. 재생 종료 갱신 테스트 1개 추가.
- 다음: 1-15 탐색 슬라이더와 배속.

## 2026-10-25 두 번째 실행 (구현 모드)
- 한 일: 1-11 마이크 권한 거부 안내(시스템 설정 열기 버튼), 1-12 비정상 종료 녹음 복구(저널 파일 + 파일 크기로 길이 추정), 1-13 사이드바 + 과목별 녹음 목록(`RecordingLibrary`). 모두 CI(Linux + macOS) 통과 후 main에 푸시. 1-12는 처음에 Linux에서 `Log`를 못 찾아 실패해 `#if canImport(os)`로 고침.
- 막힌 것: 없음.
- 확인 필요(TODO.md에 적음): 강제 종료된 `.m4a`는 파일 끝 정보가 없어 재생이 안 될 수 있음. 앱 레이아웃을 사이드바 구조로 바꿈.
- 다음 실행: 1-14 재생 서비스와 재생 / 일시정지. (목록의 "듣기" 버튼은 이미 `PlaybackController`를 씀. 1-14 완료 기준과 겹치는 부분을 먼저 확인.)

## 2026-10-25 (구현 모드)
- 한 일: 1-10 일시정지 / 재개 (`AudioRecording.pause/resume`, `RecordingController.pause/resume/togglePause`, 녹음 화면 버튼 ⌘P, 단위 테스트 6개). CI(Linux + macOS) 통과 확인.
- 막힌 것: 없음. (이 환경엔 swift/docker가 없어 CI로만 검증)
- 다음 실행: 1-11 마이크 권한 거부 처리부터.
