import Foundation

private let progressCallback: @convention(c) (UInt64, UInt64, UnsafeMutableRawPointer?) -> Int32 = { done, total, context in
    guard let context else { return 0 }
    let control = Unmanaged<TransferControl>.fromOpaque(context).takeUnretainedValue()
    if control.isCancelled { return 1 }
    control.report(total == 0 ? 0 : min(1, Double(done) / Double(total)))
    return 0
}

/// All libmtp calls, including discovery and release, run on this actor's executor.
/// No USB I/O runs on the main actor. libmtp's global state is never used concurrently.
actor MTPService {
    static let shared = MTPService()
    private var connection: OpaquePointer?
    private init() {}

    private func failure() -> ExplorerError { .message(String(cString: mtp_error())) }
    private func session() throws -> OpaquePointer {
        guard let connection else { throw ExplorerError.message("设备未连接，请重新连接设备。") }
        return connection
    }
    private func decode<T: Decodable>(_ pointer: UnsafeMutablePointer<CChar>?, as type: T.Type) throws -> T {
        guard let pointer else { throw failure() }
        defer { mtp_free(pointer) }
        return try JSONDecoder().decode(type, from: Data(bytes: pointer, count: strlen(pointer)))
    }
    func scan() throws -> [MTPDevice] { try decode(mtp_scan(), as: [MTPDevice].self) }
    func connect(_ device: MTPDevice, releasingCamera: Bool = false) throws -> (String, [MTPStorage]) {
        disconnect()
        let opened = releasingCamera ? mtp_connect_releasing_camera(device.bus, device.address) : mtp_connect(device.bus, device.address)
        guard let value = opened else { throw failure() }
        connection = value
        do {
            let namePointer = mtp_name(value)
            let reportedName = namePointer.map { String(cString: $0) } ?? ""
            let name = reportedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? device.name : reportedName
            mtp_free(namePointer)
            return (name, try storages())
        } catch { disconnect(); throw error }
    }
    func cameraBusy(_ device: MTPDevice) -> Bool { mtp_camera_busy(device.bus, device.address) }
    func disconnect() { if let connection { mtp_disconnect(connection) }; connection = nil }
    func storages() throws -> [MTPStorage] { try decode(mtp_storages(try session()), as: [MTPStorage].self) }
    func list(storage: UInt32, parent: UInt32) throws -> [MTPItem] {
        try decode(mtp_list(try session(), storage, parent), as: [MTPItem].self)
    }
    func createFolder(storage: UInt32, parent: UInt32, name: String) throws -> UInt32 {
        try Self.validate(name)
        try ensureAvailable(name: name, storage: storage, parent: parent)
        let id = mtp_mkdir(try session(), storage, parent, name)
        guard id != 0 else { throw failure() }; return id
    }
    func rename(_ item: MTPItem, to name: String) throws {
        try Self.validate(name)
        if name == item.name { return }
        try ensureAvailable(name: name, storage: item.storage, parent: item.parent)
        guard mtp_rename(try session(), item.id, name) else { throw failure() }
    }
    func delete(_ items: [MTPItem]) throws {
        for item in items { try deleteRecursively(item) }
    }
    private func deleteRecursively(_ item: MTPItem) throws {
        if item.isFolder {
            for child in try list(storage: item.storage, parent: item.id) { try deleteRecursively(child) }
        }
        guard mtp_delete(try session(), item.id) else { throw failure() }
    }
    func download(_ items: [MTPItem], to directory: URL, control: TransferControl) throws {
        for item in items {
            try checkCancelled(control)
            try downloadOne(item, to: directory, control: control)
        }
    }
    private func downloadOne(_ item: MTPItem, to directory: URL, control: TransferControl) throws {
        // Device names are untrusted and must remain a single local path component.
        try Self.validate(item.name)
        let destination = directory.appendingPathComponent(item.name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ExplorerError.message("目标位置已存在“\(item.name)”，请选择其他文件夹。")
        }
        if item.isFolder {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            for child in try list(storage: item.storage, parent: item.id) {
                try checkCancelled(control)
                try downloadOne(child, to: destination, control: control)
            }
        } else {
            // Transfer into a unique temporary file; publish atomically only after success.
            let temporary = directory.appendingPathComponent(".mtp-\(UUID().uuidString).partial")
            defer { try? FileManager.default.removeItem(at: temporary) }
            let result = mtp_download(try session(), item.id, temporary.path, progressCallback,
                                      Unmanaged.passUnretained(control).toOpaque())
            try checkCancelled(control)
            guard result else { throw failure() }
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
    func upload(_ urls: [URL], storage: UInt32, parent: UInt32, control: TransferControl) throws {
        for url in urls {
            try checkCancelled(control)
            try uploadOne(url, storage: storage, parent: parent, control: control)
        }
    }
    private func uploadOne(_ url: URL, storage: UInt32, parent: UInt32, control: TransferControl) throws {
        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
        guard info.isSymbolicLink != true else { throw ExplorerError.message("不支持导入符号链接：\(url.lastPathComponent)") }
        let name = url.lastPathComponent
        try Self.validate(name)
        if info.isDirectory == true {
            let folder = try createFolder(storage: storage, parent: parent, name: name)
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            for child in children {
                try checkCancelled(control)
                try uploadOne(child, storage: storage, parent: folder, control: control)
            }
        } else {
            guard info.isRegularFile == true else { throw ExplorerError.message("只支持导入普通文件和文件夹。") }
            try ensureAvailable(name: name, storage: storage, parent: parent)
            let result = mtp_upload(try session(), storage, parent, url.path, name, progressCallback,
                                   Unmanaged.passUnretained(control).toOpaque())
            try checkCancelled(control)
            guard result else { throw failure() }
        }
    }
    private func ensureAvailable(name: String, storage: UInt32, parent: UInt32) throws {
        if try list(storage: storage, parent: parent).contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            throw ExplorerError.message("已存在同名项目“\(name)”，请先重命名后再试。")
        }
    }
    private func checkCancelled(_ control: TransferControl) throws {
        if control.isCancelled { throw CancellationError() }
    }
    static func validate(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
              !name.contains(":"), !name.contains("\0"), name.utf8.count <= 255 else {
            throw ExplorerError.message("名称不能为空、不能超过 255 字节，也不能包含 /、\\ 或 :。")
        }
    }
}
