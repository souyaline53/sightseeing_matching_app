import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/post.dart';
import '../service/cloud/cloud_services.dart';
import 'posts_repository.dart';

class FirestorePostsRepository implements PostsRepository {
  final Future<CloudServices> Function() services;
  FirestorePostsRepository(this.services);
  @override
  Stream<PostsState> watch() {
    final subscriptions = <StreamSubscription>[];
    StreamSubscription? bookmarksSubscription, followsSubscription;
    var closed = false;
    var identityReady = false, bookmarksReady = false, followsReady = false;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? posts, likes, comments;
    Set<String> savedIds = {}, followingIds = {};
    String? uid;
    late StreamController<PostsState> controller;
    void emit() {
      if (closed ||
          !identityReady ||
          !bookmarksReady ||
          !followsReady ||
          posts == null ||
          likes == null ||
          comments == null) {
        return;
      }
      final commentsByPost = <String, List<PostComment>>{};
      for (final doc in comments!) {
        final data = doc.data();
        (commentsByPost[data['postId']] ??= []).add(
          PostComment(
            id: doc.id,
            userId: data['userId'],
            userName: data['userName'],
            text: data['text'],
            createdAt:
                (data['createdAt'] as Timestamp?)?.toDate() ??
                DateTime.now().toUtc(),
          ),
        );
      }
      for (final list in commentsByPost.values) {
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      }
      final counts = <String, int>{}, likedIds = <String>{};
      for (final doc in likes!) {
        final data = doc.data();
        final id = data['postId'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
        if (data['userId'] == uid) likedIds.add(id);
      }
      controller.add(
        PostsState(
          posts: [
            for (final doc in posts!)
              if (doc.data()['status'] == 'active')
                TravelPost.fromJson({
                  ...doc.data(),
                  'id': doc.id,
                  'createdAt':
                      ((doc.data()['createdAt'] as Timestamp?)?.toDate() ??
                              DateTime.now().toUtc())
                          .toIso8601String(),
                  'likeCount': counts[doc.id] ?? 0,
                  'comments': (commentsByPost[doc.id] ?? [])
                      .map((e) => e.toJson())
                      .toList(),
                }),
          ],
          likedIds: likedIds,
          savedIds: savedIds,
          followingIds: followingIds,
        ),
      );
    }

    void error(Object failure, StackTrace stack) {
      if (!closed) controller.addError(failure, stack);
    }

    Future<void> start() async {
      try {
        final cloud = await services();
        if (closed) return;
        subscriptions.add(
          cloud.firestore
              .collection('posts')
              .orderBy('createdAt', descending: true)
              .snapshots()
              .listen((value) {
                posts = value.docs;
                emit();
              }, onError: error),
        );
        subscriptions.add(
          cloud.firestore.collection('post_likes').snapshots().listen((value) {
            likes = value.docs;
            emit();
          }, onError: error),
        );
        subscriptions.add(
          cloud.firestore.collection('post_comments').snapshots().listen((
            value,
          ) {
            comments = value.docs;
            emit();
          }, onError: error),
        );
        subscriptions.add(
          cloud.auth.authStateChanges().listen((user) {
            final next = user?.uid;
            if (identityReady && next == uid) return;
            identityReady = true;
            uid = next;
            bookmarksReady = followsReady = next == null;
            unawaited(bookmarksSubscription?.cancel());
            unawaited(followsSubscription?.cancel());
            savedIds = {};
            followingIds = {};
            emit();
            if (next == null) return;
            final owner = cloud.firestore.collection('users').doc(next);
            bookmarksSubscription = owner
                .collection('post_bookmarks')
                .snapshots()
                .listen((value) {
                  if (uid != next) return;
                  bookmarksReady = true;
                  savedIds = value.docs.map((e) => e.id).toSet();
                  emit();
                }, onError: error);
            followsSubscription = owner
                .collection('post_follows')
                .snapshots()
                .listen((value) {
                  if (uid != next) return;
                  followsReady = true;
                  followingIds = value.docs.map((e) => e.id).toSet();
                  emit();
                }, onError: error);
          }, onError: error),
        );
      } catch (failure, stack) {
        error(failure, stack);
      }
    }

    controller = StreamController<PostsState>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        closed = true;
        await Future.wait([
          ...subscriptions.map((s) => s.cancel()),
          if (bookmarksSubscription != null) bookmarksSubscription!.cancel(),
          if (followsSubscription != null) followsSubscription!.cancel(),
        ]);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> create(TravelPost post) async {
    final cloud = await services();
    if (cloud.auth.currentUser?.uid != post.userId) {
      throw StateError('ログイン状態が変わりました。');
    }
    final data = post.toJson()
      ..remove('likeCount')
      ..remove('commentCount')
      ..remove('comments');
    await cloud.firestore.runTransaction((transaction) async {
      final doc = cloud.firestore.collection('posts').doc(post.id);
      if ((await transaction.get(doc)).exists) {
        throw StateError('同じ投稿IDが存在します。');
      }
      transaction.set(doc, {
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
      });
    });
  }

  Future<void> _toggle(
    DocumentReference<Map<String, dynamic>> doc,
    Map<String, dynamic> data,
    CloudServices cloud,
  ) => cloud.firestore.runTransaction((transaction) async {
    if ((await transaction.get(doc)).exists) {
      transaction.delete(doc);
    } else {
      transaction.set(doc, {
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  });
  @override
  Future<void> toggleLike(String postId) async {
    final cloud = await services();
    final uid = (await cloud.writer()).uid;
    await _toggle(
      cloud.firestore.collection('post_likes').doc('${postId}_$uid'),
      {'postId': postId, 'userId': uid},
      cloud,
    );
  }

  @override
  Future<void> toggleSaved(String postId) async {
    final cloud = await services();
    final uid = (await cloud.writer()).uid;
    await _toggle(
      cloud.firestore
          .collection('users')
          .doc(uid)
          .collection('post_bookmarks')
          .doc(postId),
      {'targetId': postId},
      cloud,
    );
  }

  @override
  Future<void> toggleFollow(String userId) async {
    final cloud = await services();
    final uid = (await cloud.writer()).uid;
    if (userId == uid) return;
    await _toggle(
      cloud.firestore
          .collection('users')
          .doc(uid)
          .collection('post_follows')
          .doc(userId),
      {'targetId': userId},
      cloud,
    );
  }

  @override
  Future<void> addComment(String postId, PostComment comment) async {
    final cloud = await services();
    if (cloud.auth.currentUser?.uid != comment.userId) {
      throw StateError('ログイン状態が変わりました。');
    }
    await cloud.firestore.collection('post_comments').doc(comment.id).set({
      ...comment.toJson(),
      'postId': postId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> delete(TravelPost post) async {
    final cloud = await services();
    if (cloud.auth.currentUser?.uid != post.userId) {
      throw StateError('自分の投稿だけ削除できます。');
    }
    final doc = cloud.firestore.collection('posts').doc(post.id);
    await cloud.firestore.runTransaction((transaction) async {
      final current = await transaction.get(doc);
      if (!current.exists) return;
      if (current.data()!['userId'] != cloud.auth.currentUser?.uid) {
        throw StateError('自分の投稿だけ削除できます。');
      }
      transaction.update(doc, {'status': 'deleting'});
    });
    try {
      for (final collection in ['post_comments', 'post_likes']) {
        while (true) {
          final related = await cloud.firestore
              .collection(collection)
              .where('postId', isEqualTo: post.id)
              .limit(100)
              .get();
          if (related.docs.isEmpty) break;
          final batch = cloud.firestore.batch();
          for (final item in related.docs) {
            batch.delete(item.reference);
          }
          await batch.commit();
        }
      }
      await doc.delete();
    } catch (_) {
      try {
        await doc.update({'status': 'active'});
      } catch (_) {
        /* 再接続後に再試行する。 */
      }
      rethrow;
    }
  }
}
