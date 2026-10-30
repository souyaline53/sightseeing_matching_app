import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/account_profile.dart';
import 'package:sightseeing_matching_app/state/account_state.dart';
import 'package:sightseeing_matching_app/screen/profile/account/account_form_screen.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot;

Future<void> revealAccount(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final scroll = find
      .descendant(
        of: find.byKey(const ValueKey('account-form')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(finder, 200, scrollable: scroll);
  await Scrollable.ensureVisible(tester.element(finder), alignment: .2);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, Key key, String value) async {
  final field = find.byKey(key);
  await revealAccount(tester, field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('account-email')),
    'tabi@example.com',
  );
  await revealAccount(tester, find.byKey(const ValueKey('account-password')));
  await tester.enterText(
    find.byKey(const ValueKey('account-password')),
    'abcdef',
  );
  await revealAccount(tester, find.byKey(const ValueKey('account-nickname')));
  await tester.enterText(
    find.byKey(const ValueKey('account-nickname')),
    'たびすけ',
  );
  await choose(tester, const ValueKey('account-age'), '30代');
  await choose(tester, const ValueKey('account-region'), '北海道');
  await choose(tester, const ValueKey('account-prefecture-北海道'), '北海道');
  await revealAccount(tester, find.byKey(const ValueKey('account-city')));
  await tester.enterText(find.byKey(const ValueKey('account-city')), '札幌市');
  await revealAccount(tester, find.byKey(const ValueKey('account-submit')));
}

void main() {
  initializeCatalogTests();
  testWidgets(
    'profile shows guest, registers attributes and returns to guest on logout',
    (tester) async {
      final repository = FakeAccountRepository();
      final container = await boot(tester, accountRepository: repository);
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      expect(find.text('ゲストさん'), findsOneWidget);
      await tester.tap(find.text('登録する'));
      await tester.pumpAndSettle();
      await fill(tester);
      await tester.tap(find.byKey(const ValueKey('account-submit')));
      await tester.pumpAndSettle();
      expect(find.text('たびすけ'), findsOneWidget);
      expect(find.text('tabi@example.com'), findsOneWidget);
      expect(find.text('30代 · 北海道 札幌市'), findsOneWidget);
      expect(
        container.read(currentAccountProvider).identity.uid,
        'firebase-uid-test',
      );
      final logout = find.text('ログアウト');
      await Scrollable.ensureVisible(tester.element(logout), alignment: .4);
      await tester.tap(logout);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'ログアウト'));
      await tester.pumpAndSettle();
      expect(find.text('ゲストさん'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed save keeps input; selecting another region clears the prefecture',
    (tester) async {
      final repository = FakeAccountRepository();
      await boot(tester, accountRepository: repository);
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登録する'));
      await tester.pumpAndSettle();
      await fill(tester);
      repository.failSave = true;
      await tester.tap(find.byKey(const ValueKey('account-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-form-error')), findsOneWidget);
      await choose(tester, const ValueKey('account-region'), '関東');
      expect(
        tester
            .state<FormFieldState<String>>(
              find.byKey(const ValueKey('account-prefecture-関東')),
            )
            .value,
        isNull,
      );
      await choose(tester, const ValueKey('account-prefecture-関東'), '東京都');
      repository.failSave = false;
      await revealAccount(tester, find.byKey(const ValueKey('account-submit')));
      await tester.tap(find.byKey(const ValueKey('account-submit')));
      await tester.pumpAndSettle();
      expect(repository.profiles.values.single.nickname, 'たびすけ');
      expect(repository.profiles.values.single.prefecture, '東京都');
      expect(repository.lastPassword, 'abcdef');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'incomplete registered profile offers recovery without another password registration',
    (tester) async {
      final repository = FakeAccountRepository(
        identity: const AccountIdentity(
          uid: 'existing-uid',
          email: 'already@example.com',
          registered: true,
          displayName: 'プロフィール未登録',
        ),
      );
      await boot(tester, accountRepository: repository);
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登録を完了する'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountFormScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('account-password')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'small Android registration screen remains scrollable',
    (tester) async {
      await boot(tester);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登録する'));
      await tester.pumpAndSettle();
      await fill(tester);
      expect(
        find.byKey(const ValueKey('account-submit')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );
}
