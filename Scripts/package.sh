#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
python3 Scripts/audit-publication.py
xcodebuild -project MTPExplorer.xcodeproj -scheme MTPExplorer \
  -configuration Release -derivedDataPath build-release \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
mkdir -p dist
/usr/bin/codesign --verify --deep --strict build-release/Build/Products/Release/MTPExplorer.app
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
  build-release/Build/Products/Release/MTPExplorer.app dist/MTPExplorer-macOS.zip
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
printf 'Created dist/MTPExplorer-macOS.zip and dist/MTPExplorer-Xcode.zip\n'
