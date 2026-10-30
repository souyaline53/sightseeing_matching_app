import 'package:cloud_functions/cloud_functions.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/chat.dart';
import 'cloud_services.dart';

abstract interface class MunicipalityAdminService {
  Future<ChatAccount> promote(String email);
}

class FirebaseMunicipalityAdminService implements MunicipalityAdminService {
  final Ref ref;
  FirebaseMunicipalityAdminService(this.ref);
  @override
  Future<ChatAccount> promote(String email) async {
    final cloud = await ref.read(cloudServicesProvider.future);
    cloud.requireAdmin();
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    const host = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
    if (host.isNotEmpty) functions.useFunctionsEmulator(host, 5001);
    try {
      final response = await functions
          .httpsCallable('setMunicipalityUser')
          .call({'email': email.trim()});
      final data = Map<String, dynamic>.from(response.data as Map);
      return ChatAccount.fromMap(data['uid'] as String, data);
    } on FirebaseFunctionsException catch (error) {
      throw StateError(switch (error.code) {
        'not-found' =>
          error.details is Map &&
                  (error.details as Map)['reason'] == 'user-not-found'
              ? 'そのメールアドレスの登録済みユーザーが見つかりません。'
              : '管理者用Cloud Functionsが見つかりません。デプロイを確認してください。',
        'failed-precondition' => error.message ?? '対象ユーザーのプロフィール登録が完了していません。',
        'permission-denied' ||
        'unauthenticated' => 'メール確認済みの管理者アカウントでログインしてください。',
        'invalid-argument' => 'メールアドレスを確認してください。',
        _ => '変更できませんでした。Cloud Functionsの反映と通信を確認してください。',
      });
    }
  }
}

final municipalityAdminServiceProvider = Provider<MunicipalityAdminService>(
  (ref) => FirebaseMunicipalityAdminService(ref),
);
