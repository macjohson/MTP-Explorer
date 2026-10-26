#!/usr/bin/env python3
"""Copy libmtp's public header and dylib closure, rewrite install names, sign locally."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
prefix = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(subprocess.check_output(['brew', '--prefix', 'libmtp'], text=True).strip())
destination = root / 'Vendor/lib'
destination.mkdir(parents=True, exist_ok=True)
shutil.copy2(prefix / 'include/libmtp.h', root / 'Vendor/include/libmtp.h')
queue = [prefix / 'lib/libmtp.9.dylib']
seen = set()
while queue:
    source = queue.pop(0)
    if source.name in seen:
        continue
    seen.add(source.name)
    target = destination / source.name
    shutil.copy2(source.resolve(), target)
    target.chmod(0o755)
    dependencies = subprocess.check_output(['otool', '-L', str(source)], text=True).splitlines()[2:]
    subprocess.run(['install_name_tool', '-id', '@rpath/' + source.name, str(target)], check=True)
    for line in dependencies:
        dependency = line.strip().split(' (')[0]
        if dependency.startswith(('/usr/lib/', '/System/')):
            continue
        path = Path(dependency)
        if not path.is_absolute():
            raise RuntimeError('Unexpected dependency: ' + dependency)
        queue.append(path)
        subprocess.run(['install_name_tool', '-change', dependency, '@loader_path/' + path.name, str(target)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(target)], check=True)
print('Prepared:', ', '.join(sorted(seen)))
