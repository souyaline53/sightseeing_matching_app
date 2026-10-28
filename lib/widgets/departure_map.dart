import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/departure_places.dart';

// Allows deterministic offline tests without requesting public map tiles.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

class DepartureMap extends HookConsumerWidget {
  final String selected;
  final bool highlightSelected;
  final ValueChanged<DeparturePlace> onSelect;
  final List<DeparturePlace> places;
  const DepartureMap({
    super.key,
    required this.selected,
    this.highlightSelected = true,
    required this.onSelect,
    this.places = departurePlaces,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = useMemoized(MapController.new);
    useEffect(() => map.dispose, [map]);
    final ready = useRef(false);
    final failed = useState(false);
    final enabled = ref.watch(mapTilesEnabledProvider);
    final place = departureNamed(selected);
    useEffect(() {
      if (ready.value && place != null) map.move(place.point, map.camera.zoom);
      return null;
    }, [selected]);
    return SizedBox(
      height: 290,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            FlutterMap(
              mapController: map,
              options: MapOptions(
                initialCenter: (place ?? departurePlaces.first).point,
                initialZoom: 13,
                minZoom: 5,
                maxZoom: 17,
                backgroundColor: const Color(0xffe4ece4),
                onMapReady: () => ready.value = true,
              ),
              children: [
                if (enabled)
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'jp.tabisaki.prototype',
                    maxNativeZoom: 19,
                    errorTileCallback: (_, error, stack) {
                      if (!failed.value) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (context.mounted) failed.value = true;
                        });
                      }
                    },
                  ),
                MarkerLayer(
                  markers: [
                    for (final p in places)
                      Marker(
                        point: p.point,
                        width: 48,
                        height: 48,
                        child: IconButton(
                          key: ValueKey('map-pin-${p.id}'),
                          tooltip: '${p.name}を地図で選択',
                          onPressed: () => onSelect(p),
                          icon: Icon(
                            p.bus
                                ? Icons.directions_bus_filled
                                : Icons.location_on,
                            color: highlightSelected && p.name == selected
                                ? const Color(0xff145c49)
                                : Colors.blueGrey,
                            size: highlightSelected && p.name == selected
                                ? 40
                                : 32,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (!enabled || failed.value)
              const Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      '地図画像を表示できません。出発地の選択ボタンをご利用ください。',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 8,
              bottom: 34,
              child: Column(
                children: [
                  IconButton.filledTonal(
                    tooltip: '地図を拡大',
                    onPressed: () => map.move(
                      map.camera.center,
                      (map.camera.zoom + 1).clamp(5, 17),
                    ),
                    icon: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 4),
                  IconButton.filledTonal(
                    tooltip: '地図を縮小',
                    onPressed: () => map.move(
                      map.camera.center,
                      (map.camera.zoom - 1).clamp(5, 17),
                    ),
                    icon: const Icon(Icons.remove),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ColoredBox(
                color: Colors.white,
                child: InkWell(
                  onTap: () => launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Text(
                      '© OpenStreetMap contributors',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
