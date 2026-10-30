import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/model/account_profile.dart';
import 'package:sightseeing_matching_app/model/chat.dart';
import 'package:sightseeing_matching_app/repository/chat_repository.dart';
import 'package:sightseeing_matching_app/repository/firestore_chat_repository.dart';
import 'package:sightseeing_matching_app/screen/admin/user_type_panel.dart';
import 'package:sightseeing_matching_app/screen/chat/chat_room_screen.dart';
import 'package:sightseeing_matching_app/service/cloud/municipality_admin_service.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot;

class MemoryChats implements ChatRepository {
  List<ChatAccount> accounts = [
    const ChatAccount(
      uid: 'town',
      displayName: '観光案内',
      userType: UserType.municipality,
    ),
    const ChatAccount(uid: 'traveler', displayName: '旅の仲間'),
  ];
  List<ChatRoom> rooms = [
    const ChatRoom(
      id: 'town-room',
      members: ['me', 'town'],
      lastMessage: '散策を楽しんでください',
      lastSenderId: 'town',
    ),
    const ChatRoom(id: 'traveler-room', members: ['me', 'traveler']),
  ];
  final messages = <String, List<ChatMessage>>{};
  final changes = StreamController<void>.broadcast(sync: true);
  bool failSend = false;
  @override
  Stream<List<ChatAccount>> watchAccounts() async* {
    yield accounts;
    yield* changes.stream.map((_) => accounts);
  }

  @override
  Stream<List<ChatRoom>> watchRooms(String uid) async* {
    List<ChatRoom> mine() =>
        rooms.where((r) => r.members.contains(uid)).toList();
    yield mine();
    yield* changes.stream.map((_) => mine());
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String roomId) async* {
    yield messages[roomId] ?? [];
    yield* changes.stream.map((_) => messages[roomId] ?? []);
  }

  @override
  Future<String> openRoom(String otherUid) async =>
      rooms.firstWhere((r) => r.members.contains(otherUid)).id;
  @override
  Future<void> send(String roomId, String text) async {
    if (failSend) throw StateError('offline');
    final message = ChatMessage(
      id: 'sent-${messages.length}',
      senderId: 'me',
      text: text.trim(),
      createdAt: DateTime(2026, 10, 30, 10),
    );
    messages[roomId] = [message, ...messages[roomId] ?? []];
    rooms = [
      for (final r in rooms)
        r.id == roomId
            ? ChatRoom(
                id: r.id,
                members: r.members,
                lastMessage: message.text,
                lastSenderId: 'me',
                updatedAt: message.createdAt,
              )
            : r,
    ];
    changes.add(null);
  }
}

FakeAccountRepository signedIn() =>
    FakeAccountRepository(
        identity: const AccountIdentity(
          uid: 'me',
          email: 'me@example.test',
          registered: true,
          displayName: '旅人',
        ),
      )
      ..profiles['me'] = const AccountDetails(
        nickname: '旅人',
        ageGroup: '30代',
        prefecture: '北海道',
        municipality: '札幌市',
      );

class FakeMunicipalityAdmin implements MunicipalityAdminService {
  String? email;
  @override
  Future<ChatAccount> promote(String email) async {
    this.email = email;
    return const ChatAccount(
      uid: 'town',
      displayName: '観光案内',
      userType: UserType.municipality,
    );
  }
}

