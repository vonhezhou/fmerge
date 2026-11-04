import 'diff.dart';
import 'files.dart';

/// 只在任务开始时创建快照；原始文本仅在需要还原换行时传入。
class CompareTask {
  const CompareTask({
    required this.left,
    required this.right,
    required this.options,
    this.leftOriginal,
    this.rightOriginal,
    this.base,
  });

  final String left, right;
  final String? leftOriginal, rightOriginal, base;
  final CompareOptions options;
}

typedef CompareResult = ({DiffDocument diff, List<DiffDocument>? branches});
typedef CompareRunner = Future<CompareResult> Function(CompareTask task);

/// 换行重建与三方输入比较共用一个后台任务，避免在 UI 线程遍历全文。
CompareResult runCompareTask(CompareTask task) {
  final left = task.leftOriginal == null
      ? task.left
      : TextFile.empty(task.leftOriginal!).materialize(task.left);
  final right = task.rightOriginal == null
      ? task.right
      : TextFile.empty(task.rightOriginal!).materialize(task.right);
  return (
    diff: compare(DiffInput(left, right, task.options)),
    branches: task.base == null
        ? null
        : [
            compare(DiffInput(task.base!, left, task.options)),
            compare(DiffInput(task.base!, right, task.options)),
          ],
  );
}
