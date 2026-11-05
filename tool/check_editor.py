#!/usr/bin/env python3
"""独立检查编辑器；只允许明确记录的上游诊断，新增诊断令检查失败。"""
from collections import Counter
import json
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
result = subprocess.run([shutil.which('dart') or 'dart', 'analyze', '--format', 'machine', 'packages/re_editor/lib'], cwd=root, capture_output=True, text=True)
baseline = Counter(json.loads((root / 'tool/editor_analysis_baseline.json').read_text()))
current = Counter()
for line in result.stdout.splitlines():
    parts = line.split('|', 7)
    if len(parts) == 8:
        current['|'.join([parts[0], parts[2], Path(parts[3]).relative_to(root).as_posix(), parts[7]])] += 1
new = current - baseline
if new or (result.returncode and not current):
    print('\n'.join(sorted(new.elements())) or result.stdout + result.stderr)
    sys.exit(1)
print(f'Editor analysis: no new diagnostics ({sum(current.values())} recorded upstream diagnostics).')
