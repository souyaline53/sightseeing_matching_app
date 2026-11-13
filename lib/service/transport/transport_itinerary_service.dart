import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/optimized_transport_itinerary.dart';
import '../../model/transport.dart';
import '../../model/transport_optimization.dart';
import '../cloud/cloud_services.dart';
import 'transport_admin_api.dart';

final transportItineraryServiceProvider = Provider<TransportItineraryService>(
  (ref) => TransportItineraryService(
    isAuthenticated: () async {
      final cloud = await ref.read(cloudServicesProvider.future);
      return cloud.auth.currentUser != null;
    },
    invoke: TransportItineraryService.callFirebase,
  ),
);

class TransportItineraryException implements Exception {
  final String code, message;
  final Json details;
  const TransportItineraryException(
    this.code,
    this.message, {
    this.details = const {},
  });
  @override
  String toString() => message;
}

/// Explicit calls only. Never signs in automatically, retries, or writes a trip.
class TransportItineraryService {
  static const callableName = 'optimizeTransportItinerary';
  static const timeout = Duration(seconds: 130);
  static const maxCharacters = 4000000;
  static const maxBytes = 4000000;
  final Future<bool> Function() isAuthenticated;
  final Future<dynamic> Function(Json data) invoke;
  const TransportItineraryService({
    required this.isAuthenticated,
    required this.invoke,
  });

  static Future<dynamic> callFirebase(Json data) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw const TransportItineraryException(
        'unauthenticated',
        'ログインしてから交通最適化を実行してください。',
      );
    }
    final result = await transportFunctions()
        .httpsCallable(
          callableName,
          options: HttpsCallableOptions(timeout: timeout),
        )
        .call<dynamic>(data);
    return result.data;
  }

  Future<TransportItineraryResponse> optimizeTrip({
    required String tripId,
    required String requestId,
    required Json input,
  }) async {
    try {
      if (!await isAuthenticated()) {
        throw const TransportItineraryException(
          'unauthenticated',
          'ログインしてからAIをご利用ください。',
        );
      }
      final response = await invoke({
        'tripId': tripId,
        'requestId': requestId,
        'input': input,
      }).timeout(timeout);
      if (response is! Map || response['success'] is! bool) {
        throw const FormatException();
      }
      if (response['success'] != true) {
        throw const TransportItineraryException(
          'workflow-failed',
          '条件に合う旅程を生成できませんでした。手動で編集できます。',
        );
      }
      return TransportItineraryResponse(
        itinerary: OptimizedTransportItinerary.fromJson(response['itinerary']),
        message: response['message'] as String,
        metadata: Map<String, dynamic>.from(response['aiMetadata'] as Map),
      );
    } on FirebaseFunctionsException catch (e) {
      throw _functionError(e);
    } on TimeoutException {
      throw const TransportItineraryException(
        'deadline-exceeded',
        '結果の確認が必要です。自動再試行は行いません。',
      );
    } on FormatException {
      throw const TransportItineraryException(
        'invalid-response',
        'AIの応答形式を確認できませんでした。',
      );
    }
  }

  Future<TransportItineraryResponse> optimizePrepared(
    PreparedTransportOptimization data,
  ) => optimize(data.transportJson);

  Future<TransportItineraryResponse> optimize(String transportData) async {
    try {
      if (!await isAuthenticated()) {
        throw const TransportItineraryException(
          'unauthenticated',
          'ログインしてから交通最適化を実行してください。',
        );
      }
      if (transportData.length > maxCharacters ||
          transportData.runes.length > maxCharacters ||
          utf8.encode(transportData).length > maxBytes) {
        throw const TransportItineraryException(
          'resource-exhausted',
          '交通データが送信上限（400万文字・4 MB）を超えています。AIは実行していません。出発から帰着までの時間を短くするか、手動作成をご利用ください。',
        );
      }
      dynamic network;
      try {
        network = jsonDecode(transportData);
      } on FormatException {
        throw const TransportItineraryException(
          'invalid-argument',
          '交通データのJSON形式が不正です。',
        );
      }
      if (network is! Map ||
          network['schemaVersion'] != 1 ||
          [
            'places',
            'stops',
            'routes',
            'agencies',
            'instances',
            'segments',
            'transfers',
          ].any((key) => network[key] is! List)) {
        throw const TransportItineraryException(
          'invalid-argument',
          'schemaVersion: 1の交通ネットワークを指定してください。',
        );
      }
      // Already a JSON string. Do not double-encode or send a UID/API key.
      final response = await invoke({
        'transport_data': transportData,
      }).timeout(timeout);
      if (response is! Map || response['success'] is! bool) {
        throw const FormatException('交通最適化の応答形式が不正です。');
      }
      if (response['success'] == false) {
        throw const TransportItineraryException(
          'workflow-failed',
          '交通最適化で旅程を生成できませんでした。',
        );
      }
      if (response['message'] is! String) {
        throw const FormatException('交通最適化の応答メッセージが不正です。');
      }
      return TransportItineraryResponse(
        itinerary: OptimizedTransportItinerary.fromJson(response['itinerary']),
        message: response['message'] as String,
      );
    } on TransportItineraryException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw _functionError(error);
    } on FirebaseAuthException {
      throw const TransportItineraryException(
        'unauthenticated',
        '認証状態を確認して、ログインし直してください。',
      );
    } on TimeoutException {
      throw const TransportItineraryException(
        'deadline-exceeded',
        '交通最適化がタイムアウトしました。自動再試行は行いません。',
      );
    } on FormatException {
      throw const TransportItineraryException(
        'invalid-response',
        '交通最適化結果を読み取れませんでした。',
      );
    } catch (_) {
      throw const TransportItineraryException(
        'unavailable',
        '交通最適化サービスに接続できませんでした。',
      );
    }
  }
}

