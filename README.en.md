# MTP Explorer

[简体中文](README.md) | **English**

A native macOS MTP file manager built with SwiftUI, AppKit, libmtp and libusb. Browse files on Android phones, tablets and other MTP devices through a Finder-style sidebar, unified toolbar, list / icon views and path bar.

> Current version: 1.0.1. This is an early-stage project. Connection, directory listing and storage capacity display have been tested on a Lenovo Legion Y700. Upload, download, deletion and unexpected disconnection have not yet been validated on hardware.

## Features

- Automatic device discovery, real device names, connect / disconnect, multiple storage volumes and capacity information.
- Native list / icon views, system file icons, multiple selection, sorting and an inspector.
- Back / forward / parent navigation, clickable paths, current-folder search and hidden-file visibility.
- Recursive file and folder import / export, including drag-in from Finder.
- Folder creation, renaming, permanent deletion confirmation, per-file progress and cancellation.
- Duplicate-name protection, temporary download cleanup and symbolic-link checks.
- USB / MTP interface ownership diagnostics, with an explicit user action to release `ptpcamerad` and retry.
- A demo mode that does not need a device, plus system light / dark appearance.

The application UI currently uses Simplified Chinese. Documentation is available in Chinese and English. iPhone does not use MTP and is outside this project's scope.

## Requirements and quick start

- **macOS 14.0+**, on Apple Silicon or Intel.
- Full Xcode. Built and run with **Xcode 26.3 on Apple Silicon**. Intel binaries are cross-compiled and have not been tested on Intel hardware.
- A USB data cable and a device with **File transfer / MTP** enabled.

```bash
git clone https://github.com/macjohson/MTP-Explorer.git
cd MTP-Explorer
open MTPExplorer.xcodeproj
```

Select **MTPExplorer → My Mac** and press `⌘R`. Local signing is configured, so no developer account is required. Connect and unlock your device, select File transfer / MTP, approve access on the device and click it in the sidebar.

Universal runtime libraries (`arm64 + x86_64`), matching source archives and licenses are included. Normal builds do not need Homebrew or additional dependency downloads.

## Build, test and package

```bash
# Debug build
xcodebuild -project MTPExplorer.xcodeproj -scheme MTPExplorer \
  -configuration Debug -derivedDataPath build build

# Unit tests; no device required
xcodebuild -project MTPExplorer.xcodeproj -scheme MTPExplorer \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build-tests test

# Universal Release build and app / source archives
./Scripts/package.sh
```

Run the packaging script from a Git checkout so it can enforce ignore rules. Packages are written to `dist/`, which is excluded from Git. App packages can be uploaded separately as GitHub Release assets. Local builds are **not Developer ID signed or notarized**. For public binary distribution, sign the app and its libraries with the same Developer ID, enable Hardened Runtime and complete notarization.

CI checks dependency hashes, publication rules, unit tests and a Universal Release build. It does not perform USB hardware writes.

### Preview without a device

Add `--demo` in **Edit Scheme → Run → Arguments**, or run after packaging:

```bash
open build-release/Build/Products/Release/MTPExplorer.app --args --demo
```

Demo data is explicitly labeled. Device writes, exports and file opening are disabled.

### Rebuild dependencies from source

```bash
brew install pkgconf
./Scripts/build-dependencies.sh
```

The script uses archives in `Vendor/sources/` when available, verifies their SHA-256 hashes and builds Universal libraries targeting macOS 14+. Missing archives are downloaded from pinned official URLs. See [third-party components](Vendor/SOURCES.md) for versions, licenses, sources and replacement instructions.

## Connection troubleshooting

1. Connect directly using a data cable. Unlock the device, select MTP and approve any access prompt.
2. Close other MTP applications, photo import tools and camera software.
3. If `ptpcamerad` owns the interface, choose **释放相机占用并重试** (Release camera ownership and retry). This ends the device's current camera-service session and may interrupt photo import. The app verifies interface ownership, executable path and user identity. It does not disable system services, request administrator access or automatically stop ADB.
4. ADB coexistence depends on the device and driver. You may temporarily stop your own debugging session while troubleshooting and restore it afterward.
5. Some devices re-enumerate after a session closes; select File transfer / MTP again if needed.

## Limitations and behavior

- Deletion is permanent. There is no app-provided device Trash; review the confirmation carefully.
- Duplicate names stop the operation with an error. Files are not automatically overwritten or merged.
- Batch operations do not offer atomic rollback. Completed files and created folders remain after cancellation or failure.
- Cancellation relies on progress callbacks and may be delayed by a blocked USB driver.
- Search covers the current folder only. Folder sizes are not calculated recursively.
- Opening a file downloads a temporary local copy and opens it in the default app. Edits are not synchronized back to the device.
- USB access uses libusb directly. App Sandbox is currently disabled.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New folder | `⌘⇧N` |
| Import / export | `⌘I` / `⌘E` |
| Refresh | `⌘R` |
| Back / forward | `⌘[` / `⌘]` |
| Parent folder / open | `⌘↑` / `⌘↓` |
| Rename | `Return` |
| Delete with confirmation | `⌘Delete` |
| Toggle hidden files | `⌘⇧.` |
| Inspector | `⌘⌥I` |

## Project layout

```text
MTPExplorer/              SwiftUI / AppKit app and Objective-C / C bridge
MTPExplorer.xcodeproj/    Xcode project and shared scheme
Tests/                   Core unit tests without hardware dependencies
Scripts/                 Dependency builds, audits, icon generation and packaging
Vendor/                  Third-party headers, libraries, licenses and sources
.github/                 CI and issue templates
```

A single `MTPService` actor serializes USB calls. Browser state stays on the main actor. Downloads use temporary files before moving successful results to their destination names.

## Contributing and publication rules

Issues and pull requests in Chinese or English are welcome. Read [Contributing](CONTRIBUTING.md) and the [publication policy](docs/PUBLISHING.md). Before committing, run:

```bash
python3 Scripts/audit-publication.py
```

Commit source, shared project settings, tests, documentation and the reviewed third-party dependencies. Exclude build folders, device logs, screenshots of real files, credentials, signing certificates and personal Xcode settings. See [Security](SECURITY.md) for reporting vulnerabilities.

## License

Original project code is available under the [MIT License](LICENSE). libmtp and libusb retain their respective **LGPL 2.1-or-later** licenses; they are not relicensed as MIT. Their licenses and corresponding source archives are retained in `Vendor/`. See [third-party components](Vendor/SOURCES.md).
