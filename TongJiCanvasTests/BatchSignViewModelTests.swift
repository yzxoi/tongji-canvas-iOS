import Testing
import Foundation
@testable import TongJiCanvas

@MainActor
struct BatchSignViewModelTests {

    private func makeVM() -> BatchSignViewModel {
        BatchSignViewModel(attendanceURL: URL(string: "https://canvas.tongji.edu.cn/sign")!)
    }

    // MARK: - progress

    @Test func progressIsZeroWhenEmpty() {
        let vm = makeVM()
        #expect(vm.progress == 0.0)
    }

    @Test func progressIsHalfWhenOneOfTwoDone() {
        let vm = makeVM()
        vm.statuses = [UUID(): .success, UUID(): .signing]
        #expect(vm.progress == 0.5)
    }

    @Test func progressIsOneWhenAllDone() {
        let vm = makeVM()
        vm.statuses = [UUID(): .success, UUID(): .failure, UUID(): .expired]
        #expect(vm.progress == 1.0)
    }

    // MARK: - successCount / failureCount

    @Test func successCountCounts() {
        let vm = makeVM()
        vm.statuses = [UUID(): .success, UUID(): .success, UUID(): .failure]
        #expect(vm.successCount == 2)
    }

    @Test func failureCountIncludesExpired() {
        let vm = makeVM()
        vm.statuses = [UUID(): .success, UUID(): .failure, UUID(): .expired]
        #expect(vm.failureCount == 2)
    }

    // MARK: - hasActiveSigning

    @Test func hasActiveSigningFalseWhenEmpty() {
        let vm = makeVM()
        #expect(!vm.hasActiveSigning)
    }

    @Test func hasActiveSigningTrueWhenAnySigningStatus() {
        let vm = makeVM()
        vm.statuses = [UUID(): .success, UUID(): .signing]
        #expect(vm.hasActiveSigning)
    }

    @Test func hasActiveSigningFalseWhenAllComplete() {
        let vm = makeVM()
        vm.statuses = [UUID(): .success, UUID(): .failure]
        #expect(!vm.hasActiveSigning)
    }

    // MARK: - toggleExpanded

    @Test func toggleExpandedAddsId() {
        let vm = makeVM()
        let id = UUID()
        vm.toggleExpanded(id)
        #expect(vm.expandedIds.contains(id))
    }

    @Test func toggleExpandedRemovesIfAlreadyPresent() {
        let vm = makeVM()
        let id = UUID()
        vm.toggleExpanded(id)
        vm.toggleExpanded(id)
        #expect(!vm.expandedIds.contains(id))
    }

    // MARK: - SignStatus labels & icons

    @Test func signStatusLabels() {
        #expect(SignStatus.signing.label == "签到中")
        #expect(SignStatus.success.label == "签到成功")
        #expect(SignStatus.failure.label == "签到失败")
        #expect(SignStatus.expired.label == "认证过期")
    }

    @Test func signStatusIcons() {
        #expect(SignStatus.signing.icon == "arrow.clockwise")
        #expect(SignStatus.success.icon == "checkmark.circle.fill")
        #expect(SignStatus.failure.icon == "xmark.circle.fill")
        #expect(SignStatus.expired.icon == "exclamationmark.triangle.fill")
    }
}
