import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/main.dart';
import 'package:sightseeing_matching_app/provider/app_tab_provider.dart';

void main() {
  testWidgets('Tabs and Riverpod selection stay in sync', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyApp)),
    );

    expect(find.text('Hello, World!'), findsOneWidget);
    expect(container.read(appTabProvider), AppTab.recommendation);

    final destinations = [
      (Icons.map_outlined, AppTab.itinerary, 'Hello, World!'),
      (Icons.chat_bubble_outline, AppTab.chat, 'Hello, World!'),
      (Icons.person_outline, AppTab.profile, 'Hello, World!'),
    ];

    for (final (icon, tab, message) in destinations) {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(container.read(appTabProvider), tab);
    }

    container.read(appTabProvider.notifier).select(AppTab.recommendation);
    await tester.pumpAndSettle();

    expect(find.text('新しい体験を見つけよう'), findsOneWidget);
    expect(find.byIcon(Icons.explore), findsOneWidget);

    // Hooksで生成したコントローラーの破棄時にも例外が出ないことを確認する。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
