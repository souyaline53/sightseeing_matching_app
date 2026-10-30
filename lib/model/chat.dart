import 'account_profile.dart';

class ChatAccount {
  final String uid, displayName;
  final UserType userType;
  const ChatAccount({
    required this.uid,
    required this.displayName,
    this.userType = UserType.general,
  });
  factory ChatAccount.fromMap(String uid, Map<String, dynamic> data) =>
      ChatAccount(
        uid: uid,
        displayName: data['displayName'] as String? ?? '旅行者',
        userType: UserType.fromValue(data['userType']),
      );
}

class ChatRoom {
  final String id, lastMessage, lastSenderId;
  final List<String> members;
  final DateTime? updatedAt;
  const ChatRoom({
    required this.id,
    required this.members,
    this.lastMessage = '',
    this.lastSenderId = '',
    this.updatedAt,
  });
  String otherUid(String uid) => members.firstWhere((id) => id != uid);
}

class ChatMessage {
  final String id, senderId, text;
  final DateTime? createdAt;
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.createdAt,
  });
}