String _message(String code) => switch (code) {
  'unauthenticated' => '認証状態を確認して、ログインし直してください。',
  'permission-denied' => '交通最適化を利用する権限またはアプリの認証を確認してください。',
  'deadline-exceeded' => '交通最適化がタイムアウトしました。自動再試行は行いません。',
  'resource-exhausted' => 'AI作成が一時的に制限されています。手動作成は引き続き使えます。',
  'already-exists' => 'AIの処理中または結果確認待ちです。保存済み結果を確認してください。',
  'invalid-argument' => '交通データの形式を確認してください。',
  'failed-precondition' => '交通最適化サービスの接続設定を確認してください。',
  'internal' => '交通最適化の処理または応答に問題が発生しました。',
  _ => '交通最適化サービスに接続できませんでした。',
};

TransportItineraryException _functionError(FirebaseFunctionsException error) {
  final raw = error.details;
  final details = raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};
  int? number(String key) {
    final value = details[key];
    return value is num && value.isFinite && value >= 0 && value < 100000000000
        ? value.toInt()
        : null;
  }

  String size(int bytes) => '${(bytes / 1000000).toStringAsFixed(2)} MB';
  String message = _message(error.code);
  if (details['reason'] == 'dify-http-error') {
    final status = number('httpStatus');
    message = status == 400 || status == 422
        ? 'AIサービスが入力を受け付けませんでした（HTTP $status）。入力形式の確認が必要です。再送せず、保存済み結果を確認してください。'
        : 'AIサービスからエラーが返りました${status == null ? '' : '（HTTP $status）'}。自動再試行は行いません。保存済み結果を確認してください。';
  }
  if (error.code == 'resource-exhausted') {
    switch (details['reason']) {
      case 'transport-payload-too-large':
        final bytes = number('bytes'), limitBytes = number('maxBytes');
        final characters = number('characters'),
            limitCharacters = number('maxCharacters');
        final measurements = [
          if (bytes != null && limitBytes != null)
            '${size(bytes)} / 上限${size(limitBytes)}',
          if (characters != null && limitCharacters != null)
            '$characters文字 / 上限$limitCharacters文字',
        ].join('、');
        message =
            '交通データが多すぎるため、AIを実行できませんでした。${measurements.isEmpty ? '' : '（$measurements）'}出発から帰着までの時間を短くするか、手動作成をご利用ください。AI利用済みにはなりません。';
      case 'transport-segment-limit':
      case 'transport-build-limit':
        message =
            '対象の交通区間が多すぎるため、AIを実行できませんでした。出発から帰着までの時間を短くするか、手動作成をご利用ください。AI利用済みにはなりません。';
      case 'ai-minute-limit':
        message =
            '短時間にAIを実行できる回数を超えました。約${number('retryAfterSeconds') ?? 60}秒待ってからお試しください。';
      case 'ai-daily-limit':
        final reset = details['resetAt'] is String
            ? DateTime.tryParse(details['resetAt'] as String)?.toLocal()
            : null;
        final available = reset == null
            ? '次の利用可能時刻までお待ちください。'
            : '${reset.month}/${reset.day} ${reset.hour.toString().padLeft(2, '0')}:${reset.minute.toString().padLeft(2, '0')}以降に再度ご利用いただけます。';
        message =
            '本日のAI作成回数（${number('limit') ?? 10}回）の上限に達しました。$available 手動作成・編集は引き続き使えます。';
      case 'dify-rate-limit':
        message = 'AIサービス側の利用制限に達しています。二重実行を防ぐため、保存済み結果を確認してください。手動編集は続けられます。';
    }
  }
  return TransportItineraryException(error.code, message, details: details);
}
