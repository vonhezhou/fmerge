import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/diff.dart';
import 'package:fmerge/core/myers.dart';
import 'package:fmerge/core/merge.dart';

void main() {
  test('Myers 随机用例能重建右侧并给出最短编辑长度', () {
    final random = Random(42);
    for (var trial = 0; trial < 600; trial++) {
      final a = List.generate(random.nextInt(15), (_) => random.nextInt(5));
      final b = List.generate(random.nextInt(15), (_) => random.nextInt(5));
      final result = myers(a, b);
      final output = <int>[];
      var cursor = 0, cost = 0;
      for (final c in result.changes) {
        expect(c.aStart, greaterThanOrEqualTo(cursor));
        output.addAll(a.sublist(cursor, c.aStart));
        output.addAll(b.sublist(c.bStart, c.bEnd));
        cursor = c.aEnd;
        cost += c.aEnd - c.aStart + c.bEnd - c.bStart;
      }
      output.addAll(a.sublist(cursor));
      expect(output, b);
      final dp = List.generate(
        a.length + 1,
        (_) => List.filled(b.length + 1, 0),
      );
      for (var i = 1; i <= a.length; i++) {
        for (var j = 1; j <= b.length; j++) {
          dp[i][j] = a[i - 1] == b[j - 1]
              ? dp[i - 1][j - 1] + 1
              : max(dp[i - 1][j], dp[i][j - 1]);
        }
      }
      expect(cost, a.length + b.length - 2 * dp.last.last);
    }
  });
  test('超时保留可重建的完整替换区间', () {
    final result = myers([1, 2, 3, 4], [1, 5, 6, 4], budget: Duration.zero);
    expect(result.timedOut, true);
    expect(result.changes.single.aStart, 1);
    expect(result.changes.single.aEnd, 3);
  });
  test('占位不进入原文，保留末尾换行差异', () {
    final d = computeDiff(('a\nb\n', 'a\nadded\nb'));
    expect(
      d.rows.where((r) => r.leftLine != null).map((r) => r.left).join('\n'),
      'a\nb\n',
    );
    expect(
      d.rows.where((r) => r.rightLine != null).map((r) => r.right).join('\n'),
      'a\nadded\nb',
    );
    expect(d.changes, isNotEmpty);
    expect(selectedText(d.left, 0, 0, 2, 0), 'a\nb\n');
  });
  test('Emoji 与组合字符高亮不切开字素簇', () {
    final d = computeDiff(('👨‍👩‍👧‍👦 a', '👩‍💻 a'));
    expect(d.rows.single.leftMarks.single.end, '👨‍👩‍👧‍👦'.length);
    expect(d.rows.single.rightMarks.single.end, '👩‍💻'.length);
  });
  test('跨视觉占位复制与反向选择得到真实文档', () {
    final d = computeDiff(('alpha\nbeta', 'alpha\nx\ny\nbeta'));
    expect(d.rows.where((r) => r.left == null).length, 2);
    expect(selectedText(d.left, 1, 4, 0, 0), 'alpha\nbeta');
  });
  test('独立修改自动合并，相邻替换不误报冲突', () {
    final plan = planMerge('a\nb\nc', 'A\nb\nc', 'a\nB\nc');
    expect(plan.conflicts, isEmpty);
    expect(plan.compose({}), 'A\nB\nc');
  });
  test('相同修改只合并一次', () {
    final plan = planMerge('a\nb', 'a\nB', 'a\nB');
    expect(plan.conflicts, isEmpty);
    expect(plan.compose({}), 'a\nB');
  });
  test('同位置插入生成冲突且支持双方、单方和原文', () {
    final plan = planMerge('a\nb', 'a\nleft\nb', 'a\nright\nb');
    final id = plan.conflicts.single.id;
    expect(plan.compose({}), 'a\nb');
    expect(plan.compose({id: MergeChoice.left}), 'a\nleft\nb');
    expect(plan.compose({id: MergeChoice.right}), 'a\nright\nb');
    expect(plan.compose({id: MergeChoice.both}), 'a\nleft\nright\nb');
  });
  test('重叠删除与替换不丢内容', () {
    final plan = planMerge('a\nb\nc\nd', 'a\nd', 'a\nb\nC\nd');
    final id = plan.conflicts.single.id;
    expect(plan.compose({id: MergeChoice.left}), 'a\nd');
    expect(plan.compose({id: MergeChoice.right}), 'a\nb\nC\nd');
  });
}
