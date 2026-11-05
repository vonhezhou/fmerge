#!/usr/bin/env python3
"""打包已经构建的 Release；不签名、不公证、不发布。"""
from pathlib import Path
import hashlib
import re
import shutil
import platform
import subprocess
import sys
import tarfile
root = Path(__file__).resolve().parents[1]
match = re.search(r'^version:\s*([^\s+#]+)', (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.MULTILINE)
if match is None:
    raise SystemExit('pubspec.yaml 缺少 version')
version = match[1]
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?', version):
    raise SystemExit('pubspec.yaml 的 version 格式无效')
dist = root / 'dist'
dist.mkdir(exist_ok=True)
arch = 'arm64' if platform.machine().lower() in ('arm64', 'aarch64') else 'x64'
if sys.platform == 'darwin':
    source = root / 'build/macos/Build/Products/Release/fmerge.app'
    if not source.exists():
        raise SystemExit('请先运行 flutter build macos --release')
    artifact = dist / f'fmerge-{version}-macos.zip'
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(source), str(artifact)], check=True)
elif sys.platform == 'win32':
    source = root / f'build/windows/{arch}/runner/Release'
    if not source.exists():
        raise SystemExit('请先运行 flutter build windows --release')
    artifact = Path(shutil.make_archive(str(dist / f'fmerge-{version}-windows-{arch}'), 'zip', source))
elif sys.platform == 'linux':
    source = root / f'build/linux/{arch}/release/bundle'
    if not source.exists():
        raise SystemExit('请先运行 flutter build linux --release')
    artifact = dist / f'fmerge-{version}-linux-{arch}.tar.gz'
    with tarfile.open(artifact, 'w:gz') as archive:
        archive.add(source, arcname='fmerge')
else:
    raise SystemExit('仅支持 macOS / Windows / Linux')
# 只为当前版本的发布包生成校验和，避免将目录中的历史版本混入。
artifacts = sorted([*dist.glob(f'fmerge-{version}-*.zip'), *dist.glob(f'fmerge-{version}-*.tar.gz')])
checksums = []
for entry in artifacts:
    digest = hashlib.sha256()
    with entry.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    checksums.append(f'{digest.hexdigest()}  {entry.name}\n')
(dist / 'SHA256SUMS.txt').write_text(''.join(checksums), encoding='utf-8')
print(artifact)
