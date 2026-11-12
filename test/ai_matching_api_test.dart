
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';


void checkAuth() {
  final user = FirebaseAuth.instance.currentUser;

  print('UID: ${user?.uid}');
  print('匿名認証: ${user?.isAnonymous}');
}


Future<void> testGetMatchingSpots() async {
  try {
    // 匿名認証の完了を確認
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      print('Firebase認証が完了していません');
      return;
    }

    // 東京リージョンのCloud Functionsを使用
    final functions = FirebaseFunctions.instanceFor(
      region: 'asia-northeast1',
    );

    final callable = functions.httpsCallable('getMatchingSpots');

    final result = await callable.call();

    final data = Map<String, dynamic>.from(result.data as Map);

    print('観光地取得成功！');
    print('取得件数: ${data['count']}');
    print('観光地データ: ${data['spots']}');
  } on FirebaseFunctionsException catch (e) {
    print('Functionsエラー: ${e.code} / ${e.message}');
  } catch (e) {
    print('エラー: $e');
  }
}

