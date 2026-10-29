import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/search_settings.dart';
import '../../state/app_tab.dart';
import '../../state/discovery_state.dart';
import '../../state/settings_state.dart';
import '../../state/trip_library_state.dart';
import '../../state/trip_state.dart';
import '../../widgets/travel_photo.dart';
import '../itinerary/itinerary_home.dart';
import 'trips_drawer.dart';
import 'home_experience_gallery.dart';

class HomeScreen extends HookConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(tripLibraryProvider).requireValue;
    final settings = ref.watch(settingsProvider).requireValue;
    final trip = library.activeTrip;
    void search() {
      ref
          .read(searchDraftProvider.notifier)
          .replace(settings.profile.defaults());
      ref.read(discoveryProvider.notifier).beginSearch();
    }

    void edit() {
      if (trip == null) return;
      ref.read(tripProvider.notifier).openPlan(trip.id);
      ref.read(appTabProvider.notifier).select(AppTab.itinerary);
    }

    void open() {
      if (trip == null) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlanScreen(
            tripId: trip.id,
            stops: trip.stops,
            origin: trip.origin,
            date: trip.travelDate,
            publicTransport: trip.publicTransport,
            demo: false,
            conditions: trip.conditions,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: '旅の一覧を開く',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu),
          ),
        ),
        title: const Text('TABISAKI'),
        actions: [if (trip != null) TripActionsMenu(trip: trip)],
      ),
      drawer: TripsDrawer(onNewTrip: search),
      body: SafeArea(
        top: false,
        child: trip == null
            ? _EmptyHome(onSearch: search)
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Reserve space for the independently scrolling booklet.
                  final extraTextHeight = math.max(
                    0.0,
                    MediaQuery.textScalerOf(context).scale(180) - 180,
                  );
                  final heroHeight = math.min(
                    (constraints.maxHeight * .37).clamp(190.0, 260.0) +
                        extraTextHeight,
                    constraints.maxHeight * .45,
                  );
                  const overlap = 24.0;
                  return Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: heroHeight,
                        child: _TripHero(trip: trip),
                      ),
                      Positioned(
                        top: heroHeight - overlap,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _BookletSheet(
                          key: ValueKey('sheet-${trip.id}'),
                          trip: trip,
                          onOpen: trip.stops.isEmpty ? edit : open,
                          onSeeAll: open,
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyHome extends HookConsumerWidget {
  final VoidCallback onSearch;
  const _EmptyHome({required this.onSearch});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, upperConstraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: upperConstraints.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary.withValues(alpha: .07),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Icons.landscape_outlined,
                                size: 64,
                                color: colors.primary,
                              ),
                              Positioned(
                                right: 8,
                                top: 12,
                                child: Icon(
                                  Icons.auto_awesome,
                                  size: 20,
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'まだ旅行の予定はありません',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '行きたい気分から、新しいワクワクを見つけよう',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            height: 1.7,
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 18,
                              ),
                            ),
                            onPressed: onSearch,
                            icon: const Icon(Icons.explore_outlined),
                            label: const Text('新しい旅を探す'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
            child: HomeExperienceGallery(
              photoHeight: (constraints.maxHeight * .3 - 54).clamp(80.0, 150.0),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripHero extends HookConsumerWidget {
  final TripState trip;
  const _TripHero({required this.trip});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = trip.stops.firstOrNull ?? trip.saved.firstOrNull;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        key: const ValueKey('home-trip-hero'),
        fit: StackFit.expand,
        children: [
          if (photo != null)
            TravelPhoto(photo)
          else
            ColoredBox(
              color: colors.primaryContainer,
              child: Icon(
                Icons.landscape_outlined,
                size: 88,
                color: colors.primary,
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black12, Colors.black87],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 42,
            top: 16,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  width: constraints.maxWidth - 44,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.stops.isEmpty ? '次の旅  ·  作成中' : '次の旅',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        trip.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tripDateLabel(trip),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${trip.origin} 発  ·  ${trip.conditions.transport.label}  ·  ${trip.conditions.length.label}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookletSheet extends HookConsumerWidget {
  final TripState trip;
  final VoidCallback onOpen, onSeeAll;
  const _BookletSheet({
    super.key,
    required this.trip,
    required this.onOpen,
    required this.onSeeAll,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scroll = useScrollController();
    return Material(
      key: const ValueKey('home-booklet-sheet'),
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '旅のしおり（${trip.stops.length}スポット）',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (trip.stops.length > 3)
                  TextButton(onPressed: onSeeAll, child: const Text('すべて見る')),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: trip.stops.isEmpty
                  ? const Center(
                      child: Text('まだスポットがありません', textAlign: TextAlign.center),
                    )
                  : Scrollbar(
                      controller: scroll,
                      child: ListView.builder(
                        key: PageStorageKey('home-stops-${trip.id}'),
                        controller: scroll,
                        padding: EdgeInsets.zero,
                        itemCount: trip.stops.length,
                        itemBuilder: (context, index) =>
                            _TimelineStop(trip: trip, index: index),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('home-open-booklet'),
              onPressed: onOpen,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('旅のしおりを開く'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineStop extends HookConsumerWidget {
  final TripState trip;
  final int index;
  const _TimelineStop({required this.trip, required this.index});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stop = trip.stops[index];
    final colors = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      key: ValueKey('home-stop-$index'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (index < trip.stops.length - 1)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: colors.primary.withValues(alpha: .25),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        if (stop.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            stop.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (stop.photo.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 54,
                        height: 56,
                        child: TravelPhoto(stop),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
