import 'package:cloud_firestore/cloud_firestore.dart';
import '../../model/account_profile.dart';

/// 既存アカウントの公開情報を、本人だけが読めるプロフィールから同期する。
Future<void> syncPublicChatProfile(FirebaseFirestore firestore, String uid) =>
    firestore.runTransaction((transaction) async {
      final reference = firestore.collection('users').doc(uid);
      final publicReference = firestore.collection('public_profiles').doc(uid);
      final existing = await transaction.get(reference);
      if (!existing.exists) return;
      final visible = await transaction.get(publicReference);
      final data = existing.data()!;
      final type = UserType.fromValue(data['userType']);
      if (!data.containsKey('userType')) {
        transaction.update(reference, {
          'userType': type.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (visible.data()?['displayName'] == data['nickname'] &&
          visible.data()?['userType'] == type.name) {
        return;
      }
      transaction.set(publicReference, {
        'uid': uid,
        'displayName': data['nickname'],
        'userType': type.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