Future<void> openChatTab(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('チャット'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  initializeCatalogTests();
  test(
    'legacy profiles default to general; direct room IDs are stable for both participants',
    () {
      final old = AccountDetails.fromMap({
        'nickname': '旅行者',
        'ageGroup': '30代',
        'prefecture': '北海道',
        'municipality': '札幌市',
      });
      expect(old.userType, UserType.general);
      expect(old.toMap()['userType'], 'general');
      expect(
        ChatAccount.fromMap('town', {
          'displayName': '観光案内',
          'userType': 'municipality',
        }).userType,
        UserType.municipality,
      );
      expect(directChatId('one', 'two'), directChatId('two', 'one'));
      expect(
        directChatId('one-two', 'three'),
        isNot(directChatId('one', 'two-three')),
      );
    },
  );

  testWidgets(
    'chat tab preserves existing tabs and shows a guest login entry without fake conversations',
    (tester) async {
      await boot(tester);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      await openChatTab(tester);
      expect(find.text('COMMUNITY'), findsOneWidget);
      expect(find.text('ログインする'), findsOneWidget);
      expect(find.text('観光案内'), findsNothing);
      await tester.tap(find.text('ログインする'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-email')), findsOneWidget);
    },
  );

  testWidgets(
    'room list, dynamic badges, message sending and retry preserve the draft',
    (tester) async {
      final chats = MemoryChats();
      addTearDown(chats.changes.close);
      await boot(tester, accountRepository: signedIn(), chatRepository: chats);
      await openChatTab(tester);
      expect(find.text('観光案内'), findsOneWidget);
      expect(find.text('自治体'), findsOneWidget);
      expect(find.text('旅行者'), findsOneWidget);
      expect(find.text('散策を楽しんでください'), findsOneWidget);
      chats.accounts = [
        chats.accounts.first,
        const ChatAccount(
          uid: 'traveler',
          displayName: '旅の仲間',
          userType: UserType.municipality,
        ),
      ];
      chats.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('自治体'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('chat-room-town-room')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      final input = find.byKey(const ValueKey('chat-message-input'));
      await tester.enterText(input, 'おすすめを教えてください');
      await tester.pump();
      await tester.tap(find.byTooltip('送信'));
      await tester.pumpAndSettle();
      expect(find.text('おすすめを教えてください'), findsOneWidget);
      expect(chats.messages['town-room']!.single.text, 'おすすめを教えてください');
      chats.failSend = true;
      await tester.enterText(input, '入力は保持する');
      await tester.pump();
      await tester.tap(find.byTooltip('送信'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, '入力は保持する');
      expect(chats.messages['town-room'], hasLength(1));
      chats.failSend = false;
      await tester.tap(find.byTooltip('送信'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(chats.messages['town-room'], hasLength(2));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('あなた：入力は保持する'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new conversation picker opens an existing room without duplicates',
    (tester) async {
      final chats = MemoryChats();
      addTearDown(chats.changes.close);
      await boot(tester, accountRepository: signedIn(), chatRepository: chats);
      await openChatTab(tester);
      await tester.tap(find.byTooltip('チャットを始める'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('旅の仲間'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(chats.rooms, hasLength(2));
    },
  );

  testWidgets(
    'chat composer fits a small screen with keyboard and clears the old session',
    (tester) async {
      final chats = MemoryChats();
      final account = signedIn();
      addTearDown(chats.changes.close);
      await boot(tester, accountRepository: account, chatRepository: chats);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      await openChatTab(tester);
      await tester.tap(find.byKey(const ValueKey('chat-room-town-room')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-message-input')),
        '旧セッションの下書き',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await account.signOut();
      await tester.pumpAndSettle();
      expect(find.text('旧セッションの下書き'), findsNothing);
      expect(find.byKey(const ValueKey('chat-message-input')), findsNothing);
    },
  );

  testWidgets('admin enters email and receives the promoted account badge', (
    tester,
  ) async {
    final admin = FakeMunicipalityAdmin();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [municipalityAdminServiceProvider.overrideWithValue(admin)],
        child: const MaterialApp(home: Scaffold(body: UserTypePanel())),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('municipality-email')),
      'town@example.test',
    );
    await tester.tap(find.text('自治体ユーザに変更する'));
    await tester.pumpAndSettle();
    expect(admin.email, 'town@example.test');
    expect(find.text('「観光案内」を自治体ユーザに変更しました。'), findsOneWidget);
  });
}
