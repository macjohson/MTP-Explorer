# Security / 安全政策

## 简体中文

请不要在公开 Issue 中发布漏洞利用细节、密码、令牌、设备序列号或私人文件。

如果仓库的 **Security → Advisories → Report a vulnerability** 入口可用，请使用私密报告；若不可用，请先提交不含技术细节的 Issue，请求维护者提供私密反馈渠道。不要将敏感内容附在公开报告中。

当前项目处于早期阶段，维护者会按能力处理问题，不承诺响应时限或长期支持版本。

应用使用直接 USB 访问，不启用 App Sandbox。只有用户选择“释放相机占用并重试”时，应用才会核验并结束该设备当前的 `ptpcamerad` 会话。发现路径越界、误删、任意进程结束或凭据泄漏等问题时，请按上述方式反馈。

## English

Do not post exploit details, passwords, tokens, device serial numbers or private files in public issues.

Use **Security → Advisories → Report a vulnerability** if private reporting is available for this repository. Otherwise, open an issue without technical details and ask the maintainer for a private reporting channel. Do not attach sensitive material to a public report.

This is an early-stage project. Security reports are handled on a best-effort basis, without a guaranteed response time or long-term support policy.

The app accesses USB directly and does not use App Sandbox. It verifies and ends a device's current `ptpcamerad` session only after the user chooses the release-and-retry action. Please report path traversal, unintended deletion, arbitrary process termination or credential exposure through the channels above.
