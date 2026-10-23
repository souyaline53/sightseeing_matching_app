import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RecommendationHome extends HookConsumerWidget {
  const RecommendationHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('おすすめ')),
      body: const Center(child: Text('新しい体験を見つけよう')),
    );
  }
}
