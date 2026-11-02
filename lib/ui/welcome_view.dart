import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../palette.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({
    super.key,
    required this.onCompare,
    required this.onMerge,
    required this.onPaste,
    required this.recent,
    required this.onRecent,
  });
  final VoidCallback onCompare, onMerge, onPaste;
  final List<Map<String, dynamic>> recent;
  final ValueChanged<Map<String, dynamic>> onRecent;

  @override
  Widget build(BuildContext context) => Center(
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
                    color: accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.difference_outlined,
                    color: accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Text(
                  '你的代码，清晰对照。',
                  style: TextStyle(color: muted, fontSize: 13),
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
            const Text(
              '从两份文件开始，或将不同版本合并为一个可靠的结果。',
              style: TextStyle(fontSize: 14, color: muted),
            ),
            const SizedBox(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _action(
                    Icons.compare_arrows_rounded,
                    '文件比较',
                    '并排查看差异，逐块采用修改。',
                    '打开两个文件',
                    onCompare,
                    primary: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _action(
                    Icons.merge_rounded,
                    '三方合并',
                    '对照共同祖先，逐一解决冲突。',
                    '打开三方合并',
                    onMerge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onPaste,
              icon: const Icon(Icons.content_paste_outlined, size: 16),
              label: const Text('粘贴文本比较'),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Text(
                  recent.isEmpty ? '使用提示' : '最近打开',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 10),
            if (recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '⌘ / Ctrl O  打开文件     ·     F7  跳转差异     ·     ⌘ / Ctrl S  保存',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              )
            else
              for (final entry in recent.take(6)) _recentItem(entry),
          ],
        ),
      ),
    ),
  );

  Widget _action(
    IconData icon,
    String title,
    String description,
    String label,
    VoidCallback onTap, {
    bool primary = false,
  }) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: panel,
      border: Border.all(
        color: primary ? accent.withValues(alpha: .4) : border,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: primary ? accent : muted),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(description, style: const TextStyle(color: muted, fontSize: 12)),
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

  Widget _recentItem(Map<String, dynamic> entry) {
    final left = entry['left'] as String;
    final right = entry['right'] as String;
    return Tooltip(
      message: '$left\n$right',
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: Icon(
          entry['base'] == null ? Icons.compare_arrows : Icons.merge,
          color: muted,
          size: 20,
        ),
        title: Text(
          '${p.basename(left)}  ↔  ${p.basename(right)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        subtitle: Text(
          p.dirname(right),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        trailing: const Icon(Icons.north_west, size: 15, color: muted),
        onTap: () => onRecent(entry),
      ),
    );
  }
}
