# PROGRESS

## 2026-10-25 두 번째 실행 (구현 모드)
- 한 일: 1-11 마이크 권한 거부 안내(시스템 설정 열기 버튼), 1-12 비정상 종료 녹음 복구(저널 파일 + 파일 크기로 길이 추정), 1-13 사이드바 + 과목별 녹음 목록(`RecordingLibrary`). 모두 CI(Linux + macOS) 통과 후 main에 푸시. 1-12는 처음에 Linux에서 `Log`를 못 찾아 실패해 `#if canImport(os)`로 고침.
- 막힌 것: 없음.
- 확인 필요(TODO.md에 적음): 강제 종료된 `.m4a`는 파일 끝 정보가 없어 재생이 안 될 수 있음. 앱 레이아웃을 사이드바 구조로 바꿈.
- 다음 실행: 1-14 재생 서비스와 재생 / 일시정지. (목록의 "듣기" 버튼은 이미 `PlaybackController`를 씀. 1-14 완료 기준과 겹치는 부분을 먼저 확인.)

## 2026-10-25 (구현 모드)
- 한 일: 1-10 일시정지 / 재개 (`AudioRecording.pause/resume`, `RecordingController.pause/resume/togglePause`, 녹음 화면 버튼 ⌘P, 단위 테스트 6개). CI(Linux + macOS) 통과 확인.
- 막힌 것: 없음. (이 환경엔 swift/docker가 없어 CI로만 검증)
- 다음 실행: 1-11 마이크 권한 거부 처리부터.
