import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/access.dart';
import '../core/git.dart';
import '../palette.dart';

class GitDialog extends StatefulWidget {
  const GitDialog({super.key, this.path, this.nativeAccess = false});
  final String? path;
  final bool nativeAccess;
  @override
  State<GitDialog> createState() => _GitDialogState();
}

class _GitDialogState extends State<GitDialog> {
  late final path = TextEditingController(text: widget.path);
  GitReview? review;
  final selected = <int>{};
  bool staged = false, busy = false;
  String? error, notice;
  @override
  void initState() {
    super.initState();
    if (widget.path != null) load();
  }

  @override
  void dispose() {
    path.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (busy || path.text.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      review = null;
      selected.clear();
    });
    try {
      final next = await GitReview.open(path.text, staged: staged);
      if (mounted) setState(() => review = next);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> browse() async {
    try {
      final file = await openFile(confirmButtonText: '选择 Git 工作区文件');
      if (file == null || !mounted) return;
      path.text = file.path;
      notice = null;
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> grantRepository() async {
    // 仓库根目录授权同时覆盖 .git；worktree 的外置索引需授权共同父目录。
    try {
      if (await DirectoryAccess.grant(p.dirname(p.absolute(path.text)))) {
        if (mounted) await load();
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> apply() async {
    final current = review;
    if (busy || current == null || selected.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await current.apply(selected);
      if (mounted) {
        setState(
          () =>
              notice = staged ? '所选差异块已取消暂存，工作区文件保持不变' : '所选差异块已暂存，其余修改保留在工作区',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: panel,
    title: const Text('Git · 按块暂存'),
    content: SizedBox(
      width: 860,
      height: 540,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: path,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: '工作区文件路径（可输入已删除文件的路径）',
                  ),
                  onChanged: (_) => setState(() {
                    review = null;
                    selected.clear();
                    error = notice = null;
                  }),
                  onSubmitted: (_) => load(),
                ),
              ),
              IconButton(
                tooltip: '选择 Git 文件',
                onPressed: busy ? null : browse,
                icon: const Icon(Icons.folder_open_outlined),
              ),
              IconButton(
                tooltip: '重新加载 Git 差异',
                onPressed: busy ? null : load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Unstaged · 未暂存')),
                  ButtonSegment(value: true, label: Text('Staged · 已暂存')),
                ],
                selected: {staged},
                onSelectionChanged: busy
                    ? null
                    : (v) {
                        setState(() {
                          staged = v.first;
                          notice = null;
                        });
                        load();
                      },
              ),
              const Spacer(),
              if (review != null)
                Text(
                  '${selected.length} / ${review!.patch.hunks.length} 块',
                  style: const TextStyle(color: muted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '按磁盘文件与 Git 索引的精确差异暂存，不受空白显示选项影响。编辑器中未保存的内容请先保存。',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          if (notice != null)
            Text(notice!, style: const TextStyle(color: green)),
          if (error != null)
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  error!,
                  style: const TextStyle(color: red),
                ),
              ),
            ),
          if (error != null && widget.nativeAccess)
            TextButton(
              onPressed: busy ? null : grantRepository,
              child: const Text('授权仓库根目录或共同父目录后重试'),
            ),
          if (busy) const LinearProgressIndicator(),
          if (review != null)
            Expanded(
              child: review!.patch.hunks.isEmpty
                  ? Center(child: Text(staged ? '此文件没有已暂存修改' : '此文件没有未暂存修改'))
                  : ListView.builder(
                      itemCount: review!.patch.hunks.length,
                      itemBuilder: (context, i) => Card(
                        color: elevated,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CheckboxListTile(
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                '差异块 ${i + 1}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              value: selected.contains(i),
                              onChanged: busy
                                  ? null
                                  : (value) => setState(() {
                                      if (value == true) {
                                        selected.add(i);
                                      } else {
                                        selected.remove(i);
                                      }
                                    }),
                            ),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                child: SelectableText.rich(
                                  TextSpan(
                                    children: [
                                      for (final line
                                          in review!.patch.hunks[i].split('\n'))
                                        TextSpan(
                                          text: '$line\n',
                                          style: TextStyle(
                                            color: line.startsWith('+')
                                                ? green
                                                : line.startsWith('-')
                                                ? red
                                                : muted,
                                          ),
                                        ),
                                    ],
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy || review == null
            ? null
            : () => setState(() {
                if (selected.length == review!.patch.hunks.length) {
                  selected.clear();
                } else {
                  selected.addAll(
                    List.generate(review!.patch.hunks.length, (i) => i),
                  );
                }
              }),
        child: const Text('全选 / 清空'),
      ),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      FilledButton(
        onPressed: busy || selected.isEmpty ? null : apply,
        child: Text(staged ? '取消暂存所选块' : '暂存所选块'),
      ),
    ],
  );
}
