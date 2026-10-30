import '../model/chat.dart';

abstract interface class ChatRepository {
  Stream<List<ChatAccount>> watchAccounts();
  Stream<List<ChatRoom>> watchRooms(String uid);
  Stream<List<ChatMessage>> watchMessages(String roomId);
  Future<String> openRoom(String otherUid);
  Future<void> send(String roomId, String text);
}
