import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/interest_answers.dart';
import '../model/search_settings.dart';
import 'curiosity_questions.dart';
import 'cloud/cloud_services.dart';

class AiRecommendation {
  final String spotId, reason;
  const AiRecommendation({required this.spotId, required this.reason});
  factory AiRecommendation.fromJson(Map<String, dynamic> json) {
    if (json['spot_id'] is! String ||
        (json['spot_id'] as String).isEmpty ||
        json['reason'] is! String) {
      throw const FormatException('推薦データの形式が正しくありません。');
    }
    return AiRecommendation(
      spotId: json['spot_id'] as String,
      reason: json['reason'] as String,
    );
  }
}

final aiMatchingServiceProvider = Provider<AiMatchingService>(
  (ref) => AiMatchingService(
    invoke: (data) async {
      await ref.read(cloudServicesProvider.future);
      return AiMatchingService.callFirebase(data);
    },
  ),
);

class AiMatchingService {
  final Future<dynamic> Function(Map<String, dynamic>) _invoke;
  AiMatchingService({Future<dynamic> Function(Map<String, dynamic>)? invoke})
    : _invoke = invoke ?? callFirebase;
  static Future<dynamic> callFirebase(Map<String, dynamic> data) async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) await auth.signInAnonymously();
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    const emulator = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
    if (emulator.isNotEmpty) {
      functions.useFunctionsEmulator(
        emulator,
        const int.fromEnvironment(
          'FIREBASE_FUNCTIONS_EMULATOR_PORT',
          defaultValue: 5001,
        ),
      );
    }
    final result = await functions
        .httpsCallable(
          'getAiRecommendations',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
        )
        .call(data);
    return result.data;
  }

  Future<List<AiRecommendation>> getRecommendations({
    required String interests,
    required String mood,
    Map<String, dynamic>? travelContext,
  }) async {
    final data = await _invoke({
      'interests': interests,
      'mood': mood,
      'travelContext': ?travelContext,
    });
    if (data is! Map || data['recommendations'] is! List) {
      throw const FormatException('推薦データの形式が正しくありません。');
    }
    final result = <AiRecommendation>[];
    final used = <String>{};
    for (final item in data['recommendations'] as List) {
      if (item is! Map) throw const FormatException('推薦データの形式が正しくありません。');
      final recommendation = AiRecommendation.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (used.add(recommendation.spotId)) result.add(recommendation);
      if (result.length == 10) break;
    }
    return List.unmodifiable(result);
  }
}

/// Sends answer labels, never locally derived recommendation scores or genre weights.
Map<String, String> aiQuestionInput(InterestAnswers answers) {
  final mood = CuriosityQuestions.moodFor(answers.moodId);
  final reason = CuriosityQuestions.reasonOption(
    answers.moodId,
    answers.reasonId,
  );
  final quest = CuriosityQuestions.questsFor(
    answers.moodId,
    answers.reasonId,
  ).options.where((q) => q.id == answers.questId).firstOrNull;
  return {
    'interests':
        [reason?.title, quest?.title].whereType<String>().join('、').isEmpty
        ? '未設定'
        : [reason?.title, quest?.title].whereType<String>().join('、'),
    'mood': mood?.label ?? '未設定',
  };
}

Map<String, dynamic> aiTravelContext(
  SearchConditions filters,
  Iterable<String> savedSpotIds, {
  DateTime? now,
}) {
  final japanNow = (now ?? DateTime.now()).toUtc().add(
    const Duration(hours: 9),
  );
  final date = filters.resolveDate(
    DateTime(japanNow.year, japanNow.month, japanNow.day),
  );
  return {
    'origin': filters.origin,
    'transport': filters.transport.name,
    'tripLength': filters.length.name,
    'visitDate':
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    'timeZone': 'Asia/Tokyo',
    'company': filters.company.name,
    'walking': filters.walking.name,
    'budgetYen': filters.budget,
    'maxTravelMinutes': filters.maxMinutes,
    'savedSpotIds': savedSpotIds.toSet().take(100).toList(),
  };
}

String aiMatchingError(Object error) {
  if (error is FirebaseFunctionsException) {
    return switch (error.code) {
      'resource-exhausted' => '検索回数の上限に達しました。少し待って再試行してください。',
      'deadline-exceeded' => 'AI検索がタイムアウトしました。再試行してください。',
      'unauthenticated' => '認証できませんでした。通信を確認して再試行してください。',
      _ => 'AI検索に接続できませんでした。再試行してください。',
    };
  }
  return '推薦結果を取得できませんでした。再試行してください。';
}
