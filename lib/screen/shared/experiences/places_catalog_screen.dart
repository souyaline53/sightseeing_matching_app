import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../data/catalog_data.dart';
import '../../../model/experience.dart';
import '../../../widgets/trip_from_saved_button.dart';
import 'widgets/place_card.dart';

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
