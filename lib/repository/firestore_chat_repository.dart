import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import '../model/chat.dart';
import '../service/cloud/cloud_services.dart';
import '../service/cloud/public_profile_sync.dart';
import 'chat_repository.dart';

String directChatId(String first, String second) {
  final members = [first, second]..sort();
  return sha256.convert(utf8.encode(jsonEncode(members))).toString();
}

class FirestoreChatRepository implements ChatRepository {
  final CloudServices cloud;
  FirestoreChatRepository(this.cloud);
  String _uid() {
    final user = cloud.auth.currentUser;
    if (user == null || user.isAnonymous) throw StateError('ログインしてください。');
    return user.uid;
  }

  @override
  Stream<List<ChatAccount>> watchAccounts() async* {
    await syncPublicChatProfile(cloud.firestore, _uid());
    yield* cloud.firestore
        .collection('public_profiles')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => ChatAccount.fromMap(doc.id, doc.data()))
                  .toList()
                ..sort((a, b) => a.displayName.compareTo(b.displayName)),
        );
  }

  @override
  Stream<List<ChatRoom>> watchRooms(String uid) => cloud.firestore
      .collection('chat_rooms')
      .where('members', arrayContains: uid)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map((doc) {
              final data = doc.data();
              return ChatRoom(
                id: doc.id,
                members: (data['members'] as List).cast<String>(),
                lastMessage: data['lastMessage'] as String? ?? '',
                lastSenderId: data['lastSenderId'] as String? ?? '',
                updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
              );
            }).toList()..sort(
              (a, b) => (b.updatedAt ?? DateTime(1970)).compareTo(
                a.updatedAt ?? DateTime(1970),
              ),
            ),
      );

  @override
  Stream<List<ChatMessage>> watchMessages(String roomId) => cloud.firestore
      .collection('chat_rooms')
      .doc(roomId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          return ChatMessage(
            id: doc.id,
            senderId: data['senderId'] as String,
            text: data['text'] as String,
            createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
          );
        }).toList(),
      );

  @override
  Future<String> openRoom(String otherUid) async {
    final uid = _uid();
    if (otherUid == uid) throw StateError('相手を選択してください。');
    final id = directChatId(uid, otherUid);
    final room = cloud.firestore.collection('chat_rooms').doc(id);
    await cloud.firestore.runTransaction((transaction) async {
      final existing = await transaction.get(room);
      if (existing.exists) return;
      transaction.set(room, {
        'members': [uid, otherUid]..sort(),
        'lastMessage': '',
        'lastSenderId': '',
        'lastMessageId': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return id;
  }

  @override
  Future<void> send(String roomId, String text) async {
    final uid = _uid();
    final value = text.trim();
    if (value.isEmpty || value.length > 2000) {
      throw StateError('メッセージは1〜2000文字で入力してください。');
    }
    final room = cloud.firestore.collection('chat_rooms').doc(roomId);
    final message = room.collection('messages').doc();
    final batch = cloud.firestore.batch();
    batch.set(message, {
      'senderId': uid,
      'text': value,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(room, {
      'lastMessage': value,
      'lastSenderId': uid,
      'lastMessageId': message.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
