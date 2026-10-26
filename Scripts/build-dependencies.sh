#!/bin/bash
# Build pinned LGPL dependencies as Universal binaries (Apple Silicon + Intel), targeting macOS 14+.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$root/.build-deps"
prefix="$work/install"
mkdir -p "$work/downloads" "$prefix"
fetch() {
  local url="$1" file="$2" checksum="$3"
  if [ ! -f "$work/downloads/$file" ] && [ -f "$root/Vendor/sources/$file" ]; then
    cp "$root/Vendor/sources/$file" "$work/downloads/$file"
  fi
  if [ ! -f "$work/downloads/$file" ]; then
    curl --fail --location --retry 3 --connect-timeout 20 "$url" -o "$work/downloads/$file"
  fi
  echo "$checksum  $work/downloads/$file" | shasum -a 256 -c -
}
fetch https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2 libusb-1.0.30.tar.bz2 fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf
fetch https://github.com/libmtp/libmtp/releases/download/v1.1.23/libmtp-1.1.23.tar.gz libmtp-1.1.23.tar.gz 74a2b6e8cb4a0304e95b995496ea3ac644c29371649b892b856e22f12a0bdeed
export MACOSX_DEPLOYMENT_TARGET=14.0
export CFLAGS="-O2 -arch arm64 -arch x86_64 -mmacosx-version-min=14.0"
export LDFLAGS="-arch arm64 -arch x86_64 -mmacosx-version-min=14.0"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
command -v pkg-config >/dev/null || { echo 'Install pkg-config (brew install pkgconf) before rebuilding dependencies.' >&2; exit 1; }
tar -xf "$work/downloads/libusb-1.0.30.tar.bz2" -C "$work"
tar -xf "$work/downloads/libmtp-1.1.23.tar.gz" -C "$work"
cd "$work/libusb-1.0.30"
if [ -f Makefile ]; then make clean; fi
./configure --prefix="$prefix" --disable-static --enable-shared
make -j "$(sysctl -n hw.ncpu)"
make install
cd "$work/libmtp-1.1.23"
if [ -f Makefile ]; then make clean; fi
./configure --prefix="$prefix" --disable-static --enable-shared --disable-mtpz
make -j "$(sysctl -n hw.ncpu)"
make install
cp COPYING "$root/Vendor/licenses/libmtp-COPYING.txt"
cp "$work/libusb-1.0.30/COPYING" "$root/Vendor/licenses/libusb-COPYING.txt"
python3 "$root/Scripts/prepare-vendor.py" "$prefix"
python3 - "$root" <<'CHECKSUMS'
from pathlib import Path
import hashlib
import sys
root = Path(sys.argv[1])
files = ['Vendor/include/libmtp.h', 'Vendor/lib/libmtp.9.dylib', 'Vendor/lib/libusb-1.0.0.dylib',
         'Vendor/sources/libmtp-1.1.23.tar.gz', 'Vendor/sources/libusb-1.0.30.tar.bz2']
(root / 'Vendor/checksums.sha256').write_text(''.join(
    hashlib.sha256((root / name).read_bytes()).hexdigest() + '  ' + name + '\n' for name in files))
CHECKSUMS
xcrun vtool -show-build "$root/Vendor/lib/libmtp.9.dylib"
echo 'Dependencies ready. Open MTPExplorer.xcodeproj and run.'
