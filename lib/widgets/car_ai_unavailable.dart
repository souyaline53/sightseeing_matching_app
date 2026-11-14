import 'package:flutter/material.dart';

Future<void> showCarAiUnavailable(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    content: const Text('車での移動はAIルート検索に対応していません。'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('閉じる'),
      ),
    ],
  ),
);

/// The disabled button stays grey while a tap explains why AI is unavailable.
class CarAiUnavailable extends StatelessWidget {
  final bool unavailable;
  final Widget child;
  const CarAiUnavailable({
    super.key,
    required this.unavailable,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => unavailable
      ? Semantics(
          button: true,
          label: '車での移動はAIルート検索に対応していません。',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showCarAiUnavailable(context),
            child: AbsorbPointer(child: child),
          ),
        )
      : child;
}
