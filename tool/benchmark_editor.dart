import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/session.dart';
import 'package:re_editor/re_editor.dart';

// 通过 flutter test tool/benchmark_editor.dart 运行；仅测控制器与会话，不含渲染。
void main() {
  test('编辑器选择与未保存状态读取基准', () {
    const count = int.fromEnvironment('LINES', defaultValue: 100000);
    const iterations = 50;
    final text = List.generate(
      count,
      (i) => 'final value_$i = "sample text for line $i";',
    ).join('\n');
    final session = CompareSession(TextFile.empty(text), TextFile.empty(text));
    addTearDown(session.dispose);
    var dirtyCount = 0;
    void move(int i) {
      session.rightEditor.selection = CodeLineSelection.collapsed(
        index: i % count,
        offset: 2,
      );
      if (session.leftDirty) dirtyCount++;
      if (session.rightDirty) dirtyCount++;
    }

    for (var i = 0; i < 5; i++) {
      move(i);
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      move(i + 5);
    }
    watch.stop();
    expect(dirtyCount, 0);
    stdout.writeln(
      jsonEncode({
        'lines': count,
        'iterations': iterations,
        'elapsedMs': watch.elapsedMicroseconds / 1000,
        'msPerMove': watch.elapsedMicroseconds / iterations / 1000,
        'peakRssMiB': ProcessInfo.maxRss / 1048576,
        'scope': 'Flutter test JIT; controller selection + session listeners + dirty reads; no UI rendering',
      }),
    );
  });
}
