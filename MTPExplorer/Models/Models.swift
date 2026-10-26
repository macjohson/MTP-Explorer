import Foundation
import UniformTypeIdentifiers

struct MTPDevice: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bus: UInt32
    let address: UInt8
    var accessIssue: String? = nil
}
struct MTPStorage: Codable, Identifiable, Hashable, Sendable {
    let id: UInt32
    let name: String
    let capacity: UInt64
    let free: UInt64
    let writable: Bool
    var displayName: String { name.isEmpty ? "内部存储" : name }
    var usedFraction: Double { capacity == 0 ? 0 : Double(capacity - min(free, capacity)) / Double(capacity) }
}
struct MTPItem: Codable, Identifiable, Hashable, Sendable {
    let id: UInt32
    let parent: UInt32
    let storage: UInt32
    let name: String
    let size: UInt64
    let modified: Int64
    let isFolder: Bool
    var date: Date { Date(timeIntervalSince1970: TimeInterval(modified)) }
    var fileExtension: String { (name as NSString).pathExtension.lowercased() }
    var kind: String {
        if isFolder { return "文件夹" }
        return UTType(filenameExtension: fileExtension)?.localizedDescription ?? "文件"
    }
    var symbol: String {
        if isFolder { return "folder.fill" }
        let type = UTType(filenameExtension: fileExtension)
        if type?.conforms(to: .image) == true { return "photo" }
        if type?.conforms(to: .movie) == true { return "film" }
        if type?.conforms(to: .audio) == true { return "music.note" }
        if type?.conforms(to: .archive) == true { return "doc.zipper" }
        if type?.conforms(to: .pdf) == true { return "doc.richtext" }
        return "doc.text"
    }
    var sizeLabel: String { isFolder ? "—" : ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file) }
}
struct FolderLocation: Identifiable, Hashable, Sendable {
    let id: UInt32
    let name: String
}
enum ExplorerViewMode: String, CaseIterable { case list, icons }
enum ExplorerSort: String, CaseIterable {
    case name = "名称", modified = "修改日期", size = "大小", kind = "种类"
}
enum ExplorerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

// A lock allows the main thread to cancel a synchronous libmtp transfer safely.
final class TransferControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var lastUpdate = Date.distantPast
    private let onProgress: @Sendable (Double) -> Void
    init(report: @escaping @Sendable (Double) -> Void) { self.onProgress = report }
    func report(_ progress: Double) {
        lock.lock()
        let now = Date()
        let shouldUpdate = progress >= 1 || now.timeIntervalSince(lastUpdate) >= 0.05
        if shouldUpdate { lastUpdate = now }
        lock.unlock()
        if shouldUpdate { onProgress(progress) }
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}
