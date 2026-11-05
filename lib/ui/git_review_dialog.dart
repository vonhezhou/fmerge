import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/files.dart';
import '../core/git.dart';

class GitReviewDialog extends StatefulWidget {
  const GitReviewDialog({
    super.key,
    required this.path,
    required this.encoding,
  });
  final String path;
  final TextEncoding encoding;
  @override
  State<GitReviewDialog> createState() => _GitReviewDialogState();
}

class _GitReviewDialogState extends State<GitReviewDialog> {
  bool _staged = false, _busy = true;
  GitReview? _review;
  String? _error;
  final _selected = <int>{};
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _review = null;
      _selected.clear();
    });
    try {
      final review = await GitReview.open(widget.path, staged: _staged);
      if (mounted && generation == _generation) {
        setState(() => _review = review);
      }
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      await _review!.apply({..._selected});
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  String _display(String bytes) {
    final truncated = bytes.length > 65536;
    final preview = truncated
        ? bytes.substring(0, bytes.lastIndexOf('\n', 65536).clamp(0, 65536))
        : bytes;
    try {
      final text = TextFile.decode(latin1.encode(preview), widget.encoding).$1;
      return truncated ? '$text\n…预览已截断，操作作用于完整区块' : text;
    } catch (_) {
      return '无法按 ${widget.encoding.label} 预览此区块，请检查文件编码。';
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Git 暂存预览'),
    content: SizedBox(
      width: 820,
      height: 480,
      child: Column(
        children: [
          Text(widget.path, maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(
            children: [
              ChoiceChip(
                label: const Text('未暂存'),
                selected: !_staged,
                onSelected: _busy
                    ? null
                    : (_) {
                        _staged = false;
                        _load();
                      },
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('已暂存'),
                selected: _staged,
                onSelected: _busy
                    ? null
                    : (_) {
                        _staged = true;
                        _load();
                      },
              ),
              const Spacer(),
              IconButton(
                tooltip: '刷新 Git 差异',
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_error != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 96),
              child: SingleChildScrollView(child: SelectableText(_error!)),
            ),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _review == null
                ? const SizedBox()
                : _review!.patch.hunks.isEmpty
                ? const Center(child: Text('此文件没有对应修改'))
                : ListView.builder(
                    itemCount: _review!.patch.hunks.length,
                    itemBuilder: (context, i) => Column(
                      children: [
                        CheckboxListTile(
                          title: Text('区块 ${i + 1}'),
                          value: _selected.contains(i),
                          onChanged: (v) => setState(() {
                            if (v!) {
                              _selected.add(i);
                            } else {
                              _selected.remove(i);
                            }
                          }),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(
                            _display(_review!.patch.hunks[i]),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Divider(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                _selected.clear();
                _selected.addAll(
                  List.generate(_review?.patch.hunks.length ?? 0, (i) => i),
                );
              }),
        child: const Text('选择全部区块'),
      ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      FilledButton(
        onPressed: _busy || _selected.isEmpty || _error != null ? null : _apply,
        child: Text(_staged ? '取消暂存所选块' : '暂存所选块'),
      ),
    ],
  );
}
