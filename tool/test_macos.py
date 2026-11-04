#!/usr/bin/env python3
"""在独立沙盒内运行真实 macOS 集成测试。"""
import os
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
env = os.environ.copy()
env['XCODE_XCCONFIG_FILE'] = str(root / 'tool/integration.xcconfig')
arguments = sys.argv[1:]
performance = '--performance' in arguments
if performance:
    arguments.remove('--performance')
if performance:
    subprocess.run(['flutter', '--no-version-check', 'build', 'macos', '--release',
        '--target', 'tool/performance_app.dart', '--no-pub', *arguments], cwd=root, env=env, check=True)
    command = [str(root / 'build/macos/Build/Products/Release/fmerge.app/Contents/MacOS/fmerge')]
    raise SystemExit(subprocess.call(command, cwd=root, env=env))
# 桌面端按文件启动独立 Flutter 测试进程，避免目录模式复用已退出的调试连接。
for target in sorted((root / 'integration_test').glob('*_test.dart')):
    command = ['flutter', '--no-version-check', 'test', str(target.relative_to(root)),
        '-d', 'macos', '--no-pub', '--reporter', 'expanded', *arguments]
    result = subprocess.call(command, cwd=root, env=env)
    if result:
        raise SystemExit(result)
