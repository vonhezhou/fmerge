import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  test('查找高匹配文本，记录完整查询耗时', () async {
    const lines = int.fromEnvironment('LINES', defaultValue: 64000);
    for (var round = 0; round < 3; round++) {
      final editor = CodeLineEditingController.fromText(
        List.filled(lines, 'x').join('\n'),
      );
      final finder = CodeFindController(editor);
      try {
        final watch = Stopwatch()..start();
        finder.findMode();
        finder.findInputController.text = 'x';
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (finder.value?.searching == true &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(finder.value?.searching, false);
        expect(finder.value?.result?.matches.length, lines);
        // ignore: avoid_print
        print(
          'find: lines=$lines round=$round elapsedMs=${watch.elapsedMilliseconds}',
        );
      } finally {
        finder.dispose();
        editor.dispose();
      }
    }
  });
}
