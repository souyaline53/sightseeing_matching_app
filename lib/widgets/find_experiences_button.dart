import 'package:flutter/material.dart';

class FindExperiencesButton extends StatelessWidget {
  const FindExperiencesButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.explore_outlined),
      label: const Text('新しい旅を探す'),
    ),
  );
}
