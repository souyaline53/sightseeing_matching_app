import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/catalog_data.dart';
import '../../model/experience.dart';
import '../../state/discovery_state.dart';
import '../../state/app_tab.dart';
import '../../state/settings_state.dart';
import '../../state/trip_library_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/travel_photo.dart';
import '../../widgets/trip_from_saved_button.dart';
import '../recommendation/experience_detail.dart';

void beginInterestSearch(WidgetRef ref) {
  final defaults = ref.read(settingsProvider).requireValue.profile.defaults();
  ref.read(searchDraftProvider.notifier).replace(defaults);
  ref.read(discoveryProvider.notifier).beginSearch();
  ref.read(appTabProvider.notifier).select(AppTab.recommendation);
}

Experience? _featuredPhoto(List<Experience> spots, List<String> hints) {
  final photos = spots.where((e) => e.photo.isNotEmpty);
  for (final hint in hints) {
    final match = photos
        .where((e) => '${e.displayName} ${e.category}'.contains(hint))
        .firstOrNull;
    if (match != null) return match;
  }
  return photos.firstOrNull;
}

class DiscoveryHome extends ConsumerWidget {
  const DiscoveryHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider).requireValue.experiences;
    final spots = catalog.take(4).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('TABISAKI')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _DiscoveryHero(
            landscape: _featuredPhoto(catalog, ['シューパロ', '湖', '展望', '自然']),
            nature: _featuredPhoto(catalog, ['滝', '自然', '湖']),
            onSearch: () => beginInterestSearch(ref),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: AppColors.primary,
                  size: 26,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'おすすめの観光地',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PlacesCatalogScreen(),
                    ),
                  ),
                  child: const Text('もっと見る'),
                ),
              ],
            ),
          ),
          for (var i = 0; i < spots.length; i += 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PlaceCard(experience: spots[i], interactive: false),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: i + 1 < spots.length
                        ? PlaceCard(
                            experience: spots[i + 1],
                            interactive: false,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DiscoveryHero extends StatelessWidget {
  final Experience? landscape, nature;
  final VoidCallback onSearch;
  const _DiscoveryHero({
    required this.landscape,
    required this.nature,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final height =
        222.0 + (MediaQuery.textScalerOf(context).scale(36) - 36) * 2.5;
    return Stack(
      children: [
        SizedBox(
          height: height + 40,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(child: _HomePhoto(landscape)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.ink.withValues(alpha: .32),
                      AppColors.ink.withValues(alpha: .55),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 76,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00fff8f0), AppColors.background],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 22,
          left: 24,
          right: 24,
          height: height - 52,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'まだ知らない、とっておきへ。',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              const Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '北海道で、\n何する？',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 12,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '自然も、歴史も、グルメも。',
                maxLines: 2,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(14, height - 12, 14, 2),
          child: _InterestCard(photo: nature, onPressed: onSearch),
        ),
      ],
    );
  }
}

class _HomePhoto extends StatelessWidget {
  final Experience? experience;
  const _HomePhoto(this.experience);
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xffbd7743), Color(0xff6d442c)],
      ),
    ),
    child: experience == null
        ? null
        : TravelPhoto(experience!, placeholder: const SizedBox.expand()),
  );
}

class _InterestCard extends StatelessWidget {
  final Experience? photo;
  final VoidCallback onPressed;
  const _InterestCard({required this.photo, required this.onPressed});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: .16),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Colors.white, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('home-interest-search'),
        onTap: onPressed,
        child: Stack(
          children: [
            if (photo != null)
              Positioned.fill(
                child: ExcludeSemantics(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: .62,
                      heightFactor: 1,
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.transparent, Color(0xbbffffff)],
                          stops: [.02, 1],
                        ).createShader(bounds),
                        blendMode: BlendMode.dstIn,
                        child: TravelPhoto(
                          photo!,
                          placeholder: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (MediaQuery.textScalerOf(context).scale(20) <= 28) ...[
                        const Icon(
                          Icons.travel_explore,
                          size: 31,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                      ],
                      const Expanded(
                        child: Text(
                          '興味から旅行を作る',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 28,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '好きなことから、次の行き先へ。',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.ink,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const ExcludeSemantics(
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _InterestTag(Icons.park_outlined, '自然'),
                        _InterestTag(Icons.account_balance_outlined, '歴史'),
                        _InterestTag(Icons.restaurant, 'グルメ'),
                        _InterestTag(Icons.photo_camera_outlined, '絶景'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InterestTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InterestTag(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.softSurface.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class PlacesCatalogScreen extends ConsumerWidget {
  const PlacesCatalogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spots =
        ref.watch(catalogProvider).value?.experiences ?? <Experience>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('観光地スポット一覧', style: TextStyle(fontSize: 22)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent:
                (constraints.maxWidth - 32) / 2 / PlaceCard.photoAspectRatio +
                PlaceCard.detailsHeight(context),
          ),
          itemCount: spots.length,
          itemBuilder: (_, index) => PlaceCard(experience: spots[index]),
        ),
      ),
      bottomNavigationBar: const TripFromSavedButton(),
    );
  }
}

/// The home preview shares the catalog card, with all actions omitted.
class PlaceCard extends ConsumerWidget {
  static const photoAspectRatio = 1.6;
  static double detailsHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return (16 +
            scale.scale(14) * 1.3 +
            5 +
            (scale.scale(12) * 1.4).ceilToDouble() +
            7 +
            (scale.scale(11) * 1.4).ceilToDouble().clamp(15, double.infinity))
        .ceilToDouble();
  }

  final Experience experience;
  final bool interactive;
  const PlaceCard({
    super.key,
    required this.experience,
    this.interactive = true,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref
        .watch(savedExperiencesProvider)
        .any((e) => e.id == experience.id);
    final scale = MediaQuery.textScalerOf(context);
    return Material(
      color: AppColors.surface,
      elevation: 1.5,
      shadowColor: AppColors.ink.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('place-card-${experience.id}'),
        onTap: interactive ? () => showExperience(context, experience) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: photoAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TravelPhoto(experience),
                  if (experience.category.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      right: interactive ? 48 : 8,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: .94),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            experience.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (interactive)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: IconButton.filledTonal(
                        key: ValueKey('place-save-${experience.id}'),
                        tooltip: saved ? '保存を取り消す' : '観光地を保存',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surface.withValues(
                            alpha: .95,
                          ),
                          foregroundColor: AppColors.primary,
                        ),
                        onPressed: () => ref
                            .read(tripLibraryProvider.notifier)
                            .toggleExperience(experience),
                        icon: Icon(
                          saved ? Icons.favorite : Icons.favorite_border,
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: scale.scale(14) * 1.3,
                    child: Text(
                      experience.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    experience.description.isEmpty
                        ? experience.area
                        : experience.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 15,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          '約${experience.minutes}分',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
