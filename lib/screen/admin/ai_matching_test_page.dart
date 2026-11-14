import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:sightseeing_matching_app/service/ai_matching_service.dart';

class AiMatchingTestPage extends StatefulWidget {
  const AiMatchingTestPage({super.key});

  @override
  State<AiMatchingTestPage> createState() => _AiMatchingTestPageState();
}

class _AiMatchingTestPageState extends State<AiMatchingTestPage> {
  bool _loading = false;
  String _result = 'まだテストしていません';

  Future<void> _testAi() async {
    setState(() {
      _loading = true;
      _result = 'AIが観光地を選んでいます...';
    });

    try {
      final recommendations = await AiMatchingService().getRecommendations(
        interests: '自然、歴史、体験型観光',
        mood: 'ワクワクしたい、普段できない体験がしたい',
      );

      if (!mounted) return;

      setState(() {
        _result = recommendations.isEmpty
            ? '推薦結果がありませんでした'
            : recommendations
                  .asMap()
                  .entries
                  .map(
                    (entry) =>
                        '${entry.key + 1}位：${entry.value.spotId}\n'
                        '理由：${entry.value.reason}',
                  )
                  .join('\n\n');
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;

      setState(() {
        _result =
            'Functionsエラー\n'
            'コード：${e.code}\n'
            '内容：${e.message}';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _result = 'エラー：$e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AIマッチングテスト')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _testAi,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_loading ? 'AI実行中...' : 'AIマッチングを実行'),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(child: SelectableText(_result)),
            ),
          ],
        ),
      ),
    );
  }
}
