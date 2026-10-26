import XCTest

final class ExplorerTests: XCTestCase {
    func testOnlyExactSystemCameraOwnerIsRecognized() {
        XCTAssertEqual(mtp_camera_owner_pid("pid 12345, ptpcamerad"), 12345)
        for owner in ["pid 0, ptpcamerad", "pid 1, ptpcamerad", "pid -1, ptpcamerad",
                      "pid 12345, adb", "pid 12345, other-ptpcamerad",
                      "pid 12345, ptpcamerad extra", "ptpcamerad", ""] {
            XCTAssertEqual(mtp_camera_owner_pid(owner), 0, owner)
        }
        XCTAssertEqual(mtp_camera_owner_pid(nil), 0)
    }
    func testDeviceDiscoveryAcceptsOptionalDiagnostic() throws {
        let data = Data(#"{"id":"2:1","name":"平板","bus":2,"address":1,"accessIssue":"系统相机服务占用"}"#.utf8)
        let device = try JSONDecoder().decode(MTPDevice.self, from: data)
        XCTAssertEqual(device.accessIssue, "系统相机服务占用")
        let legacy = Data(#"{"id":"2:1","name":"平板","bus":2,"address":1}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(MTPDevice.self, from: legacy).accessIssue)
    }
    func testRejectsTraversalAndUnsafeNames() {
        for name in ["", " ", ".", "..", "../escape", "a/b", "a\\b", "a:b", "a\0b", String(repeating: "字", count: 86)] {
            XCTAssertThrowsError(try MTPService.validate(name), "Accepted unsafe name: \(name)")
        }
    }
    func testAcceptsUnicodeNames() {
        for name in ["照片 2026", "旅行计划.pdf", ".hidden", "a..b", "📷 Camera", String(repeating: "a", count: 255)] {
            XCTAssertNoThrow(try MTPService.validate(name))
        }
    }
    func testCancellationIsVisible() {
        let control = TransferControl { _ in }
        XCTAssertFalse(control.isCancelled)
        control.cancel()
        XCTAssertTrue(control.isCancelled)
    }
    func testStorageCapacityNeverUnderflows() {
        let storage = MTPStorage(id: 1, name: "", capacity: 5, free: 10, writable: false)
        XCTAssertEqual(storage.usedFraction, 0)
        XCTAssertEqual(storage.displayName, "内部存储")
    }
    @MainActor func testDemoIsReadOnlyAndFoldersSortFirst() {
        let model = ExplorerModel(); model.loadDemo()
        XCTAssertFalse(model.canWrite)
        XCTAssertEqual(model.visibleItems.count, 14)
        let firstFile = model.visibleItems.firstIndex { !$0.isFolder }!
        XCTAssertTrue(model.visibleItems[..<firstFile].allSatisfy(\.isFolder))
        model.ascending = false
        XCTAssertTrue(model.visibleItems.first!.isFolder)
    }
    @MainActor func testSearchIsScopedAndCaseInsensitive() {
        let model = ExplorerModel(); model.loadDemo()
        model.search = "dcim"
        XCTAssertEqual(model.visibleItems.map(\.name), ["DCIM"])
        model.search = "旅行"
        XCTAssertEqual(model.visibleItems.map(\.name), ["旅行计划.pdf"])
    }
    @MainActor func testHistoryAndNavigation() async {
        let model = ExplorerModel(); model.loadDemo()
        let folder = model.items.first { $0.name == "DCIM" }!
        await model.open(folder)
        XCTAssertEqual(model.parentID, folder.id)
        XCTAssertTrue(model.canGoBack)
        await model.goBack()
        XCTAssertTrue(model.path.isEmpty)
        XCTAssertTrue(model.canGoForward)
        await model.goForward()
        XCTAssertEqual(model.path.last?.name, "DCIM")
        await model.goUp()
        XCTAssertTrue(model.path.isEmpty)
    }
    @MainActor func testHiddenFilesAndSelection() {
        let model = ExplorerModel(); model.loadDemo()
        model.items.append(MTPItem(id: 99, parent: 0, storage: 1, name: ".hidden", size: 1, modified: 0, isFolder: false))
        XCTAssertFalse(model.visibleItems.contains { $0.id == 99 })
        model.showHidden = true
        XCTAssertTrue(model.visibleItems.contains { $0.id == 99 })
        model.selection = [99]
        XCTAssertEqual(model.selectedItems.first?.name, ".hidden")
    }
    func testDisconnectedOperationsFailGracefully() async {
        let service = MTPService.shared
        do {
            _ = try await service.list(storage: 1, parent: 0)
            XCTFail("An unconnected session must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("未连接")) }
    }
}
