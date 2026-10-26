import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: ExplorerModel
    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("设备") {
                    if model.demoMode, let device = model.connectedDevice { deviceRow(device) }
                    else if model.devices.isEmpty {
                        Label("未连接设备", systemImage: "iphone.slash")
                            .foregroundStyle(.secondary).font(.system(size: 12)).padding(.vertical, 4)
                    } else { ForEach(model.devices) { deviceRow($0) } }
                }
                if !model.storages.isEmpty {
                    Section("位置") {
                        ForEach(model.storages) { storage in
                            Button { Task { await model.selectStorage(storage) } } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "internaldrive").font(.system(size: 16)).foregroundStyle(.secondary)
                                    Text(storage.displayName).lineLimit(1).font(.system(size: 13))
                                    Spacer(minLength: 0)
                                    if !storage.writable && !model.demoMode { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                                }
                                .padding(.vertical, 5).padding(.horizontal, 8)
                                .background(model.selectedStorage?.id == storage.id ? Color.primary.opacity(0.085) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(model.busy)
                                .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                        }
                    }
                    Section("设备信息") {
                        Label("USB · MTP", systemImage: "cable.connector").foregroundStyle(.secondary)
                        Label(model.demoMode ? "演示模式" : "已连接", systemImage: "circle.fill")
                            .foregroundStyle(model.demoMode ? .orange : .green)
                            .font(.system(size: 11))
                    }
                }
            }.listStyle(.sidebar)
            Spacer(minLength: 0)
            if let storage = model.selectedStorage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Image(systemName: "internaldrive"); Text(storage.displayName).lineLimit(1) }
                        .font(.system(size: 11, weight: .medium))
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(Color.accentColor.opacity(0.8)).frame(width: geometry.size.width * storage.usedFraction)
                        }
                    }.frame(height: 5)
                    Text("\(bytes(storage.free)) 可用，共 \(bytes(storage.capacity))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(16)
                Divider().padding(.horizontal, 12)
            }
            HStack {
                Image(systemName: "cable.connector.horizontal").foregroundStyle(.secondary)
                Text("MTP Explorer").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if model.scanning { ProgressView().controlSize(.mini) }
            }.padding(16)
        }
    }
    private func bytes(_ size: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file) }
    private func deviceRow(_ device: MTPDevice) -> some View {
        HStack(spacing: 8) {
            Button { Task { await model.connect(device) } } label: {
                HStack(spacing: 9) {
                    Image(systemName: "iphone").font(.system(size: 18)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.connectedDevice?.id == device.id ? model.deviceName : device.name)
                            .font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(model.connectedDevice?.id == device.id ? "已连接" : ((device.accessIssue?.isEmpty == false ? device.accessIssue : nil) ?? "点击连接"))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.busy || model.scanning || model.demoMode)
            if model.connectedDevice?.id == device.id && !model.demoMode {
                Button { Task { await model.disconnect() } } label: { Image(systemName: "eject.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
                    .buttonStyle(.borderless).help("断开设备").disabled(model.busy)
            }
        }.padding(.vertical, 5)
    }
}

struct ConnectionView: View {
    @EnvironmentObject private var model: ExplorerModel
    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 26).fill(Color.accentColor.opacity(0.07)).frame(width: 112, height: 112)
                Image(systemName: "iphone.and.arrow.forward").font(.system(size: 53, weight: .light)).foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 9) {
                Text("设备中的文件，触手可及").font(.system(size: 24, weight: .semibold))
                Text("连接 Android 手机、平板或其他 MTP 设备\n以熟悉的方式浏览和传输文件。")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).font(.system(size: 13)).lineSpacing(4)
            }
            VStack(alignment: .leading, spacing: 13) {
                step("1", "使用 USB 数据线连接设备")
                step("2", "解锁设备，并选择“文件传输 / MTP”")
                step("3", "在左侧选择设备，开始浏览")
            }.padding(20).frame(width: 340, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            Button { Task { await model.scan() } } label: {
                Label(model.scanning ? "正在查找…" : "查找设备", systemImage: "arrow.clockwise")
            }.controlSize(.large).disabled(model.scanning || model.busy)
            Text("请关闭其他正在使用此设备的 MTP 应用")
                .font(.caption).foregroundStyle(.tertiary)
        }.padding(30)
    }
    private func step(_ number: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(number).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 21, height: 21).background(Color.primary.opacity(0.06), in: Circle())
            Text(text).font(.system(size: 12))
        }
    }
}
