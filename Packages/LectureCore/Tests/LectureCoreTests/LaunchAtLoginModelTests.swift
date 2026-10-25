#if canImport(SwiftData)
import Foundation
import Testing
@testable import LectureCore

@MainActor
final class FakeLoginItem: LoginItemControlling {
    var status: LoginItemStatus = .notRegistered
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}

@MainActor
@Suite struct LaunchAtLoginModelTests {
    let item = FakeLoginItem()

    @Test func 처음에는_꺼져_있고_등록하지_않는다() {
        let model = LaunchAtLoginModel(controller: item)
        #expect(!model.isEnabled)
        #expect(model.message == nil)
        #expect(item.registerCalls == 0)
    }

    @Test func 켜면_등록하고_끄면_해제한다() {
        let model = LaunchAtLoginModel(controller: item)
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(item.registerCalls == 1)
        model.setEnabled(false)
        #expect(!model.isEnabled)
        #expect(item.unregisterCalls == 1)
    }

    @Test func 이미_등록돼_있으면_켜진_채로_시작한다() {
        item.status = .enabled
        #expect(LaunchAtLoginModel(controller: item).isEnabled)
    }

    @Test func 허용을_기다리는_중이면_켜진_것으로_보이고_안내를_보인다() {
        item.status = .requiresApproval
        let model = LaunchAtLoginModel(controller: item)
        #expect(model.isEnabled)
        #expect(model.message?.contains("로그인 항목") == true)
    }

    @Test func 등록할_수_없는_위치면_꺼진_채로_안내한다() {
        item.status = .notFound
        let model = LaunchAtLoginModel(controller: item)
        #expect(!model.isEnabled)
        #expect(model.message != nil)
    }

    @Test func 켜기에_실패하면_꺼진_채로_오류를_보인다() {
        item.registerError = CocoaError(.fileWriteNoPermission)
        let model = LaunchAtLoginModel(controller: item)
        model.setEnabled(true)
        #expect(!model.isEnabled)
        #expect(model.message?.contains("켜지 못했습니다") == true)
    }

    @Test func 끄기에_실패하면_켜진_채로_오류를_보인다() {
        item.status = .enabled
        item.unregisterError = CocoaError(.fileWriteNoPermission)
        let model = LaunchAtLoginModel(controller: item)
        model.setEnabled(false)
        #expect(model.isEnabled)
        #expect(model.message?.contains("끄지 못했습니다") == true)
    }

    @Test func 시스템_설정에서_바꾼_상태를_다시_읽는다() {
        let model = LaunchAtLoginModel(controller: item)
        item.status = .enabled
        model.refresh()
        #expect(model.isEnabled)
        item.status = .notRegistered
        model.refresh()
        #expect(!model.isEnabled)
    }

    @Test func 성공하면_이전_오류_안내가_사라진다() {
        item.registerError = CocoaError(.fileWriteNoPermission)
        let model = LaunchAtLoginModel(controller: item)
        model.setEnabled(true)
        item.registerError = nil
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(model.message == nil)
    }
}
#endif
