import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/material.dart';
import 'recommendation/recommendation_home.dart';
import 'itinerary/itinerary_home.dart';

class PreparingPage extends HookConsumerWidget {
  const PreparingPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('このページは現在作成中です。', style: TextStyle(fontSize: 20)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('このページでは、お店や施設の方と旅行者の皆様が直接チャットで会話できるようになる予定です！', textAlign: TextAlign.center),
                SizedBox(height: 8),
                Text('12月リリース予定！', textAlign: TextAlign.center),
              ],
            ),
          ),
        ],
      ),
    );
  }
}