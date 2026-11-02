#!/usr/bin/env python3
"""在独立沙盒内运行真实 macOS 集成测试。"""
import os
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
env = os.environ.copy()
env['XCODE_XCCONFIG_FILE'] = str(root / 'tool/integration.xcconfig')
raise SystemExit(subprocess.call(['flutter', '--no-version-check', 'test',
    'integration_test/desktop_test.dart', '-d', 'macos', '--no-pub',
    '--reporter', 'expanded', *sys.argv[1:]], cwd=root, env=env))
