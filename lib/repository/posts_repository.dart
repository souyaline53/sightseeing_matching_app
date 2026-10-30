import '../model/post.dart';

abstract interface class PostsRepository {
  Stream<PostsState> watch();
  Future<void> create(TravelPost post);
  Future<void> toggleLike(String postId);
  Future<void> toggleSaved(String postId);
  Future<void> toggleFollow(String userId);
  Future<void> addComment(String postId, PostComment comment);
  Future<void> delete(TravelPost post);
}
