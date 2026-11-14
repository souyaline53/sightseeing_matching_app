import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/catalog_data.dart';
import '../../model/experience.dart';
import '../../theme/app_theme.dart';
import '../../navigation/travel_navigation.dart';
import '../shared/experiences/widgets/place_card.dart';
import '../shared/experiences/places_catalog_screen.dart';
import 'widgets/discovery_hero.dart';

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

class HomeOverview extends ConsumerWidget {
  const HomeOverview({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider).requireValue.experiences;
    final spots = catalog.take(4).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('TABISAKI')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          DiscoveryHero(
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
