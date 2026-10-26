#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
python3 Scripts/audit-publication.py
xcodebuild -project MTPExplorer.xcodeproj -scheme MTPExplorer \
  -configuration Release -derivedDataPath build-release \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
mkdir -p dist .build-deps
/usr/bin/codesign --verify --deep --strict build-release/Build/Products/Release/MTPExplorer.app
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
  build-release/Build/Products/Release/MTPExplorer.app dist/MTPExplorer-macOS.zip
# The app and every bundled dylib are thinned, then re-signed. Each release
# download contains only the requested architecture, not just a renamed fat app.
for architecture in arm64 x86_64; do
  case "$architecture" in
    arm64) label=AppleSilicon ;;
    x86_64) label=Intel ;;
  esac
  stage="$(mktemp -d "$root/.build-deps/package-$architecture.XXXXXX")"
  app="$stage/MTPExplorer.app"
  /usr/bin/ditto build-release/Build/Products/Release/MTPExplorer.app "$app"
  for binary in "$app/Contents/MacOS/MTPExplorer" "$app/Contents/Frameworks/"*.dylib; do
    /usr/bin/lipo "$binary" -thin "$architecture" -output "$binary.thin"
    mv "$binary.thin" "$binary"
    chmod 755 "$binary"
    [ "$(/usr/bin/lipo -archs "$binary")" = "$architecture" ]
    /usr/bin/codesign --force --sign - --timestamp=none "$binary"
  done
  /usr/bin/codesign --force --sign - --timestamp=none "$app"
  /usr/bin/codesign --verify --deep --strict "$app"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "dist/MTPExplorer-$label.zip"
  # Staging directories are disposable copies under the ignored dependency workspace.
  python3 - "$stage" <<'CLEANUP'
import shutil, sys
shutil.rmtree(sys.argv[1])
CLEANUP
done

python3 - "$root" <<'PY'
from pathlib import Path
import sys
import subprocess
import zipfile
root = Path(sys.argv[1])
paths = ['MTPExplorer', 'MTPExplorer.xcodeproj', 'Scripts', 'Tests', 'Vendor', 'docs', '.github',
         'README.md', 'README.en.md', 'CONTRIBUTING.md', 'SECURITY.md', 'LICENSE', 'NOTICE', '.gitignore', '.gitattributes']
# Use the same Git candidates as the audit so ignored local material cannot enter
# source archives through a recursive directory traversal.
output = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--cached', '--others',
                                  '--exclude-standard', '-z', '--', *paths])
files = sorted(set(name.decode() for name in output.split(b'\0') if name))
with zipfile.ZipFile(root / 'dist/MTPExplorer-Xcode.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in files:
        path = root / name
        if path.is_file():
            archive.write(path, Path('MTPExplorer') / name)
PY
(
  cd dist
  shasum -a 256 MTPExplorer-AppleSilicon.zip MTPExplorer-Intel.zip MTPExplorer-Xcode.zip > SHA256SUMS.txt
)
printf 'Created Apple Silicon, Intel, Universal, Xcode archives and SHA256SUMS.txt in dist/\n'
