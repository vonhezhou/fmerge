#!/usr/bin/env python3
"""fmerge 检查入口：静态、业务/界面测试；可选真实平台集成和构建。"""
import argparse
from pathlib import Path
import subprocess
import shutil
import sys
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--native', action='store_true', help='运行真实 macOS 集成测试')
parser.add_argument('--build', action='store_true', help='构建当前桌面平台 Release')
options = parser.parse_args()
commands = [
    ['dart', 'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'integration_test'],
    ['flutter', '--no-version-check', 'analyze'],
    [sys.executable, 'tool/check_editor.py'],
    ['flutter', '--no-version-check', 'test', 'test'],
]
if options.native:
    if sys.platform != 'darwin':
        parser.error('--native 需要 macOS，不能将其他平台的检查当作原生验收')
    commands.append([sys.executable, 'tool/test_macos.py'])
if options.build:
    platform = {'darwin': 'macos', 'win32': 'windows', 'linux': 'linux'}.get(sys.platform)
    if platform is None:
        parser.error('仅支持桌面平台构建')
    commands.append(['flutter', '--no-version-check', 'build', platform, '--release'])
for command in commands:
    command[0] = shutil.which(command[0]) or command[0]
    print('+ ' + ' '.join(command), flush=True)
    subprocess.run(command, cwd=root, check=True)
