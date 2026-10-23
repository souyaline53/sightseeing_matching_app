import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChatHome extends HookConsumerWidget {
  const ChatHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('チャット')),
      body: const Center(child: Text('旅について相談しよう')),
    );
  }
}
