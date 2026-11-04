import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../palette.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({
    super.key,
    required this.onCompare,
    required this.onPaste,
    required this.recent,
    required this.onRecent,
  });
  final VoidCallback onCompare, onPaste;
  final List<Map<String, dynamic>> recent;
  final ValueChanged<Map<String, dynamic>> onRecent;

  @override
  Widget build(BuildContext context) {
    final entries = recent
        .where(
          (entry) =>
              entry['left'] is String &&
              entry['right'] is String &&
              entry['base'] == null,
        )
        .take(6)
        .toList();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).accent
                          .withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.difference_outlined,
                      color: AppPalette.of(context).accent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '你的代码，清晰对照。',
                    style: TextStyle(
                      color: AppPalette.of(context).muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                '看清每一次修改',
                style: TextStyle(
                  fontSize: 34,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '选择两份文件并排比较，也可以新建文本比较。',
                style: TextStyle(
                  fontSize: 14,
                  color: AppPalette.of(context).muted,
                ),
              ),
              const SizedBox(height: 28),
              _action(
                context,
                Icons.folder_open_outlined,
                '文件比较',
                '直接选择两个文件，支持多选；只选一个时会继续选择另一份。',
                '打开文件',
                onCompare,
                primary: true,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.note_add_outlined, size: 16),
                label: const Text('新建文本比较'),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Text(
                    entries.isEmpty ? '使用提示' : '最近打开',
                    style: TextStyle(
                      color: AppPalette.of(context).muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 10),
              if (entries.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '⌘ / Ctrl O  打开文件     ·     F7  跳转差异     ·     ⌘ / Ctrl S  保存',
                    style: TextStyle(
                      color: AppPalette.of(context).muted,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                for (final entry in entries) _recentItem(context, entry),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context,
    IconData icon,
    String title,
    String description,
    String label,
    VoidCallback onTap, {
    bool primary = false,
  }) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: AppPalette.of(context).panel,
      border: Border.all(
        color: primary
            ? AppPalette.of(context).accent.withValues(alpha: .4)
            : AppPalette.of(context).border,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 24,
          color: primary
              ? AppPalette.of(context).accent
              : AppPalette.of(context).muted,
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
        ),
        const SizedBox(height: 22),
        if (primary)
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add, size: 16),
            label: Text(label),
          )
        else
          OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add, size: 16),
            label: Text(label),
          ),
      ],
    ),
  );

  Widget _recentItem(BuildContext context, Map<String, dynamic> entry) {
    final left = entry['left'] as String;
    final right = entry['right'] as String;
    final base = entry['base'];
    final output = entry['output'];
    final leftDirectory = p.dirname(left);
    final rightDirectory = p.dirname(right);
    return Tooltip(
      message: [
        if (base is String) '共同祖先：$base',
        '左侧：$left',
        '右侧：$right',
        if (output is String) '结果：$output',
      ].join('\n'),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: Icon(
          entry['base'] == null ? Icons.compare_arrows : Icons.merge,
          color: AppPalette.of(context).muted,
          size: 20,
        ),
        title: Text(
          '${p.basename(left)}  ↔  ${p.basename(right)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final directory in [
              leftDirectory == rightDirectory
                  ? rightDirectory
                  : '左：$leftDirectory',
              if (leftDirectory != rightDirectory) '右：$rightDirectory',
            ])
              Text(
                directory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: AppPalette.of(context).muted,
                ),
              ),
          ],
        ),
        trailing: Icon(
          Icons.north_west,
          size: 15,
          color: AppPalette.of(context).muted,
        ),
        onTap: () => onRecent(entry),
      ),
    );
  }
}
