import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/account_state.dart';
import '../../state/chat_state.dart';
import '../../widgets/settings_actions.dart';
import 'chat_room_screen.dart';
import 'chat_widgets.dart';

class NewChatScreen extends HookConsumerWidget {
  const NewChatScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(chatAccountsProvider);
    final account = ref.watch(currentAccountProvider);
    final query = useTextEditingController();
    useListenable(query);
    final busy = useState(false);
    final candidates = (people.value ?? [])
        .where(
          (p) =>
              p.uid != account.identity.uid &&
              p.displayName.toLowerCase().contains(
                query.text.trim().toLowerCase(),
              ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('チャットを始める')),
      body: !account.registered
          ? const ChatNotice('ログインしてください。')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: TextField(
                    controller: query,
                    decoration: const InputDecoration(
                      hintText: '表示名で探す',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                if (busy.value) const LinearProgressIndicator(),
                Expanded(
                  child: people.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => ChatNotice(
                      '相手を読み込めませんでした。',
                      action: TextButton(
                        onPressed: () => ref.invalidate(chatAccountsProvider),
                        child: const Text('再読み込み'),
                      ),
                    ),
                    data: (_) => candidates.isEmpty
                        ? const ChatNotice('該当するユーザーはまだいません。')
                        : ListView.builder(
                            itemCount: candidates.length,
                            itemBuilder: (context, i) {
                              final peer = candidates[i];
                              return ChatAccountTile(
                                account: peer,
                                subtitle: 'メッセージを送る',
                                onTap: busy.value
                                    ? null
                                    : () async {
                                        busy.value = true;
                                        final currentUid = account.identity.uid;
                                        try {
                                          final repository = await ref.read(
                                            chatRepositoryProvider.future,
                                          );
                                          final id = await repository.openRoom(
                                            peer.uid,
                                          );
                                          if (!context.mounted ||
                                              ref
                                                      .read(
                                                        currentAccountProvider,
                                                      )
                                                      .identity
                                                      .uid !=
                                                  currentUid) {
                                            return;
                                          }
                                          await Navigator.pushReplacement<
                                            void,
                                            void
                                          >(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ChatRoomScreen(
                                                roomId: id,
                                                peerUid: peer.uid,
                                              ),
                                            ),
                                          );
                                        } catch (_) {
                                          if (context.mounted) {
                                            showMessage(
                                              context,
                                              '会話を開始できませんでした。通信とプロフィールの登録を確認してください。',
                                            );
                                          }
                                        } finally {
                                          if (context.mounted) {
                                            busy.value = false;
                                          }
                                        }
                                      },
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
