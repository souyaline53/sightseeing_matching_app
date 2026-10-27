import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<String?> askPresetName(BuildContext context, {String initial = ''}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: initial),
    );

class _NameDialog extends HookConsumerWidget {
  final String initial;
  const _NameDialog({required this.initial});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = useTextEditingController(text: initial);
    return AlertDialog(
      title: const Text('プリセット名（任意）'),
      content: TextField(
        controller: text,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(hintText: '例：週末の小さな冒険'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, text.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
