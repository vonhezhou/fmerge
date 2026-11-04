import 'package:flutter/material.dart';

class GoToLineDialog extends StatefulWidget {
  const GoToLineDialog({
    super.key,
    required this.lineCount,
    required this.currentLine,
  });
  final int lineCount, currentLine;

  @override
  State<GoToLineDialog> createState() => _GoToLineDialogState();
}

class _GoToLineDialogState extends State<GoToLineDialog> {
  final _form = GlobalKey<FormState>();
  late final _field = TextEditingController(text: '${widget.currentLine}')
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: '${widget.currentLine}'.length,
    );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, int.parse(_field.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('跳转到行'),
    content: SizedBox(
      width: 300,
      child: Form(
        key: _form,
        child: TextFormField(
          controller: _field,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '行号',
            helperText: '请输入 1–${widget.lineCount} 之间的行号',
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) {
            final line = int.tryParse(value?.trim() ?? '');
            return line == null || line < 1 || line > widget.lineCount
                ? '行号范围为 1–${widget.lineCount}'
                : null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('跳转')),
    ],
  );
}
