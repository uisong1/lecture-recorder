#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct RecordingLibraryTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
    }

    @discardableResult
    func addRecording(_ title: String, subject: Subject?, at startedAt: Date) -> Recording {
        let recording = Recording(title: title, subject: subject, startedAt: startedAt, duration: 60, relativePath: "\(title).m4a")
        context.insert(recording)
        return recording
    }

    @Test func 과목을_고르면_그_과목의_녹음이_최신순으로_나온다() throws {
        let subjects = SubjectManager(context: context)
        let ds = try subjects.add(name: "자료구조", color: .green)
        let os = try subjects.add(name: "운영체제", color: .blue)
        addRecording("월요일", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("수요일", subject: ds, at: date(2026, 3, 4, 10, 0))
        addRecording("운영체제", subject: os, at: date(2026, 3, 3, 13, 0))
        try context.save()

        let library = RecordingLibrary(context: context)
        library.select(.subject(ds.persistentModelID))

        #expect(library.recordings.map(\.title) == ["수요일", "월요일"])
    }

    @Test func 내보내기_이름은_분류와_기간을_담는다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let library = RecordingLibrary(context: context)
        #expect(library.exportLabel == "모든 녹음")
        library.select(.subject(ds.persistentModelID))
        #expect(library.exportLabel == "자료구조")
        library.select(.unclassified)
        #expect(library.exportLabel == "미분류")
        library.select(.all)
        library.filter.period = .last7Days
        #expect(library.exportLabel == "모든 녹음 최근 7일")
    }

    @Test func 직접_지정한_기간으로_목록이_걸러지고_내보내기_이름에_담긴다() throws {
        addRecording("3월 2일", subject: nil, at: date(2026, 3, 2, 10, 0))
        addRecording("3월 10일 밤", subject: nil, at: date(2026, 3, 10, 23, 59))
        addRecording("3월 11일", subject: nil, at: date(2026, 3, 11, 0, 0))
        try context.save()

        let library = RecordingLibrary(context: context, now: { date(2026, 6, 1, 9, 0) }, calendar: seoulCalendar)
        library.select(.all)
        library.filter = RecordingFilter(period: .custom, customStart: date(2026, 3, 10, 0, 0), customEnd: date(2026, 3, 10, 0, 0))
        #expect(library.recordings.map(\.title) == ["3월 10일 밤"])
        #expect(library.exportLabel == "모든 녹음 2026-03-10~2026-03-10")

        library.filter = RecordingFilter()
        #expect(library.recordings.count == 3)
    }

    @Test func 미분류를_고르면_과목_없는_녹음만_나온다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("과목 있음", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("과목 없음", subject: nil, at: date(2026, 3, 2, 12, 30))
        try context.save()

        let library = RecordingLibrary(context: context)
        library.select(.unclassified)

        #expect(library.recordings.map(\.title) == ["과목 없음"])
    }

    @Test func 모든_녹음을_고르면_과목과_상관없이_최신순으로_나온다() throws {
        let subjects = SubjectManager(context: context)
        let ds = try subjects.add(name: "자료구조", color: .green)
        let os = try subjects.add(name: "운영체제", color: .blue)
        addRecording("월요일", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("화요일", subject: os, at: date(2026, 3, 3, 13, 0))
        addRecording("미분류", subject: nil, at: date(2026, 3, 4, 9, 0))
        try context.save()

        let library = RecordingLibrary(context: context)
        library.select(.all)

        #expect(library.recordings.map(\.title) == ["미분류", "화요일", "월요일"])
        #expect(library.count(for: .all) == 3)
        #expect(library.showsSubjectName)
    }

    @Test func 모든_녹음에서도_검색과_기간_필터가_동작한다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("중간고사 범위", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("일반 수업", subject: nil, at: date(2026, 3, 3, 10, 0))
        try context.save()

        let library = RecordingLibrary(context: context)
        library.select(.all)
        library.filter.query = "중간"

        #expect(library.recordings.map(\.title) == ["중간고사 범위"])
        // 분류 수는 필터와 상관없는 전체 수다.
        #expect(library.count(for: .all) == 2)
    }

    @Test func 녹음이_없으면_모든_녹음도_비어_있다() throws {
        let library = RecordingLibrary(context: context)
        library.select(.all)
        #expect(library.recordings.isEmpty)
        #expect(library.count(for: .all) == 0)
    }

    @Test func 행에_보일_과목_이름은_과목이_없으면_미분류다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let a = addRecording("a", subject: ds, at: date(2026, 3, 2, 10, 0))
        let b = addRecording("b", subject: nil, at: date(2026, 3, 2, 12, 0))
        try context.save()

        let library = RecordingLibrary(context: context)
        #expect(library.subjectName(of: a) == "자료구조")
        #expect(library.subjectName(of: b) == SubjectManager.unclassifiedName)
        library.select(.unclassified)
        #expect(!library.showsSubjectName)
    }

    @Test func 북마크를_녹음_최신순_시점순으로_모아_보고_북마크_없는_녹음은_뺀다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let monday = addRecording("월요일", subject: ds, at: date(2026, 3, 2, 10, 0))
        let wednesday = addRecording("수요일", subject: ds, at: date(2026, 3, 4, 10, 0))
        addRecording("북마크 없음", subject: ds, at: date(2026, 3, 3, 10, 0))
        let at = date(2026, 3, 5, 0, 0)
        context.insert(Bookmark(time: 300, note: "정리", createdAt: at, recording: monday))
        context.insert(Bookmark(time: 60, note: "시험 범위", createdAt: at, recording: monday))
        context.insert(Bookmark(time: 90, note: "", createdAt: at, recording: wednesday))
        try context.save()

        let library = RecordingLibrary(context: context)
        library.select(.all)

        #expect(library.bookmarkEntries.map(\.recording.title) == ["수요일", "월요일", "월요일"])
        #expect(library.bookmarkEntries.map(\.bookmark.time) == [90, 60, 300])
        #expect(library.bookmarkCount(for: .all) == 3)
    }

    @Test func 북마크_검색은_메모와_녹음_제목을_함께_찾는다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let monday = addRecording("중간고사 대비", subject: ds, at: date(2026, 3, 2, 10, 0))
        let wednesday = addRecording("수요일", subject: ds, at: date(2026, 3, 4, 10, 0))
        let at = date(2026, 3, 5, 0, 0)
        context.insert(Bookmark(time: 10, note: "별건", createdAt: at, recording: monday))
        context.insert(Bookmark(time: 20, note: "시험에 나온다고 함", createdAt: at, recording: wednesday))
        context.insert(Bookmark(time: 30, note: "다른 이야기", createdAt: at, recording: wednesday))
        try context.save()

        let library = RecordingLibrary(context: context)
        library.select(.all)
        library.filter.query = "시험"
        #expect(library.bookmarkEntries.map(\.bookmark.time) == [20])

        library.filter.query = "중간고사"
        #expect(library.bookmarkEntries.map(\.bookmark.time) == [10])

        library.filter.query = "없는말"
        #expect(library.bookmarkEntries.isEmpty)
        // 분류 전체 수는 검색과 상관없다.
        #expect(library.bookmarkCount(for: .all) == 3)
    }

    @Test func 북마크는_고른_과목만_모아_본다() throws {
        let subjects = SubjectManager(context: context)
        let ds = try subjects.add(name: "자료구조", color: .green)
        let os = try subjects.add(name: "운영체제", color: .blue)
        let a = addRecording("a", subject: ds, at: date(2026, 3, 2, 10, 0))
        let b = addRecording("b", subject: os, at: date(2026, 3, 3, 10, 0))
        let at = date(2026, 3, 5, 0, 0)
        context.insert(Bookmark(time: 10, createdAt: at, recording: a))
        context.insert(Bookmark(time: 20, createdAt: at, recording: b))
        try context.save()

        let library = RecordingLibrary(context: context)
        library.select(.subject(os.persistentModelID))
        #expect(library.bookmarkEntries.map(\.bookmark.time) == [20])
        #expect(library.bookmarkCount(for: .subject(ds.persistentModelID)) == 1)
    }

    @Test func 북마크_모아보기에도_기간_필터가_녹음_날짜로_적용된다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let old = addRecording("오래된", subject: ds, at: date(2026, 1, 5, 10, 0))
        let recent = addRecording("최근", subject: ds, at: date(2026, 3, 1, 10, 0))
        let at = date(2026, 3, 5, 0, 0)
        context.insert(Bookmark(time: 10, createdAt: at, recording: old))
        context.insert(Bookmark(time: 20, createdAt: at, recording: recent))
        try context.save()

        let library = RecordingLibrary(context: context, now: { date(2026, 3, 5, 12, 0) }, calendar: seoulCalendar)
        library.select(.all)
        library.filter.period = .last7Days
        #expect(library.bookmarkEntries.map(\.bookmark.time) == [20])
    }

    @Test func 북마크가_하나도_없으면_모아보기가_비어_있다() throws {
        addRecording("a", subject: nil, at: date(2026, 3, 2, 10, 0))
        try context.save()
        let library = RecordingLibrary(context: context)
        library.select(.all)
        #expect(library.bookmarkEntries.isEmpty)
    }

    @Test func 아무것도_고르지_않으면_목록이_비어_있다() throws {
        addRecording("a", subject: nil, at: date(2026, 3, 2, 10, 0))
        try context.save()
        #expect(RecordingLibrary(context: context).recordings.isEmpty)
    }

    @Test func 새_녹음이_저장된_뒤_다시_읽으면_목록에_나타난다() throws {
        let library = RecordingLibrary(context: context)
        library.select(.unclassified)
        #expect(library.recordings.isEmpty)

        addRecording("새 녹음", subject: nil, at: date(2026, 3, 2, 10, 0))
        try context.save()
        library.reload()

        #expect(library.recordings.map(\.title) == ["새 녹음"])
    }

    @Test func 분류별_녹음_수를_센다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("a", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("b", subject: ds, at: date(2026, 3, 3, 10, 0))
        addRecording("c", subject: nil, at: date(2026, 3, 4, 10, 0))
        try context.save()

        let library = RecordingLibrary(context: context)
        #expect(library.count(for: .subject(ds.persistentModelID)) == 2)
        #expect(library.count(for: .unclassified) == 1)
    }

    @Test func 고르고_있던_과목이_삭제되면_선택이_풀린다() throws {
        let subjects = SubjectManager(context: context)
        let ds = try subjects.add(name: "자료구조", color: .green)
        let library = RecordingLibrary(context: context)
        library.select(.subject(ds.persistentModelID))

        try subjects.delete(ds)
        library.reload()

        #expect(library.selection == nil)
        #expect(library.subjects.isEmpty)
    }

    // MARK: 검색과 기간

    /// 테스트끼리 저장된 정렬 선택이 섞이지 않게 매번 새 저장소를 쓴다.
    func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "RecordingLibraryTests-\(UUID().uuidString)"))
    }

    func makeLibrary(now: Date = date(2026, 3, 30, 15, 0), defaults: UserDefaults? = nil) throws -> RecordingLibrary {
        RecordingLibrary(context: context, now: { now }, calendar: seoulCalendar, defaults: try defaults ?? makeDefaults())
    }

    @Test func 검색어를_넣으면_제목으로_걸러진다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("트리 복습", subject: ds, at: date(2026, 3, 29, 10, 0))
        addRecording("그래프", subject: ds, at: date(2026, 3, 28, 10, 0))
        let library = try makeLibrary()
        library.select(.subject(ds.persistentModelID))

        library.filter.query = "트리"
        #expect(library.recordings.map(\.title) == ["트리 복습"])

        library.filter.query = ""
        #expect(library.recordings.count == 2)
    }

    @Test func 기간을_고르면_오래된_녹음이_빠진다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("이번 주", subject: ds, at: date(2026, 3, 28, 10, 0))
        addRecording("지난달", subject: ds, at: date(2026, 2, 10, 10, 0))
        let library = try makeLibrary()
        library.select(.subject(ds.persistentModelID))

        library.filter.period = .last7Days
        #expect(library.recordings.map(\.title) == ["이번 주"])
        library.filter.period = .last30Days
        #expect(library.recordings.map(\.title) == ["이번 주"])
        library.filter.period = .all
        #expect(library.recordings.count == 2)
    }

    @Test func 과목을_바꿔도_검색_조건은_유지된다() throws {
        let subjects = SubjectManager(context: context)
        let ds = try subjects.add(name: "자료구조", color: .green)
        let os = try subjects.add(name: "운영체제", color: .blue)
        addRecording("트리", subject: ds, at: date(2026, 3, 29, 10, 0))
        addRecording("트리 구조", subject: os, at: date(2026, 3, 29, 11, 0))
        addRecording("프로세스", subject: os, at: date(2026, 3, 29, 12, 0))
        let library = try makeLibrary()
        library.filter.query = "트리"

        library.select(.subject(os.persistentModelID))
        #expect(library.recordings.map(\.title) == ["트리 구조"])
    }

    @Test func 사이드바_개수는_검색_조건과_상관없다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("트리", subject: ds, at: date(2026, 3, 29, 10, 0))
        addRecording("그래프", subject: ds, at: date(2026, 3, 28, 10, 0))
        let library = try makeLibrary()
        library.filter.query = "트리"
        #expect(library.count(for: .subject(ds.persistentModelID)) == 2)
    }

    @Test func 다시_읽어도_검색_조건이_적용된다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("트리", subject: ds, at: date(2026, 3, 29, 10, 0))
        let library = try makeLibrary()
        library.select(.subject(ds.persistentModelID))
        library.filter.query = "그래프"
        addRecording("그래프", subject: ds, at: date(2026, 3, 29, 11, 0))
        library.reload()
        #expect(library.recordings.map(\.title) == ["그래프"])
    }

    // MARK: 정렬과 안 들음

    @Test func 기본은_최신순이다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("월", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("수", subject: ds, at: date(2026, 3, 4, 10, 0))
        addRecording("화", subject: ds, at: date(2026, 3, 3, 10, 0))
        let library = try makeLibrary()
        library.select(.all)
        #expect(library.sortOrder == .newestFirst)
        #expect(library.recordings.map(\.title) == ["수", "화", "월"])
    }

    @Test func 오래된_순으로_바꾸면_바로_다시_정렬된다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("월", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("수", subject: ds, at: date(2026, 3, 4, 10, 0))
        addRecording("화", subject: ds, at: date(2026, 3, 3, 10, 0))
        let library = try makeLibrary()
        library.select(.all)

        library.sortOrder = .oldestFirst
        #expect(library.recordings.map(\.title) == ["월", "화", "수"])
        library.sortOrder = .newestFirst
        #expect(library.recordings.map(\.title) == ["수", "화", "월"])
    }

    @Test func 오래된_순은_검색과_다시_읽기_뒤에도_유지된다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("트리 1", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("트리 2", subject: ds, at: date(2026, 3, 4, 10, 0))
        addRecording("그래프", subject: ds, at: date(2026, 3, 3, 10, 0))
        let library = try makeLibrary()
        library.select(.all)
        library.sortOrder = .oldestFirst

        library.filter.query = "트리"
        #expect(library.recordings.map(\.title) == ["트리 1", "트리 2"])
        addRecording("트리 0", subject: ds, at: date(2026, 3, 1, 10, 0))
        library.reload()
        #expect(library.recordings.map(\.title) == ["트리 0", "트리 1", "트리 2"])
    }

    @Test func 정렬_선택은_앱을_다시_켜도_기억한다() throws {
        let defaults = try makeDefaults()
        let first = try makeLibrary(defaults: defaults)
        first.sortOrder = .oldestFirst

        let second = try makeLibrary(defaults: defaults)
        #expect(second.sortOrder == .oldestFirst)
    }

    @Test func 저장된_정렬값이_이상하면_최신순으로_시작한다() throws {
        let defaults = try makeDefaults()
        defaults.set("엉뚱한 값", forKey: RecordingLibrary.sortOrderKey)
        let library = try makeLibrary(defaults: defaults)
        #expect(library.sortOrder == .newestFirst)
    }

    @Test func 정렬을_바꿔도_북마크_모아보기는_최근_녹음부터다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let old = addRecording("옛날", subject: ds, at: date(2026, 3, 2, 10, 0))
        let recent = addRecording("최근", subject: ds, at: date(2026, 3, 4, 10, 0))
        context.insert(Bookmark(time: 10, note: "a", createdAt: date(2026, 3, 2, 10, 1), recording: old))
        context.insert(Bookmark(time: 10, note: "b", createdAt: date(2026, 3, 4, 10, 1), recording: recent))
        let library = try makeLibrary()
        library.select(.all)
        library.sortOrder = .oldestFirst
        #expect(library.bookmarkEntries.map(\.recording.title) == ["최근", "옛날"])
    }

    @Test func 재생_기록이_없고_위치도_없으면_안_들은_녹음이다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let fresh = addRecording("새것", subject: ds, at: date(2026, 3, 2, 10, 0))
        let resumed = addRecording("듣던 것", subject: ds, at: date(2026, 3, 3, 10, 0))
        resumed.lastPlayedPosition = 120
        let finished = addRecording("끝까지 들은 것", subject: ds, at: date(2026, 3, 4, 10, 0))
        finished.lastPlayedAt = date(2026, 3, 5, 9, 0)
        finished.lastPlayedPosition = 0

        #expect(fresh.isUnplayed)
        #expect(!resumed.isUnplayed)
        #expect(!finished.isUnplayed)
    }

    @Test func 안_들은_것만_보면_들은_녹음이_빠진다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("새것", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("듣던 것", subject: ds, at: date(2026, 3, 3, 10, 0)).lastPlayedPosition = 120
        addRecording("끝까지 들은 것", subject: ds, at: date(2026, 3, 4, 10, 0)).lastPlayedAt = date(2026, 3, 5, 9, 0)
        let library = try makeLibrary()
        library.select(.all)

        library.filter.unplayedOnly = true
        #expect(library.recordings.map(\.title) == ["새것"])
        library.filter.unplayedOnly = false
        #expect(library.recordings.count == 3)
    }

    @Test func 안_들은_것만은_정렬_검색과_함께_적용된다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("트리 1", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("트리 2", subject: ds, at: date(2026, 3, 4, 10, 0))
        addRecording("트리 들음", subject: ds, at: date(2026, 3, 3, 10, 0)).lastPlayedAt = date(2026, 3, 5, 9, 0)
        addRecording("그래프", subject: ds, at: date(2026, 3, 1, 10, 0))
        let library = try makeLibrary()
        library.select(.all)
        library.filter = RecordingFilter(query: "트리", unplayedOnly: true)
        #expect(library.recordings.map(\.title) == ["트리 2", "트리 1"])
        library.sortOrder = .oldestFirst
        #expect(library.recordings.map(\.title) == ["트리 1", "트리 2"])
    }

    @Test func 안_들은_것만은_사이드바_개수에_영향이_없다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("새것", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("들은 것", subject: ds, at: date(2026, 3, 3, 10, 0)).lastPlayedAt = date(2026, 3, 5, 9, 0)
        let library = try makeLibrary()
        library.filter.unplayedOnly = true
        #expect(library.count(for: .subject(ds.persistentModelID)) == 2)
    }

    // MARK: 학기별 묶음

    func addSubject(_ name: String, semester: String, scheduled: Bool = true) throws -> Subject {
        let subject = try SubjectManager(context: context).add(name: name, color: .blue)
        subject.semester = semester
        if scheduled {
            context.insert(TimeSlot(try period(.monday, (9, 0), (10, 0)), subject: subject))
        }
        try context.save()
        return subject
    }

    @Test func 과목을_학기별로_묶고_지난_학기는_접혀_있다() throws {
        _ = try addSubject("자료구조", semester: "2026년 2학기")
        _ = try addSubject("운영체제", semester: "2026년 2학기")
        _ = try addSubject("미적분", semester: "2025년 2학기")
        _ = try addSubject("직접 만듦", semester: "", scheduled: false)

        let library = try makeLibrary()

        #expect(library.semesterSections.map(\.title) == ["2026년 2학기", "2025년 2학기", "기타"])
        #expect(library.subjects(in: library.semesterSections[0]).map(\.name) == ["운영체제", "자료구조"])
        #expect(library.semesterSections.map { library.isExpanded($0) } == [true, false, true])
    }

    @Test func 펼침을_바꾸면_다음_실행에도_기억한다() throws {
        _ = try addSubject("자료구조", semester: "2026년 2학기")
        _ = try addSubject("미적분", semester: "2025년 2학기")
        let defaults = try makeDefaults()
        let library = try makeLibrary(defaults: defaults)
        library.setExpanded(true, for: library.semesterSections[1])
        library.setExpanded(false, for: library.semesterSections[0])

        let reopened = try makeLibrary(defaults: defaults)

        #expect(reopened.semesterSections.map { reopened.isExpanded($0) } == [false, true])
    }

    @Test func 접힌_학기의_과목을_고르거나_검색해도_선택은_풀리지_않는다() throws {
        let old = try addSubject("미적분", semester: "2025년 2학기")
        _ = try addSubject("자료구조", semester: "2026년 2학기")
        addRecording("미적분 1주차", subject: old, at: date(2025, 9, 1, 10, 0))
        try context.save()
        let library = try makeLibrary()
        let oldSection = try #require(library.semesterSections.last)
        #expect(!library.isExpanded(oldSection))

        library.select(.subject(old.persistentModelID))
        library.filter.query = "1주차"
        library.reload()

        #expect(library.selection == .subject(old.persistentModelID))
        #expect(library.recordings.map(\.title) == ["미적분 1주차"])
    }

    @Test func 시간표를_가져와_학기가_바뀌면_reload_뒤에_묶음도_바뀐다() throws {
        let subject = try addSubject("자료구조", semester: "", scheduled: false)
        let library = try makeLibrary()
        #expect(library.semesterSections.map(\.title) == ["기타"])

        subject.semester = "2026년 2학기"
        try context.save()
        library.reload()

        #expect(library.semesterSections.map(\.title) == ["2026년 2학기"])
        #expect(library.semesterSections.first?.isCurrent == true)
    }
}
#endif
