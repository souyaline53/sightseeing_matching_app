import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/departure_places.dart';
import '../../widgets/departure_map.dart' show mapTilesEnabledProvider;

/// A background map only. It intentionally has no markers or route overlays.
class ItineraryMap extends ConsumerStatefulWidget {
  final String origin;
  const ItineraryMap({super.key, required this.origin});
  @override
  ConsumerState<ItineraryMap> createState() => _MapState();
}

class _MapState extends ConsumerState<ItineraryMap> {
  bool failed = false;
  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(mapTilesEnabledProvider);
    final center =
        (departureNamed(widget.origin) ?? departurePlaces.first).point;
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          key: ValueKey(widget.origin),
          options: MapOptions(
            initialCenter: center,
            initialZoom: 12,
            minZoom: 5,
            maxZoom: 18,
            backgroundColor: const Color(0xffe3ebe4),
          ),
          children: [
            if (enabled)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'jp.tabisaki.prototype',
                maxNativeZoom: 19,
                errorTileCallback: (_, error, stack) {
                  if (!failed) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !failed) setState(() => failed = true);
                    });
                  }
                },
              ),
          ],
        ),
        // At the top so attribution remains visible when the sheet covers the map.
        Positioned(
          top: 4,
          left: 8,
          child: Material(
            color: Colors.white.withValues(alpha: .9),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 9),
                ),
              ),
            ),
          ),
        ),
        if (failed || !enabled)
          const Positioned(
            top: 30,
            left: 12,
            child: Text(
              '地図を読み込めません。旅程の編集は続けられます。',
              style: TextStyle(fontSize: 10, backgroundColor: Colors.white),
            ),
          ),
      ],
    );
  }
}
