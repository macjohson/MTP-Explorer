import AppKit
import SwiftUI

@MainActor
final class ExplorerModel: ObservableObject {
    @Published var devices: [MTPDevice] = []
    @Published var connectedDevice: MTPDevice?
    @Published var deviceName = "MTP Explorer"
    @Published var storages: [MTPStorage] = []
    @Published var selectedStorage: MTPStorage?
    @Published var path: [FolderLocation] = []
    @Published var items: [MTPItem] = []
    @Published var selection: Set<UInt32> = []
    @Published var search = ""
    @Published var viewMode: ExplorerViewMode = .list
    @Published var sort: ExplorerSort = .name
    @Published var ascending = true
    @Published var showHidden = false
    @Published var busy = false
    @Published var scanning = false
    @Published var transferTitle: String?
    @Published var transferProgress = 0.0
    @Published var cameraConflictDevice: MTPDevice?
    @Published var errorMessage: String?
    @Published var showNewFolder = false
    @Published var renameTarget: MTPItem?
    @Published var showDelete = false
    @Published var showInspector = false
    @Published var demoMode = false
    private var transferControl: TransferControl?
    private var backStack: [[FolderLocation]] = []
    private var forwardStack: [[FolderLocation]] = []
    private var monitor: Task<Void, Never>?
    let service = MTPService.shared
    var parentID: UInt32 { path.last?.id ?? 0 }
    var folderName: String { path.last?.name ?? selectedStorage?.displayName ?? "MTP Explorer" }
    var canGoBack: Bool { !backStack.isEmpty && !busy }
    var canGoForward: Bool { !forwardStack.isEmpty && !busy }
    var canWrite: Bool { selectedStorage?.writable == true && !busy && !demoMode }
    var selectedItems: [MTPItem] { visibleItems.filter { selection.contains($0.id) } }
    var visibleItems: [MTPItem] {
        items.filter { (showHidden || !$0.name.hasPrefix(".")) && (search.isEmpty || $0.name.localizedStandardContains(search)) }
            .sorted { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                let comparison: ComparisonResult
                switch sort {
                case .name: comparison = lhs.name.localizedStandardCompare(rhs.name)
                case .modified: comparison = lhs.modified == rhs.modified ? lhs.name.localizedStandardCompare(rhs.name) : (lhs.modified < rhs.modified ? .orderedAscending : .orderedDescending)
                case .size: comparison = lhs.size == rhs.size ? lhs.name.localizedStandardCompare(rhs.name) : (lhs.size < rhs.size ? .orderedAscending : .orderedDescending)
                case .kind: comparison = lhs.kind == rhs.kind ? lhs.name.localizedStandardCompare(rhs.name) : lhs.kind.localizedStandardCompare(rhs.kind)
                }
                return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
    }
    func start() {
        guard monitor == nil else { return }
        if ProcessInfo.processInfo.arguments.contains("--demo") { loadDemo(); return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.busy && !self.demoMode { await self.scan(silent: true) }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
    func scan(silent: Bool = false) async {
        guard !busy, !scanning, !demoMode else { return }
        scanning = true
        defer { scanning = false }
        do {
            devices = try await service.scan()
            if let device = connectedDevice, !devices.contains(where: { $0.id == device.id }) {
                await disconnect()
                errorMessage = "设备已断开连接。请检查 USB 数据线后重新连接。"
            }
        } catch { if !silent { report(error) } }
    }
    func connect(_ device: MTPDevice, releasingCamera: Bool = false) async {
        guard !busy, connectedDevice?.id != device.id else { return }
        busy = true
        defer { busy = false }
        resetBrowser()
        do {
            let (name, volumes) = try await service.connect(device, releasingCamera: releasingCamera)
            connectedDevice = device; deviceName = name; storages = volumes
            guard let first = volumes.first else { throw ExplorerError.message("设备未提供可访问的存储。请解锁设备并允许文件传输。") }
            selectedStorage = first
            items = try await service.list(storage: first.id, parent: 0)
        } catch {
            await service.disconnect(); connectedDevice = nil; storages = []; selectedStorage = nil
            let cameraBusy = await service.cameraBusy(device)
            report(error)
            if cameraBusy { cameraConflictDevice = device }
        }
    }
    func disconnect() async {
        guard !busy else { return }
        busy = true
        await service.disconnect()
        connectedDevice = nil; deviceName = "MTP Explorer"; storages = []; selectedStorage = nil
        resetBrowser(); busy = false
    }
    private func resetBrowser() {
        items = []; selection = []; path = []; backStack = []; forwardStack = []; search = ""
    }
    func selectStorage(_ storage: MTPStorage) async {
        guard !busy else { return }
        selectedStorage = storage; resetBrowser()
        await refresh()
    }
    func refresh() async {
        guard let storage = selectedStorage, !busy else { return }
        if demoMode { loadDemoItems(); return }
        busy = true
        defer { busy = false }
        do {
            let result = try await service.list(storage: storage.id, parent: parentID)
            items = result; selection.formIntersection(Set(result.map(\.id)))
            let volumes = try await service.storages()
            storages = volumes
            if let refreshed = volumes.first(where: { $0.id == storage.id }) { selectedStorage = refreshed }
        } catch { report(error) }
    }
    func open(_ item: MTPItem) async {
        guard !busy else { return }
        if item.isFolder { await navigate(path + [FolderLocation(id: item.id, name: item.name)]) }
        else { await openFile(item) }
    }
    func navigate(_ destination: [FolderLocation], record: Bool = true) async {
        guard !busy, let storage = selectedStorage else { return }
        if demoMode {
            if record { backStack.append(path); forwardStack = [] }
            path = destination; selection = []; search = ""; loadDemoItems(); return
        }
        busy = true; defer { busy = false }
        do {
            let result = try await service.list(storage: storage.id, parent: destination.last?.id ?? 0)
            if record { backStack.append(path); forwardStack = [] }
            path = destination; items = result; selection = []; search = ""
        } catch { report(error) }
    }
    func goBack() async {
        guard canGoBack, let destination = backStack.last else { return }
        let current = path
        await navigate(destination, record: false)
        if path == destination { backStack.removeLast(); forwardStack.append(current) }
    }
    func goForward() async {
        guard canGoForward, let destination = forwardStack.last else { return }
        let current = path
        await navigate(destination, record: false)
        if path == destination { forwardStack.removeLast(); backStack.append(current) }
    }
    func goUp() async { if !path.isEmpty { await navigate(Array(path.dropLast())) } }
    func createFolder(_ name: String) async {
        guard canWrite, let storage = selectedStorage else { return }
        busy = true
        do { _ = try await service.createFolder(storage: storage.id, parent: parentID, name: name) }
        catch { report(error) }
        busy = false; await refresh()
    }
    func rename(_ item: MTPItem, to name: String) async {
        guard canWrite else { return }
        busy = true
        do { try await service.rename(item, to: name) } catch { report(error) }
        busy = false; await refresh()
    }
    func deleteSelection() async {
        guard canWrite else { return }
        let targets = selectedItems
        busy = true
        do { try await service.delete(targets) } catch { report(error, partial: true) }
        busy = false; await refresh()
    }
    func chooseUpload() {
        guard canWrite else { return }
        let panel = NSOpenPanel()
        panel.message = "选择要导入设备的文件或文件夹"
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in await self?.upload(panel.urls) }
        }
    }
    func upload(_ urls: [URL]) async {
        guard canWrite, let storage = selectedStorage, !urls.isEmpty else { return }
        let parent = parentID
        await transfer(title: "正在导入 \(urls.count) 个项目") { control in
            try await self.service.upload(urls, storage: storage.id, parent: parent, control: control)
        }
    }
    func chooseDownload() {
        let targets = selectedItems
        guard !targets.isEmpty, !busy, !demoMode else { return }
        let panel = NSOpenPanel()
        panel.message = "选择导出位置（现有同名文件不会被覆盖）"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.transfer(title: "正在导出 \(targets.count) 个项目") { control in
                    try await self?.service.download(targets, to: url, control: control)
                }
            }
        }
    }
    private func openFile(_ item: MTPItem) async {
        guard !demoMode else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MTPExplorer/\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { report(error); return }
        var completed = false
        await transfer(title: "正在打开 \(item.name)") { control in
            try await self.service.download([item], to: directory, control: control)
            completed = true
        }
        if completed { NSWorkspace.shared.open(directory.appendingPathComponent(item.name)) }
    }
    private func transfer(title: String, operation: (TransferControl) async throws -> Void) async {
        guard !busy else { return }
        busy = true; transferTitle = title; transferProgress = 0
        let control = TransferControl { [weak self] progress in
            Task { @MainActor in self?.transferProgress = progress }
        }
        transferControl = control
        do { try await operation(control) }
        catch is CancellationError { errorMessage = "传输已取消。已完成的文件会保留，请检查目标文件夹；未完成的本地文件已清理。" }
        catch { report(error, partial: true) }
        transferControl = nil; transferTitle = nil; busy = false
        await refresh()
    }
    func cancelTransfer() { transferControl?.cancel() }
    func report(_ error: Error, partial: Bool = false) {
        cameraConflictDevice = nil
        errorMessage = error.localizedDescription + (partial ? "\n\n部分项目可能已完成，请刷新并检查目标位置。" : "")
    }
    func loadDemo() {
        demoMode = true
        connectedDevice = MTPDevice(id: "demo", name: "Pixel 9 Pro", bus: 0, address: 0)
        deviceName = "Pixel 9 Pro"
        let storage = MTPStorage(id: 1, name: "内部共享存储空间", capacity: 128_000_000_000, free: 83_400_000_000, writable: false)
        storages = [storage]; selectedStorage = storage; loadDemoItems()
    }
    private func loadDemoItems() {
        let names: [(String, Bool, UInt64)] = path.isEmpty ? [
            ("Alarms", true, 0), ("Android", true, 0), ("Audiobooks", true, 0), ("DCIM", true, 0),
            ("Documents", true, 0), ("Download", true, 0), ("Movies", true, 0), ("Music", true, 0),
            ("Notifications", true, 0), ("Pictures", true, 0), ("Podcasts", true, 0), ("Recordings", true, 0),
            ("旅行计划.pdf", false, 2_430_000), ("设备说明.txt", false, 1240)
        ] : [("Camera", true, 0), ("IMG_20261026.jpg", false, 4_520_000), ("Weekend.mp4", false, 128_000_000)]
        items = names.enumerated().map { index, value in
            MTPItem(id: UInt32(index + 1), parent: parentID, storage: 1, name: value.0, size: value.2,
                    modified: 1_792_900_000 - Int64(index * 3600), isFolder: value.1)
        }
    }
}
