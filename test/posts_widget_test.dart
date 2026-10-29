import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/post.dart';
import 'package:sightseeing_matching_app/service/post_media_picker.dart';
import 'package:sightseeing_matching_app/state/posts_state.dart';
import 'package:sightseeing_matching_app/screen/posts/widgets/post_card.dart';
import 'package:sightseeing_matching_app/screen/recommendation/experience_detail.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot;

Future<void> openPosts(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text('投稿')),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .25);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> revealForm(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final scrollable = find
      .descendant(
        of: find.byKey(const ValueKey('post-create-form')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(finder, 180, scrollable: scrollable);
  await Scrollable.ensureVisible(tester.element(finder), alignment: .2);
  await tester.pumpAndSettle();
}

Future<void> fillPost(WidgetTester tester, {bool sample = true}) async {
  await tester.tap(find.byTooltip('投稿を作成'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('post-spot-option-melon')));
  await tester.pumpAndSettle();
  final mediaButton = find.byKey(
    ValueKey(sample ? 'use-sample-post-photo' : 'pick-post-media'),
  );
  await revealForm(tester, mediaButton);
  await tester.tap(mediaButton);
  await tester.pumpAndSettle();
  final star = find.byKey(const ValueKey('post-rating-5'));
  await revealForm(tester, star);
  await tester.tap(star);
  final category = find.widgetWithText(ChoiceChip, 'グルメ');
  await revealForm(tester, category);
  await tester.tap(category);
  final caption = find.byKey(const ValueKey('post-caption-input'));
  await revealForm(tester, caption);
  await tester.enterText(caption, '見つけた、小さな幸せ。 #夕張 #週末旅');
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

class FakeMediaPicker implements PostMediaPicker {
  PostMediaSource? lastSource;
  @override
  Future<List<PickedPostMedia>> pick(
    PostMediaSource source, {
    required int remaining,
  }) async {
    lastSource = source;
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    return [
      PickedPostMedia(
        const PostMedia(
          id: 'picked-image',
          source: 'local://picked-image',
          mimeType: 'image/png',
        ),
        bytes,
      ),
    ];
  }
}

void main() {
  initializeMockCatalogTests();
  testWidgets(
    'posts tab, reactions, comments, bookmarks and following are interactive',
    (tester) async {
      final repository = MemoryPostsRepository();
      final container = await boot(tester, postsRepository: repository);
      await openPosts(tester);
      expect(find.text('おすすめ'), findsOneWidget);
      expect(find.text('フォロー中'), findsOneWidget);
      final original = container.read(postsProvider).requireValue.posts.first;
      final card = find.byKey(ValueKey('post-card-${original.id}'));
      final like = find.byKey(ValueKey('post-like-${original.id}'));
      await tapVisible(tester, like);
      expect(
        container.read(postsProvider).requireValue.likedIds,
        contains(original.id),
      );
      expect(
        container.read(postsProvider).requireValue.posts.first.likeCount,
        original.likeCount + 1,
      );
      await tapVisible(
        tester,
        find.byKey(ValueKey('post-save-${original.id}')),
      );
      expect(
        container.read(postsProvider).requireValue.savedIds,
        contains(original.id),
      );
      final comments = find.descendant(
        of: card,
        matching: find.byTooltip('コメント'),
      );
      await tapVisible(tester, comments);
      await tester.enterText(
        find.byKey(const ValueKey('post-comment-input')),
        '次のお休みに行きたい！',
      );
      await tester.tap(find.byTooltip('コメントを送信'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(postsProvider)
            .requireValue
            .posts
            .first
            .comments
            .last
            .text,
        '次のお休みに行きたい！',
      );
      await tester.tap(find.byTooltip('コメントを閉じる'));
      await tester.pumpAndSettle();
      final menu = find.descendant(
        of: card,
        matching: find.byTooltip('投稿のメニュー'),
      );
      await tapVisible(tester, menu);
      await tester.tap(find.text('フォローを解除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('フォロー中'));
      await tester.pumpAndSettle();
      expect(find.text('フォロー中の投稿はまだありません'), findsOneWidget);
      await tester.tap(find.byTooltip('保存した投稿'));
      await tester.pumpAndSettle();
      expect(find.byType(PostCard), findsOneWidget);
      expect(repository.value!.savedIds, contains(original.id));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'create post appears immediately and spot details include its review',
    (tester) async {
      final repository = MemoryPostsRepository();
      final container = await boot(tester, postsRepository: repository);
      await openPosts(tester);
      await fillPost(tester);
      await tester.tap(find.byKey(const ValueKey('publish-post')));
      await tester.pumpAndSettle();
      final post = container.read(postsProvider).requireValue.posts.first;
      expect(post.userId, localPostUserId);
      expect(post.rating, 5);
      expect(post.spotId, 'melon');
      expect(post.caption, contains('#夕張'));
      expect(find.byKey(ValueKey('post-card-${post.id}')), findsOneWidget);
      await tapVisible(tester, find.byKey(ValueKey('post-spot-${post.id}')));
      expect(find.byType(ExperienceDetail), findsOneWidget);
      final review = find.byKey(const ValueKey('spot-reviews-melon'));
      await Scrollable.ensureVisible(tester.element(review), alignment: .1);
      await tester.pumpAndSettle();
      expect(find.text('みんなのレビュー（2件）'), findsOneWidget);
      expect(repository.value!.posts.first.id, post.id);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'library media persists and a failed publish retains the form for retry',
    (tester) async {
      final repository = MemoryPostsRepository();
      final picker = FakeMediaPicker();
      final container = await boot(
        tester,
        postsRepository: repository,
        mediaPicker: picker,
      );
      await openPosts(tester);
      await fillPost(tester, sample: false);
      expect(picker.lastSource, PostMediaSource.library);
      repository.failWrite = true;
      await tester.tap(find.byKey(const ValueKey('publish-post')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post-caption-input')), findsOneWidget);
      expect(
        container
            .read(postsProvider)
            .requireValue
            .posts
            .where((p) => p.userId == localPostUserId),
        isEmpty,
      );
      repository.failWrite = false;
      await tester.tap(find.byKey(const ValueKey('publish-post')));
      await tester.pumpAndSettle();
      final own = container.read(postsProvider).requireValue.posts.first;
      expect(own.media.single.isLocal, isTrue);
      expect(repository.media['picked-image'], isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'small Android feed and compose layout remains usable',
    (tester) async {
      await boot(tester);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      await openPosts(tester);
      expect(find.byTooltip('投稿を作成').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('投稿を作成'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('publish-post')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );
}
