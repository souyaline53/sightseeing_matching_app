import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/posts_state.dart';
import '../../widgets/settings_actions.dart';

Future<void> showPostComments(BuildContext context, String postId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (_) => _CommentsSheet(postId: postId),
    );

class _CommentsSheet extends HookConsumerWidget {
  final String postId;
  const _CommentsSheet({required this.postId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref
        .watch(postsProvider)
        .value
        ?.posts
        .where((p) => p.id == postId)
        .firstOrNull;
    final text = useTextEditingController();
    final scroll = useScrollController();
    final busy = useState(false);
    Future<void> send() async {
      if (busy.value || text.text.trim().isEmpty) return;
      busy.value = true;
      try {
        await ref.read(postsProvider.notifier).comment(postId, text.text);
        text.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) {
            scroll.animateTo(
              scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      } catch (_) {
        if (context.mounted) {
          showMessage(context, 'コメントを保存できませんでした。もう一度お試しください。');
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'コメント（${post?.commentCount ?? 0}件）',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'コメントを閉じる',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: post == null || post.comments.isEmpty
                  ? const Center(child: Text('最初のコメントを残してみましょう。'))
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: post.comments.length,
                      itemBuilder: (_, index) {
                        final comment = post.comments[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 16,
                                child: Text(
                                  comment.userName.characters.first,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      comment.userName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      comment.text,
                                      style: const TextStyle(height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('post-comment-input'),
                        controller: text,
                        maxLength: 500,
                        minLines: 1,
                        maxLines: 3,
                        enabled: !busy.value && post != null,
                        decoration: const InputDecoration(
                          hintText: 'コメントを書く',
                          counterText: '',
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => send(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'コメントを送信',
                      onPressed: busy.value || post == null ? null : send,
                      icon: const Icon(Icons.send_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
