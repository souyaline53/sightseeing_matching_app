import 'package:hooks_riverpod/hooks_riverpod.dart';

enum AppTab { recommendation, itinerary, posts, chat, profile }

final appTabProvider = NotifierProvider<AppTabNotifier, AppTab>(
  AppTabNotifier.new,
);

class AppTabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.recommendation;

  void select(AppTab tab) {
    state = tab;
  }
}
