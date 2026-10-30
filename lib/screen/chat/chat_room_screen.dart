import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/chat.dart';
import '../../state/account_state.dart';
import '../../state/chat_state.dart';
import '../../widgets/user_type_badge.dart';
import 'chat_widgets.dart';

class ChatRoomScreen extends HookConsumerWidget {
  final String roomId, peerUid;
  const ChatRoomScreen({
    super.key,
    required this.roomId,
    required this.peerUid,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final rooms = ref.watch(chatRoomsProvider);
    final people = ref.watch(chatAccountsProvider);
    final messages = ref.watch(chatMessagesProvider(roomId));
    final peer = people.value?.where((p) => p.uid == peerUid).firstOrNull;
    final input = useTextEditingController(keys: [account.identity.uid]);
    useListenable(input);
    final busy = useState(false);
    final sendError = useState<String?>(null);
    final colors = Theme.of(context).colorScheme;
    final allowed =
        account.registered &&
        (rooms.value?.any(
              (r) => r.id == roomId && r.members.contains(account.identity.uid),
            ) ??
            false);
    Future<void> send() async {
      if (busy.value || !allowed || input.text.trim().isEmpty) return;
      final uid = account.identity.uid;
      final text = input.text;
      busy.value = true;
      sendError.value = null;
      try {
        final repository = await ref.read(chatRepositoryProvider.future);
        if (ref.read(currentAccountProvider).identity.uid != uid) return;
        await repository.send(roomId, text);
        if (context.mounted &&
            ref.read(currentAccountProvider).identity.uid == uid) {
          input.clear();
        }
      } catch (_) {
        if (context.mounted) {
          sendError.value = '送信できませんでした。入力内容を保持しています。再度お試しください。';
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              peer?.displayName ?? 'チャット',
              style: const TextStyle(fontSize: 17),
            ),
            if (peer != null) UserTypeBadge(peer.userType),
          ],
        ),
      ),
      body: !account.registered
          ? const ChatNotice('ログインし直してチャットを開いてください。')
          : rooms.hasError
          ? const ChatNotice('会話を読み込めませんでした。')
          : rooms.isLoading
          ? const Center(child: CircularProgressIndicator())
          : !allowed
          ? const ChatNotice('この会話は開けません。チャット一覧に戻ってください。')
          : Column(
              children: [
                Expanded(
                  child: messages.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => ChatNotice(
                      'メッセージを読み込めませんでした。',
                      action: TextButton(
                        onPressed: () =>
                            ref.invalidate(chatMessagesProvider(roomId)),
                        child: const Text('再読み込み'),
                      ),
                    ),
                    data: (items) => items.isEmpty
                        ? const ChatNotice('旅の気になることを、話してみましょう。')
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(16),
                            itemCount:
                                items.length + (items.length == 100 ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == items.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    '直近100件のメッセージを表示しています。',
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              }
                              final message = items[index];
                              return _MessageBubble(
                                message: message,
                                mine: message.senderId == account.identity.uid,
                              );
                            },
                          ),
                  ),
                ),
                if (sendError.value != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        sendError.value!,
                        style: TextStyle(fontSize: 12, color: colors.error),
                      ),
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Container(
                    color: colors.surface,
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('chat-message-input'),
                            controller: input,
                            enabled: !busy.value,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'メッセージを入力',
                              counterText: '',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          tooltip: '送信',
                          onPressed: busy.value || input.text.trim().isEmpty
                              ? null
                              : send,
                          icon: busy.value
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MessageBubble extends HookConsumerWidget {
  final ChatMessage message;
  final bool mine;
  const _MessageBubble({required this.message, required this.mine});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final date = message.createdAt?.toLocal();
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width.clamp(0, 480) * .78,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: mine ? colors.primary : colors.surface,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.text,
              style: TextStyle(
                color: mine ? colors.onPrimary : colors.onSurface,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              date == null
                  ? '送信中'
                  : '${date.year}/${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 10,
                color: (mine ? colors.onPrimary : colors.onSurfaceVariant)
                    .withValues(alpha: .75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
