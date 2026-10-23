import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ItineraryHome extends HookConsumerWidget {
  const ItineraryHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('旅程')),
      body: const Center(child: Text('自分だけの旅を組み立てよう')),
    );
  }
}
