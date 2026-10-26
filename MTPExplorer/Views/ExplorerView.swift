import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ExplorerView: View {
    @EnvironmentObject private var model: ExplorerModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var dropTarget = false
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                if model.demoMode {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                        Text("界面演示 · 示例数据，仅供预览")
                        Spacer()
                    }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 7)
                    Divider()
                }
                ZStack {
                    if model.connectedDevice == nil { ConnectionView() }
                    else if model.items.isEmpty && model.busy {
                        ProgressView("正在读取设备…").controlSize(.small)
                    } else if model.visibleItems.isEmpty {
                        ContentUnavailableView {
                            Label(model.search.isEmpty ? "此文件夹为空" : "未找到匹配项目", systemImage: model.search.isEmpty ? "folder" : "magnifyingglass")
                        } description: {
                            Text(model.search.isEmpty ? "将 Mac 上的文件拖到此处，或点击“导入”。" : "尝试其他名称。搜索范围为当前文件夹。")
                        }
                    } else if model.viewMode == .list { FileListView() }
                    else { FileIconView() }
                    if dropTarget {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 3)
                            .background(Color.accentColor.opacity(0.07)).padding(8).allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [UTType.fileURL], isTargeted: $dropTarget, perform: handleDrop)
                if model.connectedDevice != nil {
                    Divider()
                    PathBar()
                    Divider()
                    statusBar
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle(model.connectedDevice == nil ? "MTP Explorer" : model.folderName)
            .navigationSubtitle(model.connectedDevice == nil ? "USB 文件传输" : model.deviceName)
            .toolbar { toolbar }
            .inspector(isPresented: $model.showInspector) {
                InspectorView().inspectorColumnWidth(min: 240, ideal: 270, max: 320)
            }
        }
        .sheet(isPresented: $model.showNewFolder) {
            NameSheet(title: "新建文件夹", initialName: "未命名文件夹", actionTitle: "创建") { name in
                Task { await model.createFolder(name) }
            }
        }
        .sheet(item: $model.renameTarget) { item in
            NameSheet(title: "重命名", initialName: item.name, actionTitle: "重命名") { name in
                Task { await model.rename(item, to: name) }
            }
        }
        .alert("无法完成操作", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            if let device = model.cameraConflictDevice {
                Button("释放相机占用并重试") {
                    model.errorMessage = nil; model.cameraConflictDevice = nil
                    Task { await model.connect(device, releasingCamera: true) }
                }
                Button("取消", role: .cancel) { model.errorMessage = nil; model.cameraConflictDevice = nil }
            } else {
                Button("好") { model.errorMessage = nil }
            }
        } message: { Text(model.errorMessage ?? "") }
        .alert("从设备永久删除？", isPresented: $model.showDelete) {
            Button("取消", role: .cancel) { }
            Button("永久删除", role: .destructive) { Task { await model.deleteSelection() } }
        } message: {
            Text("将永久删除所选的 \(model.selectedItems.count) 个项目及文件夹中的全部内容。MTP 设备没有废纸篓，此操作无法撤销。")
        }
        .sheet(isPresented: Binding(get: { model.transferTitle != nil }, set: { _ in })) {
            VStack(alignment: .leading, spacing: 18) {
                Label(model.transferTitle ?? "正在传输", systemImage: "arrow.left.arrow.right")
                    .font(.headline).lineLimit(2)
                ProgressView(value: model.transferProgress)
                HStack {
                    Text("当前文件 \(Int(model.transferProgress * 100))%")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button("取消传输") { model.cancelTransfer() }
                }
            }.padding(26).frame(width: 420).interactiveDismissDisabled()
        }
    }
    private var statusBar: some View {
        HStack(spacing: 6) {
            if model.busy { ProgressView().controlSize(.mini) }
            Spacer()
            if !model.selection.isEmpty { Text("已选择 \(model.selection.count) 个，共 \(model.visibleItems.count) 个项目") }
            else { Text("\(model.visibleItems.count) 个项目") }
            if let storage = model.selectedStorage {
                Text("·")
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(clamping: storage.free), countStyle: .file)) 可用")
            }
            Spacer()
            if model.search.isEmpty == false { Image(systemName: "line.3.horizontal.decrease.circle").help("正在筛选当前文件夹") }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 16).frame(height: 29)
        .background(.bar)
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { Task { await model.goBack() } } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoBack).help("后退 (⌘[)")
            Button { Task { await model.goForward() } } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward).help("前进 (⌘])")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("显示方式", selection: $model.viewMode) {
                Image(systemName: "square.grid.2x2").tag(ExplorerViewMode.icons)
                Image(systemName: "list.bullet").tag(ExplorerViewMode.list)
            }.pickerStyle(.segmented).frame(width: 80).help("图标或列表视图")
            Menu {
                Picker("排序依据", selection: $model.sort) {
                    ForEach(ExplorerSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Divider()
                Toggle("升序", isOn: $model.ascending)
                Toggle("显示隐藏文件", isOn: $model.showHidden)
            } label: { Image(systemName: "arrow.up.arrow.down") }.help("排序与显示选项")
            Button { model.chooseUpload() } label: { Image(systemName: "square.and.arrow.down") }
                .disabled(!model.canWrite).help("导入到设备 (⌘I)")
            Button { model.chooseDownload() } label: { Image(systemName: "square.and.arrow.up") }
                .disabled(model.selectedItems.isEmpty || model.busy || model.demoMode).help("导出到 Mac (⌘E)")
            Menu {
                Button("新建文件夹", systemImage: "folder.badge.plus") { model.showNewFolder = true }.disabled(!model.canWrite)
                Button("重命名…", systemImage: "pencil") { model.renameTarget = model.selectedItems.first }
                    .disabled(model.selectedItems.count != 1 || !model.canWrite)
                Divider()
                Button("永久删除…", systemImage: "trash", role: .destructive) { model.showDelete = true }
                    .disabled(model.selectedItems.isEmpty || !model.canWrite)
            } label: { Image(systemName: "ellipsis.circle") }.help("更多操作")
            Button { Task { if model.connectedDevice == nil { await model.scan() } else { await model.refresh() } } } label: {
                Image(systemName: "arrow.clockwise")
            }.disabled(model.busy || model.scanning || model.demoMode).help("刷新 (⌘R)")
            Button { model.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("显示简介")
        }
        ToolbarItem(placement: .automatic) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索当前文件夹", text: $model.search).textFieldStyle(.plain)
                    .frame(width: 140)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 8).padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .disabled(model.connectedDevice == nil)
        }
    }
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard model.canWrite else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                        if let url = value as? URL { continuation.resume(returning: url) }
                        else if let data = value as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                        else { continuation.resume(returning: nil) }
                    }
                }
                if let url { urls.append(url) }
            }
            await model.upload(urls)
        }
        return true
    }
}

struct PathBar: View {
    @EnvironmentObject private var model: ExplorerModel
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Image(systemName: "externaldrive").foregroundStyle(.secondary)
                Button(model.selectedStorage?.displayName ?? "存储") { Task { await model.navigate([]) } }
                ForEach(Array(model.path.enumerated()), id: \.offset) { index, folder in
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                    Button { Task { await model.navigate(Array(model.path.prefix(index + 1))) } } label: {
                        Label(folder.name, systemImage: "folder.fill")
                    }
                }
            }.buttonStyle(.plain).font(.system(size: 11))
                .padding(.horizontal, 16).frame(height: 29)
        }.background(.bar).disabled(model.busy)
    }
}

struct NameSheet: View {
    let title: String
    let initialName: String
    let actionTitle: String
    let action: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var validation: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.headline)
            TextField("名称", text: $name).textFieldStyle(.roundedBorder).focused($focused).onSubmit(submit)
            if let validation { Text(validation).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(actionTitle, action: submit).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 380)
            .onAppear { name = initialName; focused = true }
    }
    private func submit() {
        do { try MTPService.validate(name); dismiss(); action(name) }
        catch { validation = error.localizedDescription }
    }
}
