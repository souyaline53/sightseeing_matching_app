import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfileHome extends HookConsumerWidget {
  const ProfileHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール')),
      body: const Center(child: Text('Hello, World!')),
    );
  }
}
