#!/usr/bin/env python3
"""打包已经构建的 Release；不签名、不公证、不发布。"""
from pathlib import Path
import shutil
import platform
import subprocess
import sys
import tarfile
root = Path(__file__).resolve().parents[1]
dist = root / 'dist'
dist.mkdir(exist_ok=True)
arch = 'arm64' if platform.machine().lower() in ('arm64', 'aarch64') else 'x64'
if sys.platform == 'darwin':
    source = root / 'build/macos/Build/Products/Release/fmerge.app'
    if not source.exists():
        raise SystemExit('请先运行 flutter build macos --release')
    artifact = dist / 'fmerge-0.1.0-macos.zip'
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(source), str(artifact)], check=True)
elif sys.platform == 'win32':
    source = root / f'build/windows/{arch}/runner/Release'
    if not source.exists():
        raise SystemExit('请先运行 flutter build windows --release')
    artifact = Path(shutil.make_archive(str(dist / f'fmerge-0.1.0-windows-{arch}'), 'zip', source))
elif sys.platform == 'linux':
    source = root / f'build/linux/{arch}/release/bundle'
    if not source.exists():
        raise SystemExit('请先运行 flutter build linux --release')
    artifact = dist / f'fmerge-0.1.0-linux-{arch}.tar.gz'
    with tarfile.open(artifact, 'w:gz') as archive:
        archive.add(source, arcname='fmerge')
else:
    raise SystemExit('仅支持 macOS / Windows / Linux')
print(artifact)
