import SwiftUI
import AppKit

@main
struct MTPExplorerApp: App {
    @StateObject private var model = ExplorerModel()
    var body: some Scene {
        Window("MTP Explorer", id: "explorer") {
            ExplorerView().environmentObject(model)
                .frame(minWidth: 860, minHeight: 560)
                .task { model.start() }
        }
        .defaultSize(width: 1120, height: 740)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建文件夹") { model.showNewFolder = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift]).disabled(!model.canWrite)
                Divider()
                Button("导入到设备…") { model.chooseUpload() }
                    .keyboardShortcut("i", modifiers: .command).disabled(!model.canWrite)
                Button("导出到 Mac…") { model.chooseDownload() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(model.selectedItems.isEmpty || model.busy || model.demoMode)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("全选") { model.selection = Set(model.visibleItems.map(\.id)) }
                    .keyboardShortcut("a").disabled(model.busy)
                Button("重命名…") { model.renameTarget = model.selectedItems.first }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(model.selectedItems.count != 1 || !model.canWrite)
                Button("从设备删除…") { model.showDelete = true }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.selectedItems.isEmpty || !model.canWrite)
            }
            CommandMenu("前往") {
                Button("后退") { Task { await model.goBack() } }
                    .keyboardShortcut("[", modifiers: .command).disabled(!model.canGoBack)
                Button("前进") { Task { await model.goForward() } }
                    .keyboardShortcut("]", modifiers: .command).disabled(!model.canGoForward)
                Button("上层文件夹") { Task { await model.goUp() } }
                    .keyboardShortcut(.upArrow, modifiers: .command).disabled(model.path.isEmpty || model.busy)
                Button("打开所选项目") { if let item = model.selectedItems.first { Task { await model.open(item) } } }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .disabled(model.selectedItems.count != 1 || model.busy)
            }
            CommandGroup(after: .toolbar) {
                Button("刷新") { Task { if model.connectedDevice == nil { await model.scan() } else { await model.refresh() } } }
                    .keyboardShortcut("r").disabled(model.busy || model.scanning)
                Toggle("显示隐藏文件", isOn: $model.showHidden).keyboardShortcut(".", modifiers: [.command, .shift])
                Toggle("显示简介", isOn: $model.showInspector).keyboardShortcut("i", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .help) {
                Button("连接帮助") {
                    let alert = NSAlert()
                    alert.messageText = "连接你的 MTP 设备"
                    alert.informativeText = "1. 使用支持数据传输的 USB 线连接设备。\n2. 解锁设备，在 USB 选项中选择“文件传输 / MTP”。\n3. 允许设备上的访问请求。\n4. 关闭 Android File Transfer、OpenMTP 等占用设备的应用。\n5. 点击侧边栏中的设备以连接。\n\nMTP 不提供废纸篓，删除操作无法撤销。iPhone 不使用 MTP 协议。"
                    alert.runModal()
                }
            }
        }
    }
}
