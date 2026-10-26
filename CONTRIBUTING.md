# Contributing / 贡献指南

## 简体中文

欢迎中文和英文的 Issue / Pull Request。提交错误报告时，请提供 macOS / Xcode 版本、设备型号、USB 模式、预期行为、实际行为和复现步骤。

请勿上传完整设备转储、序列号、真实文件列表、私人文件截图或未经脱敏的日志。可使用 `--demo` 截图，或手动遮盖与问题无关的信息。安全漏洞请按 [SECURITY.md](SECURITY.md) 处理。

### 本地验证

```bash
python3 Scripts/audit-publication.py
xcodebuild -project MTPExplorer.xcodeproj -scheme MTPExplorer \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build-tests test
```

- USB 操作保持由 `MTPService` 串行执行，避免在主线程进行 USB I/O。
- 涉及名称、路径、覆盖、删除及取消行为的改动，应说明失败和部分完成时的行为。
- 默认测试不得连接真实设备、结束其他进程或修改设备文件。硬件测试需明确说明范围。
- 第三方依赖更新时，同时更新源码包、许可证、版本说明和 `Vendor/checksums.sha256`。构建脚本会更新校验清单。
- Pull Request 应说明问题、最终行为和验证结果；不要提交构建产物或个人签名设置。
- 若修改用户文档，请同步检查中英文版本；发现翻译差异可直接提交修正。

提交贡献即表示你有权按本项目的 MIT 许可提供原创改动；第三方代码保留其原许可证。

## English

Issues and pull requests in Chinese or English are welcome. Include your macOS / Xcode versions, device model, USB mode, expected and actual behavior, and reproduction steps.

Do not upload full device dumps, serial numbers, real file listings, screenshots of private files or unredacted logs. Use `--demo` for screenshots or redact unrelated information. Follow [SECURITY.md](SECURITY.md) for vulnerabilities.

Run the audit and unit-test commands above before submitting changes.

- Keep USB operations serialized through `MTPService`; avoid USB I/O on the main thread.
- Explain failure and partial-completion behavior for changes involving names, paths, overwrite protection, deletion or cancellation.
- Default tests must not connect to physical devices, terminate other processes or modify device files. State the scope of any hardware testing separately.
- Dependency updates must include matching source archives, licenses, version notes and `Vendor/checksums.sha256`. The dependency build script updates the checksum manifest.
- Describe the problem, final behavior and validation in your pull request. Exclude build products and personal signing settings.
- Keep Chinese and English user documentation aligned. Translation corrections are welcome.

By contributing, you confirm that you have the right to provide your original changes under the project's MIT license. Third-party code retains its original license.
