"""用 Python 标准编码表交叉验证 Dart 解码结果，不依赖网络。"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", default="dart")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    fixtures = {}
    multibyte = {"gbk", "big5", "shift_jis", "euc_jp"}
    names = [*sorted(multibyte), *(f"cp{i}" for i in range(1250, 1259)), "cp437", "cp737"]
    for name in names:
        rows = []
        inputs = [bytes([i]) for i in range(256)]
        if name in multibyte:
            inputs.extend(bytes([a, b]) for a in range(128, 256) for b in range(256))
        for data in inputs:
            try:
                text = data.decode(name)
            except UnicodeError:
                continue
            if len(text) == 1:
                rows.append([list(data), text])
        fixtures[name] = rows
    with tempfile.TemporaryDirectory(prefix="fmerge-reference-") as temp:
        path = Path(temp) / "reference.json"
        path.write_text(json.dumps(fixtures), encoding="utf-8")
        result = subprocess.run(
            [args.dart, "run", "tool/verify_legacy_encodings.dart", str(path)], cwd=root
        )
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
