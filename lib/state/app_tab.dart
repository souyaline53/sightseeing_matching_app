import 'package:hooks_riverpod/hooks_riverpod.dart';

enum AppTab { home, swipe, bookmark, itinerary, profile }

final appTabProvider = NotifierProvider<AppTabNotifier, AppTab>(
  AppTabNotifier.new,
);

class AppTabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;

  void select(AppTab tab) {
    state = tab;
  }
}
