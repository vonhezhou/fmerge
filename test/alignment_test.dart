import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/diff.dart';
import 'package:fmerge/core/alignment.dart';

void main() {
  test('三方显示以祖先对齐双方插入和删除', () {
    final l = computeDiff(('a\nb\nc', 'a\nL1\nL2\nb\nc'));
    final r = computeDiff(('a\nb\nc', 'a\nR\nc'));
    final a = alignThreeWay(l, r);
    expect(a.baseRows, [0, 3, 4]);
    expect(a.localRows, [0, 1, 2, 3, 4]);
    expect(a.remoteRows, [0, 3, 4]);
    expect(a.totalRows, 5);
  });
  test('相同双方修改仍然显示相对于祖先的修改', () {
    final d = computeDiff(('a\nb', 'a\nB'));
    final a = alignThreeWay(d, d);
    expect(a.changeRows, [1]);
    expect(a.localRows, a.remoteRows);
  });
  test('显示选项不会把忽略的空白写入真实文本', () {
    final d = compare(
      const DiffInput(
        'a  \nb',
        'a\nB',
        CompareOptions(whitespace: WhitespaceMode.trailing, ignoreCase: true),
      ),
    );
    expect(d.changes, isEmpty);
    expect(d.left.first, 'a  ');
    expect(d.right.last, 'B');
  });
  test('换行符可以显示为差异或忽略', () {
    expect(
      compare(const DiffInput('a\r\n', 'a\n', CompareOptions(ignoreEol: false)))
          .changes,
      isNotEmpty,
    );
    expect(compare(const DiffInput('a\r\n', 'a\n')).changes, isEmpty);
  });
}
