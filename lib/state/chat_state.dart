import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/chat.dart';
import '../repository/chat_repository.dart';
import '../repository/firestore_chat_repository.dart';
import '../service/cloud/cloud_services.dart';
import 'account_state.dart';

final chatRepositoryProvider = FutureProvider<ChatRepository>(
  (ref) async =>
      FirestoreChatRepository(await ref.watch(cloudServicesProvider.future)),
);

final chatAccountsProvider = StreamProvider.autoDispose<List<ChatAccount>>((
  ref,
) async* {
  final uid = ref.watch(
    currentAccountProvider.select(
      (account) => account.registered ? account.identity.uid : null,
    ),
  );
  if (uid == null) {
    yield [];
    return;
  }
  final repository = await ref.watch(chatRepositoryProvider.future);
  yield* repository.watchAccounts();
});

final chatRoomsProvider = StreamProvider.autoDispose<List<ChatRoom>>((
  ref,
) async* {
  final uid = ref.watch(
    currentAccountProvider.select(
      (account) => account.registered ? account.identity.uid : null,
    ),
  );
  if (uid == null) {
    yield [];
    return;
  }
  final repository = await ref.watch(chatRepositoryProvider.future);
  yield* repository.watchRooms(uid);
});

// アカウント切り替え時は古い会話の購読を破棄する。
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, roomId) async* {
      final uid = ref.watch(
        currentAccountProvider.select(
          (account) => account.registered ? account.identity.uid : null,
        ),
      );
      if (uid == null) {
        yield [];
        return;
      }
      final allowed = ref.watch(
        chatRoomsProvider.select(
          (value) =>
              value.value?.any(
                (room) => room.id == roomId && room.members.contains(uid),
              ) ??
              false,
        ),
      );
      if (!allowed) {
        yield [];
        return;
      }
      final repository = await ref.watch(chatRepositoryProvider.future);
      yield* repository.watchMessages(roomId);
    });
