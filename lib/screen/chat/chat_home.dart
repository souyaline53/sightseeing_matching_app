import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/chat.dart';
import '../../state/account_state.dart';
import '../../state/chat_state.dart';
import '../profile/account/account_form_screen.dart';
import 'chat_widgets.dart';
import 'chat_room_screen.dart';
import 'new_chat_screen.dart';

class ChatHome extends HookConsumerWidget {
  const ChatHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final rooms = ref.watch(chatRoomsProvider);
    final people = ref.watch(chatAccountsProvider);
    final opening = useState(false);
    Future<void> open(Widget page) async {
      if (opening.value) return;
      opening.value = true;
      try {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => page),
        );
      } finally {
        if (context.mounted) opening.value = false;
      }
    }

    final ready =
        account.registered &&
        account.details != null &&
        !account.profileLoading;
    return Scaffold(
      floatingActionButton: ready
          ? FloatingActionButton(
              heroTag: 'start-chat',
              tooltip: 'チャットを始める',
              onPressed: opening.value
                  ? null
                  : () => open(const NewChatScreen()),
              child: const Icon(Icons.chat_bubble_outline),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COMMUNITY',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'チャット',
                    style: TextStyle(fontSize: 29, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Expanded(
              child: account.loading || account.profileLoading
                  ? const Center(child: CircularProgressIndicator())
                  : !account.registered
                  ? ChatNotice(
                      '旅の発見を、誰かと話してみませんか。\nチャットはログインして利用できます。',
                      action: FilledButton(
                        onPressed: opening.value
                            ? null
                            : () => open(
                                const AccountFormScreen(
                                  mode: AccountFormMode.login,
                                ),
                              ),
                        child: const Text('ログインする'),
                      ),
                    )
                  : account.details == null
                  ? ChatNotice(
                      'プロフィールを登録するとチャットを始められます。',
                      action: FilledButton(
                        onPressed: opening.value
                            ? null
                            : () => open(
                                const AccountFormScreen(
                                  mode: AccountFormMode.edit,
                                ),
                              ),
                        child: const Text('プロフィールを登録する'),
                      ),
                    )
                  : rooms.hasError || people.hasError
                  ? ChatNotice(
                      'チャットを読み込めませんでした。\n通信とFirebaseの設定を確認してください。',
                      action: OutlinedButton(
                        onPressed: () {
                          ref.invalidate(chatRoomsProvider);
                          ref.invalidate(chatAccountsProvider);
                        },
                        child: const Text('再読み込み'),
                      ),
                    )
                  : rooms.isLoading || people.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : rooms.requireValue.isEmpty
                  ? const ChatNotice('まだ会話はありません。\n右下のボタンからチャットを始めましょう。')
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: rooms.requireValue.length,
                      itemBuilder: (context, index) {
                        final room = rooms.requireValue[index];
                        final peerUid = room.otherUid(account.identity.uid);
                        final peer =
                            people.requireValue
                                .where((p) => p.uid == peerUid)
                                .firstOrNull ??
                            ChatAccount(uid: peerUid, displayName: '旅行者');
                        return ChatAccountTile(
                          key: ValueKey('chat-room-${room.id}'),
                          account: peer,
                          subtitle: room.lastMessage.isEmpty
                              ? '会話を始めましょう'
                              : '${room.lastSenderId == account.identity.uid ? 'あなた：' : ''}${room.lastMessage}',
                          onTap: opening.value
                              ? null
                              : () => open(
                                  ChatRoomScreen(
                                    roomId: room.id,
                                    peerUid: peerUid,
                                  ),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
