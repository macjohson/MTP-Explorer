#!/usr/bin/env python3
"""Audit the public working-tree candidates or the exact Git index, without printing secrets."""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TOP_LEVEL_FILES = {
    '.gitignore', '.gitattributes', 'LICENSE', 'README.md', 'README.en.md',
    'CONTRIBUTING.md', 'SECURITY.md', 'CHANGELOG.md', 'NOTICE',
}
TOP_LEVEL_DIRS = {'.github', 'MTPExplorer', 'MTPExplorer.xcodeproj', 'Scripts', 'Tests', 'Vendor', 'docs'}
PINNED_SOURCES = {
    'Vendor/sources/libmtp-1.1.23.tar.gz': '74a2b6e8cb4a0304e95b995496ea3ac644c29371649b892b856e22f12a0bdeed',
    'Vendor/sources/libusb-1.0.30.tar.bz2': 'fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf',
}
VENDORED = set(PINNED_SOURCES) | {
    'Vendor/include/libmtp.h', 'Vendor/lib/libmtp.9.dylib', 'Vendor/lib/libusb-1.0.0.dylib',
}
BANNED_PARTS = {'xcuserdata', 'project.xcworkspace', '.build-deps', 'DerivedData', 'dist', '.env', '.DS_Store', '__pycache__'}
BANNED_PATTERNS = ('*.log', '*.ips', '*.crash', '*.p12', '*.pfx', '*.pem', '*.key', '*.mobileprovision', '*.provisionprofile', '*.xcuserstate', '.env.*', '*.local', '*.local.*')
CREDENTIAL_PATTERNS = [
    re.compile(rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'),
    re.compile(rb'\bgh[pousr]_[A-Za-z0-9]{30,}\b'),
    re.compile(rb'\bgithub_pat_[A-Za-z0-9_]{30,}\b'),
    re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    re.compile(rb'(?i)https?://[^\s/]+:[^\s/@]+@github\.com'),
]
HOME_PATH = re.compile(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/')


def git(*args: str) -> bytes:
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true', help='Read the exact index blobs, including unchanged tracked files')
    args = parser.parse_args()
    try:
        index = {}
        for entry in git('ls-files', '--stage', '-z').split(b'\0'):
            if entry:
                metadata, name = entry.split(b'\t', 1)
                mode, sha, stage = metadata.decode().split()
                if stage != '0':
                    raise ValueError('Resolve merge conflicts before auditing')
                index[name.decode()] = (mode, sha)
        if args.staged:
            names = sorted(index)
        else:
            names = sorted(set(x.decode() for x in git('ls-files', '--cached', '--others', '--exclude-standard', '-z').split(b'\0') if x))
    except (subprocess.CalledProcessError, ValueError) as error:
        print('Cannot inspect Git candidates:', error, file=sys.stderr)
        return 1
    if not names:
        print('No publication candidates. Stage the intended source files first.', file=sys.stderr)
        return 1

    failures: list[tuple[str, str]] = []
    total = 0

    def read(name: str) -> bytes:
        if args.staged:
            return git('cat-file', 'blob', index[name][1])
        return (ROOT / name).read_bytes()

    try:
        manifest = {}
        for line in read('Vendor/checksums.sha256').decode().splitlines():
            if not line.strip():
                continue
            digest, name = line.split(None, 1)
            name = name.strip()
            if not re.fullmatch(r'[a-f0-9]{64}', digest) or name in manifest:
                raise ValueError('Invalid or duplicate checksum entry')
            manifest[name] = digest
        if set(manifest) != VENDORED:
            raise ValueError('Checksum manifest must cover exactly the reviewed vendor files')
        for name, expected in PINNED_SOURCES.items():
            if manifest[name] != expected:
                raise ValueError('Pinned upstream source checksum changed: ' + name)
    except (KeyError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print('Dependency manifest error:', error, file=sys.stderr)
        return 1

    for name in names:
        path = PurePosixPath(name)
        reason = None
        if path.is_absolute() or '..' in path.parts:
            reason = 'unsafe repository path'
        elif len(path.parts) == 1 and name not in TOP_LEVEL_FILES:
            reason = 'unreviewed top-level file'
        elif len(path.parts) > 1 and path.parts[0] not in TOP_LEVEL_DIRS:
            reason = 'unreviewed top-level directory'
        elif any(part in BANNED_PARTS or part.endswith(('.app', '.dSYM', '.xcresult', '.xcarchive')) for part in path.parts):
            reason = 'local state or build / diagnostic artifact'
        elif any(fnmatch.fnmatch(path.name, pattern) for pattern in BANNED_PATTERNS):
            reason = 'local configuration, diagnostics or signing material'
        elif index.get(name, ('', ''))[0] in {'120000', '160000'} or (ROOT / name).is_symlink():
            reason = 'unreviewed symlink or submodule'
        elif path.suffix in {'.dylib', '.a', '.o', '.so', '.zip', '.dmg', '.ipa', '.gz', '.bz2'} and name not in VENDORED:
            reason = 'unreviewed binary or archive'
        elif path.suffix in {'.png', '.jpg', '.jpeg', '.webp', '.heic', '.pdf', '.mp4'} and not name.startswith('MTPExplorer/Resources/Assets.xcassets/'):
            reason = 'media requires manual privacy review and an explicit allowlist entry'
        if reason:
            failures.append((name, reason))
            continue
        try:
            data = read(name)
        except (OSError, subprocess.CalledProcessError):
            failures.append((name, 'file could not be read'))
            continue
        total += len(data)
        if len(data) > 10 * 1024 * 1024:
            failures.append((name, 'file exceeds the 10 MiB source-file budget'))
        if name in manifest and hashlib.sha256(data).hexdigest() != manifest[name]:
            failures.append((name, 'vendored content does not match its checksum'))
        if name in PINNED_SOURCES:
            continue  # Exact official archive content was verified above.
        if HOME_PATH.search(data):
            failures.append((name, 'personal absolute home path detected'))
        if any(pattern.search(data) for pattern in CREDENTIAL_PATTERNS):
            failures.append((name, 'possible credential detected; matching content is withheld'))
        if name.endswith('.pbxproj') and re.search(rb'DEVELOPMENT_TEAM\s*=\s*[^;\s][^;]*;', data):
            failures.append((name, 'personal signing team configuration detected'))

    for name in sorted(VENDORED | {'Vendor/licenses/libmtp-COPYING.txt', 'Vendor/licenses/libusb-COPYING.txt', 'Vendor/SOURCES.md'}):
        if name not in names:
            failures.append((name, 'required third-party distribution file is missing'))
    if failures:
        print('Publication audit FAILED:', file=sys.stderr)
        for name, reason in failures:
            print(f'  {name}: {reason}', file=sys.stderr)
        return 1
    print(f'Publication audit passed: {len(names)} files, {total / 1024 / 1024:.2f} MiB; vendor hashes verified.')
    print('Manual review is still required for content and licensing changes.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
