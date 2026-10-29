import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/mock_data.dart';
import '../../model/experience.dart';
import '../../model/post.dart';
import '../../service/post_media_picker.dart';
import '../../state/posts_state.dart';
import '../../widgets/settings_actions.dart';
import 'widgets/post_media_view.dart';

class PostCreateScreen extends HookConsumerWidget {
  const PostCreateScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(mockCatalogProvider).requireValue.experiences;
    final caption = useTextEditingController();
    final query = useState('');
    final selected = useState<Experience?>(null);
    final media = useState<List<PostMedia>>([]);
    final bytes = useState<Map<String, Uint8List>>({});
    final rating = useState(0);
    final category = useState<String?>(null);
    final busy = useState(false);
    final colors = Theme.of(context).colorScheme;
    final candidates = catalog
        .where(
          (spot) => '${spot.area} ${spot.title} ${spot.category}'
              .toLowerCase()
              .contains(query.value.trim().toLowerCase()),
        )
        .take(8)
        .toList();
    Future<void> pick(PostMediaSource source) async {
      if (busy.value) return;
      busy.value = true;
      ref.read(playingPostVideoProvider.notifier).select(null);
      try {
        final picked = await ref
            .read(postMediaPickerProvider)
            .pick(source, remaining: 6 - media.value.length);
        if (!context.mounted) return;
        final nextBytes = {
          ...bytes.value,
          for (final item in picked) item.media.id: item.bytes,
        };
        if (nextBytes.values.fold<int>(0, (n, b) => n + b.length) >
            40 * 1024 * 1024) {
          throw StateError('メディアは合計40MBまでです。');
        }
        media.value = [...media.value, ...picked.map((item) => item.media)];
        bytes.value = nextBytes;
      } catch (error) {
        if (context.mounted) {
          showMessage(
            context,
            error is StateError
                ? error.message.toString()
                : '写真・動画を選択できませんでした。権限やファイル形式を確認してください。',
          );
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> publish() async {
      if (busy.value) return;
      if (selected.value == null) {
        showMessage(context, '訪れた場所を選択してください。');
        return;
      }
      busy.value = true;
      try {
        ref.read(playingPostVideoProvider.notifier).select(null);
        await ref
            .read(postsProvider.notifier)
            .publish(
              spotId: selected.value!.id,
              caption: caption.text,
              category: category.value ?? '',
              rating: rating.value.toDouble(),
              media: media.value,
              bytes: bytes.value,
            );
        if (context.mounted) Navigator.pop(context, true);
      } catch (error) {
        if (context.mounted) {
          showMessage(
            context,
            error is StateError
                ? error.message.toString()
                : '投稿を保存できませんでした。入力内容は残っています。',
          );
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    void samplePhoto() {
      if (selected.value == null ||
          selected.value!.photo.isEmpty ||
          busy.value ||
          media.value.length >= 6) {
        return;
      }
      final id = newPostId('sample-photo');
      media.value = [
        ...media.value,
        PostMedia(id: id, source: selected.value!.photo),
      ];
    }

    return PopScope(
      canPop: !busy.value,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('旅の発見を投稿'),
          actions: [
            TextButton(
              key: const ValueKey('publish-post'),
              onPressed: busy.value ? null : publish,
              child: Text(
                busy.value ? '保存中…' : '投稿する',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        body: ListView(
          key: const ValueKey('post-create-form'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'この端末に保存されます。ほかのユーザーには公開されません。',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '訪れた場所',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (selected.value == null) ...[
              TextField(
                key: const ValueKey('post-spot-search'),
                enabled: !busy.value,
                decoration: const InputDecoration(
                  hintText: '地域・スポット・体験を検索',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => query.value = value,
              ),
              const SizedBox(height: 8),
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('一致するスポットがありません。'),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (_, index) {
                      final spot = candidates[index];
                      return ListTile(
                        key: ValueKey('post-spot-option-${spot.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: const Icon(Icons.place_outlined),
                        title: Text(
                          spot.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(spot.area),
                        onTap: busy.value
                            ? null
                            : () {
                                selected.value = spot;
                                FocusScope.of(context).unfocus();
                              },
                      );
                    },
                  ),
                ),
            ] else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.check_circle, color: colors.primary),
                title: Text(selected.value!.title),
                subtitle: Text(selected.value!.area),
                trailing: IconButton(
                  tooltip: 'スポットを選び直す',
                  onPressed: busy.value ? null : () => selected.value = null,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              '写真・動画（${media.value.length}/6）',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('pick-post-media'),
                  onPressed: busy.value || media.value.length >= 6
                      ? null
                      : () => pick(PostMediaSource.library),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('ライブラリから'),
                ),
                PopupMenuButton<PostMediaSource>(
                  enabled: !busy.value && media.value.length < 6,
                  tooltip: '写真・動画を撮影',
                  onSelected: pick,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: PostMediaSource.cameraPhoto,
                      child: Text('写真を撮影'),
                    ),
                    PopupMenuItem(
                      value: PostMediaSource.cameraVideo,
                      child: Text('動画を撮影（30秒まで）'),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt_outlined),
                        SizedBox(width: 6),
                        Text('撮影'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            TextButton.icon(
              key: const ValueKey('use-sample-post-photo'),
              onPressed:
                  selected.value == null ||
                      busy.value ||
                      media.value.length >= 6
                  ? null
                  : samplePhoto,
              icon: const Icon(Icons.landscape_outlined),
              label: const Text('選んだスポットのサンプル写真を使う'),
            ),
            const Text(
              '写真・動画は6件、1件20MB・合計40MBまで。動画は30秒以内。撮影は対応端末で利用できます。',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5),
            ),
            if (media.value.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: media.value.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 10),
                  itemBuilder: (_, index) {
                    final item = media.value[index];
                    return SizedBox(
                      width: 125,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PostMediaView(
                              media: item,
                              previewBytes: bytes.value[item.id],
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton.filledTonal(
                                tooltip: 'メディアを削除',
                                onPressed: busy.value
                                    ? null
                                    : () {
                                        media.value = media.value
                                            .where((m) => m.id != item.id)
                                            .toList();
                                        bytes.value = {...bytes.value}
                                          ..remove(item.id);
                                      },
                                icon: const Icon(Icons.close, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              '満足度',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    key: ValueKey('post-rating-$i'),
                    tooltip: '$iつ星',
                    onPressed: busy.value ? null : () => rating.value = i,
                    icon: Icon(
                      i <= rating.value
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: colors.primary,
                      size: 29,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'カテゴリ',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final value in [
                  'グルメ',
                  '絶景',
                  '宿・温泉',
                  '自然',
                  '歴史・文化',
                  'ものづくり',
                  '街歩き',
                ])
                  ChoiceChip(
                    label: Text(value),
                    selected: category.value == value,
                    onSelected: busy.value
                        ? null
                        : (_) => category.value = value,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('post-caption-input'),
              controller: caption,
              enabled: !busy.value,
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: '旅で見つけたこと',
                alignLabelWithHint: true,
                hintText: 'どんな発見がありましたか？\n#北海道 #週末の寄り道',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
