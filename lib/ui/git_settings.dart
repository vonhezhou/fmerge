import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/launch.dart';
import '../palette.dart';

class GitSettings extends StatelessWidget {
  const GitSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final commands = LaunchOptions.gitConfiguration(Platform.resolvedExecutable)
        .split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '将 fmerge 用作 Git 外部工具',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          '复制对应命令，在终端执行一次。下面的按钮只复制命令，不修改 Git 配置。',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 20),
        _card(
          context,
          '文件比较',
          'git difftool',
          '传入两个文件，并排检查修改。',
          commands.take(2).join('\n'),
        ),
        const SizedBox(height: 14),
        _card(
          context,
          '三方合并',
          'git mergetool',
          '传入共同祖先、左右版本和结果路径；Git 等待保存并接收退出状态。',
          commands.skip(2).join('\n'),
        ),
        const SizedBox(height: 20),
        const Text('当前程序', style: TextStyle(color: muted, fontSize: 11)),
        const SizedBox(height: 6),
        SelectableText(
          Platform.resolvedExecutable,
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        const SizedBox(height: 14),
        const Text(
          '移动或重新安装应用后，请从新位置重新复制配置。三方合并由 Git 或命令行打开。',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    String title,
    String command,
    String description,
    String script,
  ) => Material(
    color: elevated,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  command,
                  style: const TextStyle(color: accent, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.copy_outlined, size: 16),
              label: Text('复制$title配置'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: script));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('已复制$title配置，请在终端执行')));
                }
              },
            ),
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                '查看完整命令',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: SelectableText(
                      script,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
