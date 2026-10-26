# Third-party components

These libraries are dynamically linked. Their licenses are included in `licenses/` and copied into the app's `Contents/Resources/Licenses/` on every build.

| Component | Version | License | Exact corresponding source | SHA-256 |
| --- | --- | --- | --- | --- |
| libmtp | 1.1.23 | LGPL 2.1 or later | https://github.com/libmtp/libmtp/releases/download/v1.1.23/libmtp-1.1.23.tar.gz | `74a2b6e8cb4a0304e95b995496ea3ac644c29371649b892b856e22f12a0bdeed` |
| libusb | 1.0.30 | LGPL 2.1 or later | https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2 | `fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf` |

The vendored libraries were compiled from these unmodified sources using `Scripts/build-dependencies.sh` for macOS 14.0+, with both arm64 and x86_64 slices. MTPZ support is disabled to avoid a crypto dependency; standard MTP is supported. The only post-build modifications are install-name rewriting to `@rpath` / `@loader_path` and ad-hoc signing for local execution. No Homebrew paths are present in the shipped dylib dependencies.

To rebuild or replace a library, run the build script, or supply ABI-compatible libmtp.9.dylib and libusb-1.0.0.dylib files in `Vendor/lib/` and rebuild the Xcode project. Both complete corresponding source archives are included in `Vendor/sources/` for offline inspection and rebuilding; the script's downloads can be seeded with these files.

Upstream projects: https://github.com/libmtp/libmtp and https://github.com/libusb/libusb.

## Integrity / 完整性

`checksums.sha256` records the reviewed header, runtime libraries and source archives. Run `python3 Scripts/audit-publication.py` from the project root to verify them. Dependency rebuilds update this manifest; review and commit it together with the matching files.

`checksums.sha256` 记录经过检查的头文件、动态库及源码包。依赖重建会更新校验清单，须与对应文件一起审阅和提交；上游固定版本源码包的 SHA-256 还会被审计脚本独立核验。
