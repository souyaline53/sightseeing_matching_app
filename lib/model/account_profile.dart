import '../data/japan_regions.dart';

enum UserType {
  general('旅行者'),
  municipality('自治体');

  final String label;
  const UserType(this.label);
  static UserType fromValue(Object? value) =>
      value == 'municipality' ? municipality : general;
}

class AccountDetails {
  final String nickname, ageGroup, prefecture, municipality;
  final UserType userType;
  const AccountDetails({
    required this.nickname,
    required this.ageGroup,
    required this.prefecture,
    required this.municipality,
    this.userType = UserType.general,
  });
  String? validate() {
    if (nickname.trim().isEmpty || nickname.trim().length > 30) {
      return 'ニックネームを1〜30文字で入力してください。';
    }
    if (!ageGroups.contains(ageGroup)) return '年代を選択してください。';
    if (regionForPrefecture(prefecture) == null) return '都道府県を選択してください。';
    if (municipality.trim().isEmpty || municipality.trim().length > 80) {
      return '市町村を1〜80文字で入力してください。';
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'nickname': nickname.trim(),
    'ageGroup': ageGroup,
    'prefecture': prefecture,
    'municipality': municipality.trim(),
    'userType': userType.name,
  };
  factory AccountDetails.fromMap(Map<String, dynamic> data) => AccountDetails(
    nickname: data['nickname'] as String,
    ageGroup: data['ageGroup'] as String,
    prefecture: data['prefecture'] as String,
    municipality: data['municipality'] as String,
    userType: UserType.fromValue(data['userType']),
  );
}

class AccountIdentity {
  final String uid, displayName;
  final String? email;
  final bool registered, emailVerified;
  const AccountIdentity({
    required this.uid,
    this.displayName = 'ゲストさん',
    this.email,
    this.registered = false,
    this.emailVerified = false,
  });
}

class GuestIdentity {
  final String id;
  const GuestIdentity(this.id);
}

class CurrentAccount {
  final AccountIdentity identity;
  final AccountDetails? details;
  final bool loading, profileLoading;
  final Object? error;
  const CurrentAccount({
    required this.identity,
    this.details,
    this.loading = false,
    this.profileLoading = false,
    this.error,
  });
  bool get registered => identity.registered;
  UserType get userType => details?.userType ?? UserType.general;
  String get name =>
      registered ? details?.nickname ?? identity.displayName : 'ゲストさん';
  bool ownsPost(String userId) => userId == identity.uid;
}

class AccountFailure implements Exception {
  final String message;
  const AccountFailure(this.message);
  @override
  String toString() => message;
}
