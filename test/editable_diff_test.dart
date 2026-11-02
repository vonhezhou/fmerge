import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  testWidgets('真实编辑器可显示占位，复制不含占位，输入与撤销保留文档模型', (tester) async {
    final controller = CodeLineEditingController.fromText('alpha\nbeta');
    controller.diffLayout = const CodeDiffLayout(
      lineRows: [0, 3],
      totalRows: 4,
      rowColors: {0: Colors.red, 1: Colors.grey, 2: Colors.grey},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditor(
            controller: controller,
            wordWrap: false,
            chunkAnalyzer: const NonCodeChunkAnalyzer(),
            style: const CodeEditorStyle(fontSize: 14, fontHeight: 1.5),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    controller.selectAll();
    expect(controller.selectedText, 'alpha\nbeta');
    controller.runRevocableOp(() => controller.replaceSelection('中文\nresult'));
    await tester.pumpAndSettle();
    expect(controller.text, '中文\nresult');
    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, 'alpha\nbeta');
    controller.redo();
    await tester.pumpAndSettle();
    expect(controller.text, '中文\nresult');
    expect(tester.takeException(), isNull);
  });
}
