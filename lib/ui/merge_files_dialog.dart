import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/launch.dart';

class MergeFilesDialog extends StatefulWidget {
  const MergeFilesDialog({
    super.key,
    this.recent = const [],
    this.onFileSelected,
  });
  final List<LaunchOptions> recent;
  final Future<void> Function(String)? onFileSelected;
  @override
  State<MergeFilesDialog> createState() => _MergeFilesDialogState();
}

class _MergeFilesDialogState extends State<MergeFilesDialog> {
  final _form = GlobalKey<FormState>();
  final _paths = List.generate(4, (_) => TextEditingController());
  bool _picking = false;
  String? _error;
  static const _labels = ['共同祖先', '左侧输入', '右侧输入', '结果保存位置'];
  @override
  void initState() {
    super.initState();
    if (widget.recent.isNotEmpty) _fill(widget.recent.first);
  }

  void _fill(LaunchOptions options) {
    final values = [options.base, options.left, options.right, options.output];
    for (var i = 0; i < 4; i++) {
      _paths[i].text = values[i] ?? '';
    }
  }

  @override
  void dispose() {
    for (final path in _paths) {
      path.dispose();
    }
    super.dispose();
  }

  Future<void> _browse(int side) async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      String? selected;
      if (side == 3) {
        selected = (await getSaveLocation(
          suggestedName: _paths[3].text.isEmpty
              ? 'merged-${p.basename(_paths[1].text.isEmpty ? 'result.txt' : _paths[1].text)}'
              : p.basename(_paths[3].text),
          confirmButtonText: '选择结果位置',
        ))?.path;
      } else {
        final file = await openFile(confirmButtonText: '选择${_labels[side]}');
        selected = file?.path;
        if (selected != null) await widget.onFileSelected?.call(selected);
      }
      if (mounted && selected != null) {
        setState(() => _paths[side].text = selected!);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '选择文件失败：$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _open() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      LaunchOptions(
        base: _paths[0].text,
        left: _paths[1].text,
        right: _paths[2].text,
        output: _paths[3].text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_picking,
    child: AlertDialog(
      title: const Text('打开三方合并'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.recent.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<int>(
                      tooltip: '最近使用的合并',
                      onSelected: (i) =>
                          setState(() => _fill(widget.recent[i])),
                      itemBuilder: (_) => [
                        for (var i = 0; i < widget.recent.length; i++)
                          PopupMenuItem(
                            value: i,
                            child: Text(
                              '${p.basename(widget.recent[i].left!)} ↔ ${p.basename(widget.recent[i].right!)}',
                            ),
                          ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('最近使用的合并 ▾'),
                      ),
                    ),
                  ),
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('merge-path-$i'),
                            controller: _paths[i],
                            enabled: !_picking,
                            decoration: InputDecoration(
                              labelText: _labels[i],
                              isDense: true,
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? '请选择或输入${_labels[i]}'
                                : null,
                          ),
                        ),
                        IconButton(
                          key: ValueKey('merge-browse-$i'),
                          tooltip: '选择${_labels[i]}',
                          onPressed: _picking ? null : () => _browse(i),
                          icon: const Icon(Icons.folder_open),
                        ),
                      ],
                    ),
                  ),
                if (_error != null) SelectableText(_error!),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _picking ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('merge-open'),
          onPressed: _picking ? null : _open,
          child: const Text('打开合并'),
        ),
      ],
    ),
  );
}
