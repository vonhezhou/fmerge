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
else:
    command = ['flutter', '--no-version-check', 'test', 'integration_test/desktop_test.dart',
        '-d', 'macos', '--no-pub', '--reporter', 'expanded', *arguments]
raise SystemExit(subprocess.call(command, cwd=root, env=env))
