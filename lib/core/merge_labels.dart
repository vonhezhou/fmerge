enum MergeOperation { files, merge, rebase }

/// 来源只描述当前输入快照，不把左右位置等同于“我的/别人的修改”。
class MergeLabels {
  const MergeLabels({
    this.operation = MergeOperation.files,
    this.summary = '三方文件合并 · 按输入路径区分左右',
    this.leftTitle = '左侧输入',
    this.rightTitle = '右侧输入',
    this.leftSource = '未确认 Git 上下文',
    this.rightSource = '未确认 Git 上下文',
    this.leftAction = '采用左侧',
    this.rightAction = '采用右侧',
  });
  final MergeOperation operation;
  final String summary, leftTitle, rightTitle, leftSource, rightSource;
  final String leftAction, rightAction;
  String detail(bool left) => operation == MergeOperation.files
      ? '${left ? '--local' : '--remote'} 仅表示输入位置，不表示文件来自本机或远端仓库。'
      : '${left ? 'ours / current / LOCAL' : 'theirs / incoming / REMOTE'}\n${left ? leftSource : rightSource}';
}
