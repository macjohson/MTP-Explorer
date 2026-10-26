# Publication policy / 公开文件范围

## 简体中文

此说明适用于 Git 提交、GitHub 仓库和源码压缩包。`.gitignore` 负责排除默认不提交的文件；`Scripts/audit-publication.py` 会额外检查待公开文件，已被 Git 跟踪的文件也不能绕过审计。

| 文件 / 目录 | Git 仓库 | 处理方式 |
| --- | --- | --- |
| `MTPExplorer/` | 提交 | 原创源码、应用图标和必要资源 |
| `MTPExplorer.xcodeproj/project.pbxproj`、共享 scheme | 提交 | 使用相对路径和本地签名；无个人 Team ID |
| `Tests/`、`Scripts/`、`.github/` | 提交 | 测试、可复现脚本与 CI |
| 中英文文档、`LICENSE` | 提交 | 说明实际功能、限制与许可证 |
| `Vendor/include/`、指定的两个 `.dylib` | 提交 | 直接构建需要；校验值、许可证及源码同时保留 |
| `Vendor/sources/` | 提交 | 固定版本官方源码包，便于离线检查与重建 |
| `Vendor/licenses/`、`SOURCES.md`、校验清单 | 提交 | 原许可证保持完整，不改成 MIT |
| `build*`、`DerivedData/`、`.build-deps/`、`dist/` | 不提交 | 本地构建、缓存、诊断和发行产物 |
| `.app`、`.dmg`、`.zip`、`.xcarchive`、`.dSYM` | 不提交 | 需要发行时作为 Release 附件单独审查 |
| 设备日志、真实目录截图、设备转储 | 不提交 | 可能包含序列号、文件名和个人信息 |
| `xcuserdata/`、个人工作区及本地配置 | 不提交 | 与机器、用户或签名身份相关 |
| `.env`、密钥、令牌、证书、描述文件 | 不提交 | 永不作为源码公开 |

### 每次发布前

```bash
python3 Scripts/audit-publication.py
# 暂存明确的改动后，再检查真正准备提交的版本：
python3 Scripts/audit-publication.py --staged
git diff --cached --stat
```

审计会检查路径范围、常见凭据格式、个人主目录路径、依赖校验值及链接目标，不打印命中的敏感内容。自动检查不能替代人工审阅，尤其是截图、许可证变更及日志。

源码打包脚本采用路径清单，并依据 Git 的忽略规则过滤文件；不会递归打包整个工作目录。新增顶层目录时，应同步审计规则与打包清单。

如需对外发布 App，应单独完成代码签名、公证及第三方许可证 / 对应源码交付检查；本仓库中的本地签名构建不代表已完成正式发行流程。

## English

This policy covers Git commits, GitHub publication and source archives. `.gitignore` excludes local material by default. `Scripts/audit-publication.py` also checks publication candidates, including files already tracked by Git.

**Commit:** original app source and icons; the Xcode project and shared scheme; tests, scripts and CI; bilingual documentation and the MIT license; the reviewed third-party header, the two runtime libraries, matching official source archives, original licenses and checksums.

**Exclude:** build directories, dependency workspaces, caches, `dist/`, app / installer packages, debug symbols, device logs, screenshots of real files, device dumps, personal Xcode state, local configuration, environment files, credentials and signing material. Release assets require a separate review rather than being committed to source history.

Run the audit commands above, then manually review the staged diff. The audit checks allowed paths, common credential formats, personal home paths, dependency hashes and symlinks without printing matching secret values. It does not replace human review, especially for screenshots, license changes and logs.

The source packager uses explicit top-level paths and Git ignore rules rather than archiving the entire working directory. Update both the audit rules and packaging list when adding a new top-level directory.

Public app distribution additionally requires appropriate signing, notarization and delivery of third-party notices and corresponding source. Local ad-hoc builds do not imply that these distribution steps are complete.
