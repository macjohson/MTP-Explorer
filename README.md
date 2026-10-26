# MTP Explorer

**简体中文** | [English](README.en.md)

原生 macOS MTP 文件管理器，使用 SwiftUI、AppKit、libmtp 和 libusb 构建。采用接近 Finder 的侧边栏、统一工具栏、列表 / 图标视图和路径栏，浏览 Android 手机、平板及其他 MTP 设备中的文件。

> 当前版本：1.0.1。项目仍处于早期阶段。已在联想拯救者平板 Y700 上验证连接、目录读取和存储容量显示；上传、下载、删除及异常断连尚未完成实机验证。

## 下载

在 [GitHub Releases](https://github.com/macjohson/MTP-Explorer/releases/latest) 中按芯片选择：

| Mac 芯片 | 应用安装包 |
| --- | --- |
| Apple Silicon（M 系列，arm64） | [MTPExplorer-AppleSilicon.zip](https://github.com/macjohson/MTP-Explorer/releases/latest/download/MTPExplorer-AppleSilicon.zip) |
| Intel（x86_64） | [MTPExplorer-Intel.zip](https://github.com/macjohson/MTP-Explorer/releases/latest/download/MTPExplorer-Intel.zip) |

解压后将 `MTPExplorer.app` 移入“应用程序”。两个安装包均为单架构，应用及内部动态库与标注的芯片一致。Release 另附完整 Xcode 工程包与 `SHA256SUMS.txt`。当前安装包使用本地签名，尚未完成 Developer ID 签名或公证。

## 功能

- 自动发现设备、真实设备名、连接 / 断开、多存储卷及容量显示。
- 原生列表 / 图标视图、系统文件图标、多选、排序及简介面板。
- 前进 / 后退 / 上层目录、可点击路径栏、当前目录搜索及隐藏文件切换。
- 递归导入 / 导出文件与文件夹，支持从 Finder 拖入。
- 新建文件夹、重命名、永久删除确认、当前文件传输进度及取消。
- 同名项目保护、下载临时文件清理和符号链接检查。
- USB / MTP 接口占用诊断；遇到 `ptpcamerad` 占用时，可由用户确认释放并重试。
- 无设备演示模式；跟随系统的浅色 / 深色外观。

当前应用界面为简体中文，本文档同时提供英文版本。iPhone 不使用 MTP，不在支持范围内。

## 系统要求与快速开始

- macOS **14.0+**，Apple Silicon 或 Intel。
- 完整 Xcode；已在 **Xcode 26.3 / Apple Silicon** 上构建和运行。Intel 版本已交叉编译，尚未进行 Intel 实机验证。
- 支持数据传输的 USB 线，以及启用“文件传输 / MTP”的设备。

```bash
git clone https://github.com/macjohson/MTP-Explorer.git
cd MTP-Explorer
open MTPExplorer.xcodeproj
```

选择 **MTPExplorer → My Mac**，按 `⌘R`。默认使用本地签名，无需开发者账号。连接设备后解锁、选择“文件传输 / MTP”并允许访问，再点击侧边栏中的设备。

仓库包含 Universal 动态依赖库（`arm64 + x86_64`）、对应源码和许可证，正常构建无需安装 Homebrew 或额外下载依赖。

## 构建、测试与打包

```bash
# Debug 构建
xcodebuild -project MTPExplorer.xcodeproj -scheme MTPExplorer \
  -configuration Debug -derivedDataPath build build

# 单元测试，不需要连接设备
xcodebuild -project MTPExplorer.xcodeproj -scheme MTPExplorer \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build-tests test

# 构建 Release，并分别生成 Apple Silicon / Intel 安装包及源码包
./Scripts/package.sh
```

打包脚本需在 Git 工作副本中运行，以便使用 Git 忽略规则过滤文件。打包输出在 `dist/`，不提交到 Git。发布时可将安装包作为 GitHub Release 附件单独上传。当前本地构建**未经过 Developer ID 签名或公证**；正式分发前应为应用及依赖库使用同一 Developer ID 签名，启用 Hardened Runtime 并完成 notarization。

CI 会验证依赖校验值、提交文件策略、单元测试及 Universal Release 构建，不执行 USB 真机写入操作。

### 无设备演示

在 **Edit Scheme → Run → Arguments** 中加入 `--demo`，或在打包后运行：

```bash
open build-release/Build/Products/Release/MTPExplorer.app --args --demo
```

演示数据会明确标注，设备写入、导出及文件打开均禁用。

### 从源码重建依赖

```bash
brew install pkgconf
./Scripts/build-dependencies.sh
```

脚本优先使用 `Vendor/sources/` 内的源码包，校验 SHA-256 后构建 macOS 14+ 双架构动态库。缺少源码包时从固定的官方地址下载。版本、许可证、来源及替换方法见 [第三方组件说明](Vendor/SOURCES.md)。

## 连接故障排查

1. 使用数据线直连 Mac，解锁设备并启用 MTP，确认设备端访问请求。
2. 关闭其他 MTP 应用、照片导入程序或相机软件。
3. 若提示系统相机服务 `ptpcamerad` 占用，可点击**释放相机占用并重试**。这会结束该设备当前相机服务会话，可能中断照片导入。应用会核验接口归属、进程路径及当前用户；不会禁用系统服务、请求管理员权限或自动停止 ADB。
4. ADB 是否能共存取决于设备和驱动；排查时可暂时停止自己的调试会话，再按需要恢复。
5. 部分设备断开会话后会重新枚举，需要重新选择“文件传输 / MTP”。

## 使用边界

- 删除是永久删除，设备没有本应用提供的废纸篓，执行前请确认。
- 遇到同名项目会停止并提示，不会自动覆盖或合并。
- 批量操作没有原子回滚。取消或失败时，已完成的文件及已创建文件夹会保留。
- 取消依赖设备返回进度回调，驱动阻塞时不能保证立即生效。
- 搜索限于当前目录；文件夹大小不递归统计。
- “打开”会先下载临时副本，再交给默认应用；编辑不会自动写回设备。
- 应用通过 libusb 直接访问 USB，当前不启用 App Sandbox。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 新建文件夹 | `⌘⇧N` |
| 导入 / 导出 | `⌘I` / `⌘E` |
| 刷新 | `⌘R` |
| 后退 / 前进 | `⌘[` / `⌘]` |
| 上层目录 / 打开 | `⌘↑` / `⌘↓` |
| 重命名 | `Return` |
| 删除并确认 | `⌘Delete` |
| 隐藏文件切换 | `⌘⇧.` |
| 简介 | `⌘⌥I` |

## 项目结构

```text
MTPExplorer/              SwiftUI / AppKit 应用及 Objective-C / C 桥接
MTPExplorer.xcodeproj/    Xcode 工程与共享 scheme
Tests/                   不依赖设备的核心单元测试
Scripts/                 依赖重建、审计、图标生成及打包
Vendor/                  第三方头文件、动态库、许可证及对应源码
.github/                 CI 与问题反馈模板
```

USB 操作由唯一 `MTPService` actor 串行执行，浏览状态由主线程管理。下载先写临时文件，成功后再移动到目标名称。

## 贡献与公开文件范围

欢迎中文或英文的 Issue 和 Pull Request。请先阅读 [贡献指南](CONTRIBUTING.md) 和 [上传范围说明](docs/PUBLISHING.md)。提交前运行：

```bash
python3 Scripts/audit-publication.py
```

源码、共享工程设置、测试、文档及经审计的第三方依赖可以提交；构建目录、设备日志、真实文件截图、凭据、签名证书和个人 Xcode 配置不应提交。安全问题的反馈方式见 [安全政策](SECURITY.md)。

## 许可证

本项目原创代码采用 [MIT License](LICENSE)。libmtp 与 libusb 按各自的 **LGPL 2.1 或更新版本**许可分发，未改成 MIT；许可证及对应源码保留在 `Vendor/` 中。详见 [第三方组件说明](Vendor/SOURCES.md)。
