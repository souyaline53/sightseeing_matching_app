import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/discovery_state.dart';
import 'home_overview.dart';
import '../shared/discovery/interest_search_flow.dart';

/// Home owns the landing page; the question/recommendation flow is shared.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(discoveryProvider.select((state) => state.step)) == 0
      ? const HomeOverview()
      : const InterestSearchFlow();
}
