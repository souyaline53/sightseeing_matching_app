import 'dart:math';

const localPostUserId = 'local-user';
String newPostId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

enum PostMediaKind { image, video }

class PostMedia {
  final String id, source, mimeType;
  final PostMediaKind kind;
  const PostMedia({
    required this.id,
    required this.source,
    this.kind = PostMediaKind.image,
    this.mimeType = 'image/jpeg',
  });
  bool get isLocal => source.startsWith('local://');
  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'kind': kind.name,
    'mimeType': mimeType,
  };
  factory PostMedia.fromJson(Map<String, dynamic> json) => PostMedia(
    id: json['id'] as String,
    source: json['source'] as String,
    kind: PostMediaKind.values.byName(json['kind'] as String),
    mimeType: json['mimeType'] as String,
  );
}

class PostComment {
  final String id, userId, userName, text;
  final DateTime createdAt;
  PostComment({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required DateTime createdAt,
  }) : createdAt = createdAt.toUtc();
  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'userName': userName,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };
  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
    id: json['id'] as String,
    userId: json['userId'] as String,
    userName: json['userName'] as String,
    text: json['text'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class TravelPost {
  final String id, userId, userName, avatar, spotId, category, caption;
  final List<PostMedia> media;
  final List<PostComment> comments;
  final double rating;
  final int likeCount;
  final DateTime createdAt;
  TravelPost({
    required this.id,
    required this.userId,
    required this.userName,
    this.avatar = '',
    required this.spotId,
    required this.category,
    required this.caption,
    required List<PostMedia> media,
    required this.rating,
    required DateTime createdAt,
    this.likeCount = 0,
    List<PostComment> comments = const [],
  }) : media = List.unmodifiable(media),
       comments = List.unmodifiable(comments),
       createdAt = createdAt.toUtc();
  int get commentCount => comments.length;
  TravelPost copyWith({int? likeCount, List<PostComment>? comments}) =>
      TravelPost(
        id: id,
        userId: userId,
        userName: userName,
        avatar: avatar,
        spotId: spotId,
        category: category,
        caption: caption,
        media: media,
        rating: rating,
        createdAt: createdAt,
        likeCount: likeCount ?? this.likeCount,
        comments: comments ?? this.comments,
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'userName': userName,
    'avatar': avatar,
    'spotId': spotId,
    'category': category,
    'caption': caption,
    'media': media.map((e) => e.toJson()).toList(),
    'rating': rating,
    'createdAt': createdAt.toIso8601String(),
    'likeCount': likeCount,
    'commentCount': commentCount,
    'comments': comments.map((e) => e.toJson()).toList(),
  };
  factory TravelPost.fromJson(Map<String, dynamic> json) => TravelPost(
    id: json['id'] as String,
    userId: json['userId'] as String,
    userName: json['userName'] as String,
    avatar: json['avatar'] as String? ?? '',
    spotId: json['spotId'] as String,
    category: json['category'] as String,
    caption: json['caption'] as String,
    media: (json['media'] as List)
        .map((e) => PostMedia.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    rating: (json['rating'] as num).toDouble(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    likeCount: json['likeCount'] as int,
    comments: (json['comments'] as List)
        .map((e) => PostComment.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

class PostsState {
  final List<TravelPost> posts;
  final Set<String> followingIds, likedIds, savedIds;
  PostsState({
    List<TravelPost> posts = const [],
    Set<String> followingIds = const {},
    Set<String> likedIds = const {},
    Set<String> savedIds = const {},
  }) : posts = List.unmodifiable(posts),
       followingIds = Set.unmodifiable(followingIds),
       likedIds = Set.unmodifiable(likedIds),
       savedIds = Set.unmodifiable(savedIds);
  PostsState copyWith({
    List<TravelPost>? posts,
    Set<String>? followingIds,
    Set<String>? likedIds,
    Set<String>? savedIds,
  }) => PostsState(
    posts: posts ?? this.posts,
    followingIds: followingIds ?? this.followingIds,
    likedIds: likedIds ?? this.likedIds,
    savedIds: savedIds ?? this.savedIds,
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'posts': posts.map((e) => e.toJson()).toList(),
    'followingIds': followingIds.toList(),
    'likedIds': likedIds.toList(),
    'savedIds': savedIds.toList(),
  };
  factory PostsState.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported posts version');
    }
    final posts = (json['posts'] as List)
        .map((e) => TravelPost.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (posts.map((e) => e.id).toSet().length != posts.length) {
      throw const FormatException('Duplicate post ids');
    }
    return PostsState(
      posts: posts,
      followingIds: (json['followingIds'] as List).cast<String>().toSet(),
      likedIds: (json['likedIds'] as List).cast<String>().toSet(),
      savedIds: (json['savedIds'] as List).cast<String>().toSet(),
    );
  }
}
