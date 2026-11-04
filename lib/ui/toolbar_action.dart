import 'package:flutter/material.dart';

import '../palette.dart';

class ToolbarAction extends StatelessWidget {
  const ToolbarAction({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    required this.showLabel,
    this.selected = false,
  });
  final IconData icon;
  final String label, tooltip;
  final VoidCallback? onPressed;
  final bool showLabel, selected;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: showLabel ? (label.length > 4 ? 60 : 50) : 34,
      height: showLabel ? 58 : 34,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          foregroundColor: selected ? accent : muted,
          backgroundColor: selected ? accent.withValues(alpha: .1) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19),
            if (showLabel) ...[
              const SizedBox(height: 4),
              Text(label, maxLines: 1, style: const TextStyle(fontSize: 10)),
            ],
          ],
        ),
      ),
    ),
  );
}
