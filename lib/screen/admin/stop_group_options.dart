import 'package:flutter/material.dart';
import '../../model/transport.dart';
import '../../model/stop_selection.dart';

/// Nearby same-name platforms share a visual group; each keeps its original ID.
class StopGroupOptions extends StatelessWidget {
  final List<Json> stops;
  final String search;
  final bool multiple, enabled;
  final Set<String> selectedIds;
  final void Function(Json) onPick;
  final void Function(List<Json>, bool) onToggle;
  const StopGroupOptions({
    super.key,
    required this.stops,
    this.search = '',
    this.multiple = false,
    this.enabled = true,
    this.selectedIds = const {},
    required this.onPick,
    required this.onToggle,
  });
  @override
  Widget build(BuildContext context) {
    final groups = groupStopSelections(stops).where(
      (group) => group.any(
        (s) =>
            '${s['name']} ${s['id']} ${s['stopId']} ${(s['stopDestinations'] as List? ?? []).join(' ')}'
                .toLowerCase()
                .contains(search.toLowerCase()),
      ),
    );
    return Column(
      children: [
        for (final group in groups)
          if (group.length == 1)
            _row(context, group.single)
          else
            ExpansionTile(
              key: PageStorageKey('stop-group-${group.first['id']}'),
              title: Text('${group.first['name']}（${group.length}乗り場）'),
              subtitle: Text(
                stopGroupDistanceMeters(group) == null
                    ? '方向・乗り場を確認して選択'
                    : '乗り場間の直線距離：約${stopGroupDistanceMeters(group)}m。徒歩経路は別途確認',
              ),
              children: [
                if ((stopGroupDistanceMeters(group) ?? 0) > 300)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('同名でも離れた停留所を含みます。位置とアクセス経路を確認して選んでください。'),
                  ),
                if (multiple)
                  CheckboxListTile(
                    key: ValueKey('group-select-${group.first['id']}'),
                    title: const Text('すべての乗り場を選択'),
                    subtitle: const Text('徒歩時間は登録後に乗り場ごとに入力できます'),
                    value: group.every((s) => selectedIds.contains(s['id'])),
                    onChanged: enabled
                        ? (v) => onToggle(group, v == true)
                        : null,
                  ),
                for (final stop in group) _row(context, stop),
              ],
            ),
      ],
    );
  }

  Widget _row(BuildContext context, Json stop) {
    final destinations = (stop['stopDestinations'] as List? ?? [])
        .cast<String>();
    final origins = (stop['arrivalOrigins'] as List? ?? []).cast<String>();
    final details = <String>[
      if (destinations.isEmpty)
        origins.isEmpty ? '方向情報未確認' : '${origins.join('・')}から到着（降車用）',
      'ID：${stop['stopId'] ?? stop['id']}',
      if (stop['latitude'] is num && stop['longitude'] is num)
        '位置：${(stop['latitude'] as num).toStringAsFixed(6)}, ${(stop['longitude'] as num).toStringAsFixed(6)}',
    ];
    return multiple
        ? CheckboxListTile(
            key: ValueKey('stop-option-${stop['id']}'),
            title: Text(stopSelectionLabel(stop)),
            subtitle: Text(details.join('\n')),
            value: selectedIds.contains(stop['id']),
            onChanged: enabled ? (v) => onToggle([stop], v == true) : null,
          )
        : ListTile(
            key: ValueKey('stop-option-${stop['id']}'),
            title: Text(stopSelectionLabel(stop)),
            subtitle: Text(details.join('\n')),
            onTap: enabled ? () => onPick(stop) : null,
          );
  }
}
