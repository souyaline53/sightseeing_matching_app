import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../model/experience.dart';
import '../../../model/trip_plan.dart';
import '../../../model/transport.dart';
import '../../../repository/driving_route_repository.dart';
import '../../../service/transport/driving_schedule.dart';
import '../../../service/transport/external_directions.dart';

class CarTransportOptions extends ConsumerWidget {
  final TripState trip;
  final Experience from, to;
  final ValueChanged<TransportSelection> onSave;
  const CarTransportOptions({
    super.key,
    required this.trip,
    required this.from,
    required this.to,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultDeparture = drivingEarliestDepartureMinutes(trip, from.id);
    final earliest = from.id == trip.originEndpointId ? 0 : defaultDeparture;
    final saved = trip.transportSelections
        .where(
          (s) =>
              s.from == from.id &&
              s.to == to.id &&
              isCurrentDrivingSelection(trip, s),
        )
        .firstOrNull;
    final departure =
        saved?.data['departureMinutes'] as int? ?? defaultDeparture;
    final effectiveDeparture = departure < earliest ? earliest : departure;
    if (!hasDrivingLocation(from) || !hasDrivingLocation(to)) {
      return const Text('車ルートの検索には出発地・目的地の住所または位置情報が必要です。');
    }
    final key = drivingRouteKey(from, to);
    final route = ref.watch(drivingRouteProvider(key));
    final uri = externalDirectionsUri(
      from,
      to,
      mode: DirectionsMode.driving,
      platform: defaultTargetPlatform,
      web: kIsWeb,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        route.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Column(
            children: [
              const Text('車ルートを取得できませんでした。住所や通信状態を確認して再試行してください。'),
              TextButton(
                onPressed: () => ref.invalidate(drivingRouteProvider(key)),
                child: const Text('再試行'),
              ),
            ],
          ),
          data: (data) {
            final duration = ((data['durationSeconds'] as num) / 60).ceil();
            final arrival = effectiveDeparture + duration;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const ValueKey('car-travel-times'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text('出発'),
                            Text(
                              drivingTime(effectiveDeparture),
                              key: const ValueKey('car-departure-label'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.east),
                      Expanded(
                        child: Column(
                          children: [
                            const Text('到着予定'),
                            Text(
                              drivingTime(arrival),
                              key: const ValueKey('car-arrival-label'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '車で約$duration分 · ${((data['distanceMeters'] as num) / 1000).toStringAsFixed(1)}km',
                ),
                ListTile(
                  key: const ValueKey('car-departure-time'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('出発時刻を変更'),
                  subtitle: Text(drivingTime(effectiveDeparture)),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: effectiveDeparture ~/ 60 % 24,
                        minute: effectiveDeparture % 60,
                      ),
                    );
                    if (picked == null || !context.mounted) return;
                    var minutes =
                        picked.hour * 60 +
                        picked.minute +
                        (effectiveDeparture ~/ 1440) * 1440;
                    // An earlier clock time means the following day, preserving visit order.
                    while (minutes < earliest) {
                      minutes += 1440;
                    }
                    onSave(
                      TransportSelection({
                        'mode': 'car',
                        'fromSpotId': from.id,
                        'toSpotId': to.id,
                        'selectedTripId': 'car-${from.id}-${to.id}',
                        'departureMinutes': minutes,
                        'arrivalMinutes': minutes + duration,
                        'durationSeconds': data['durationSeconds'],
                        'distanceMeters': data['distanceMeters'],
                        'serviceDate': drivingServiceDate(trip),
                        'provider': data['provider'],
                        'departureOverride': true,
                        'requestedDepartureMinutes': minutes,
                      }),
                    );
                  },
                ),
                const Text(
                  '所要時間は目安です。渋滞や休憩時間は含みません。',
                  style: TextStyle(fontSize: 11),
                ),
                const Text(
                  'Google Maps',
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 11),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (uri != null)
          FilledButton.icon(
            key: const ValueKey('car-open-maps'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onPressed: () async {
              var opened = false;
              try {
                opened = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {}
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('マップを開けませんでした。時間をおいてお試しください。')),
                );
              }
            },
            icon: const Icon(Icons.navigation_outlined, size: 24),
            label: const Text(
              'マップアプリでルートを確認',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}
