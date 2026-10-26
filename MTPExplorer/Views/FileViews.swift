import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileGlyph: View {
    let item: MTPItem
    let size: CGFloat
    var body: some View {
        Image(nsImage: icon).resizable().scaledToFit().frame(width: size, height: size)
    }
    private var icon: NSImage {
        if item.isFolder { return NSWorkspace.shared.icon(for: .folder) }
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: item.fileExtension) ?? .data)
    }
}

struct FileListView: View {
    @EnvironmentObject private var model: ExplorerModel
    private var sortOrder: Binding<[KeyPathComparator<MTPItem>]> {
        Binding(get: {
            let order: SortOrder = model.ascending ? .forward : .reverse
            switch model.sort {
            case .name: return [KeyPathComparator(\MTPItem.name, order: order)]
            case .modified: return [KeyPathComparator(\MTPItem.modified, order: order)]
            case .size: return [KeyPathComparator(\MTPItem.size, order: order)]
            case .kind: return [KeyPathComparator(\MTPItem.kind, order: order)]
            }
        }, set: { values in
            guard let first = values.first else { return }
            if first.keyPath == \MTPItem.name { model.sort = .name }
            else if first.keyPath == \MTPItem.modified { model.sort = .modified }
            else if first.keyPath == \MTPItem.size { model.sort = .size }
            else if first.keyPath == \MTPItem.kind { model.sort = .kind }
            model.ascending = first.order == .forward
        })
    }
    var body: some View {
        Table(model.visibleItems, selection: $model.selection, sortOrder: sortOrder) {
            TableColumn("名称", value: \.name) { item in
                HStack(spacing: 7) {
                    FileGlyph(item: item, size: 22)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                }.padding(.vertical, 2)
            }.width(min: 180, ideal: 320)
            TableColumn("修改日期", value: \.modified) { item in
                if item.modified > 0 { Text(item.date, format: .dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute()).foregroundStyle(.secondary) }
                else { Text("—").foregroundStyle(.tertiary) }
            }.width(min: 125, ideal: 155, max: 180)
            TableColumn("大小", value: \.size) { item in
                Text(item.sizeLabel).monospacedDigit().foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
            }.width(min: 65, ideal: 85, max: 110)
            TableColumn("种类", value: \.kind) { item in Text(item.kind).foregroundStyle(.secondary).lineLimit(1) }
                .width(min: 80, ideal: 120, max: 180)
        }
        .alternatingRowBackgrounds(.enabled)
        .contextMenu(forSelectionType: UInt32.self) { ids in
            FileContextMenu(ids: ids)
        } primaryAction: { ids in
            if let id = ids.first, let item = model.items.first(where: { $0.id == id }) { Task { await model.open(item) } }
        }
        .disabled(model.busy)
    }
}

struct FileIconView: View {
    @EnvironmentObject private var model: ExplorerModel
    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 14)]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(model.visibleItems) { item in
                    VStack(spacing: 5) {
                        FileGlyph(item: item, size: 58)
                            .padding(8)
                            .background(model.selection.contains(item.id) ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        Text(item.name).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.center)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .foregroundStyle(model.selection.contains(item.id) ? Color.white : Color.primary)
                            .background(model.selection.contains(item.id) ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .frame(maxWidth: .infinity).frame(height: 113, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.selection = [item.id]; Task { await model.open(item) } }
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                            if model.selection.contains(item.id) { model.selection.remove(item.id) } else { model.selection.insert(item.id) }
                        } else { model.selection = [item.id] }
                    }
                    .contextMenu { FileContextMenu(ids: model.selection.contains(item.id) ? model.selection : [item.id]) }
                    .help(item.name)
                }
            }.padding(22)
        }.disabled(model.busy)
    }
}

struct FileContextMenu: View {
    @EnvironmentObject private var model: ExplorerModel
    let ids: Set<UInt32>
    private var targets: [MTPItem] { model.items.filter { ids.contains($0.id) } }
    var body: some View {
        if targets.count == 1, let first = targets.first {
            Button(first.isFolder ? "打开" : "下载并打开", systemImage: first.isFolder ? "folder" : "arrow.up.forward.app") {
                Task { await model.open(first) }
            }.disabled(model.busy || (model.demoMode && !first.isFolder))
        }
        if !targets.isEmpty {
            Button("导出到 Mac…", systemImage: "square.and.arrow.up") { model.selection = ids; model.chooseDownload() }
                .disabled(model.busy || model.demoMode)
            if targets.count == 1, let first = targets.first {
                Button("重命名…", systemImage: "pencil") { model.renameTarget = first }.disabled(!model.canWrite)
            }
            Button("显示简介", systemImage: "info.circle") { model.selection = ids; model.showInspector = true }
            Divider()
            Button("永久删除…", systemImage: "trash", role: .destructive) { model.selection = ids; model.showDelete = true }.disabled(!model.canWrite)
        } else {
            Button("新建文件夹", systemImage: "folder.badge.plus") { model.showNewFolder = true }.disabled(!model.canWrite)
            Button("导入到设备…", systemImage: "square.and.arrow.down") { model.chooseUpload() }.disabled(!model.canWrite)
        }
    }
}

struct InspectorView: View {
    @EnvironmentObject private var model: ExplorerModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("简介").font(.headline); Spacer(); Button { model.showInspector = false } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                if let item = model.selectedItems.first, model.selectedItems.count == 1 {
                    VStack(spacing: 10) {
                        FileGlyph(item: item, size: 80)
                        Text(item.name).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.center).textSelection(.enabled)
                        Text(item.kind).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                    Divider()
                    details("通用") {
                        row("种类", item.kind)
                        row("大小", item.sizeLabel)
                        row("位置", ([model.deviceName, model.selectedStorage?.displayName ?? ""] + model.path.map(\.name)).joined(separator: " / "))
                        if item.modified > 0 { row("修改日期", item.date.formatted(date: .abbreviated, time: .shortened)) }
                        row("对象 ID", String(item.id))
                    }
                } else if !model.selection.isEmpty {
                    Image(systemName: "doc.on.doc").font(.system(size: 48)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical)
                    Text("\(model.selection.count) 个项目").font(.headline)
                    row("文件大小", ByteCountFormatter.string(fromByteCount: model.selectedItems.reduce(Int64(0)) { partial, item in
                        let sum = partial.addingReportingOverflow(Int64(clamping: item.size)); return sum.overflow ? Int64.max : sum.partialValue
                    }, countStyle: .file))
                } else {
                    Image(systemName: "internaldrive").font(.system(size: 56)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20)
                    Text(model.selectedStorage?.displayName ?? "未选择项目").font(.headline)
                    Text("选择一个文件或文件夹以查看详细信息。").font(.callout).foregroundStyle(.secondary)
                    if let storage = model.selectedStorage {
                        Divider()
                        details("存储空间") {
                            row("容量", bytes(storage.capacity))
                            row("可用", bytes(storage.free))
                            row("设备", model.deviceName)
                            row("协议", "Media Transfer Protocol")
                        }
                    }
                }
            }.padding(20)
        }.background(.bar)
    }
    private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file) }
    private func details<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.system(size: 12, weight: .semibold)); content() }
    }
    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
