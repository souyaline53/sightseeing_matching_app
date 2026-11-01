import 'stop_group_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../repository/gtfs_repository.dart';
import '../../service/cloud/cloud_services.dart';
import '../../model/transport.dart';

class TransportStopPicker extends ConsumerStatefulWidget {
  final bool selectRoute,
      selectAgency,
      manualOnly,
      multipleStops,
      returnStopRecord;
  const TransportStopPicker({
    super.key,
    this.selectRoute = false,
    this.selectAgency = false,
    this.manualOnly = false,
    this.multipleStops = false,
    this.returnStopRecord = false,
  });
  @override
  ConsumerState<TransportStopPicker> createState() => _Picker();
}

class _Picker extends ConsumerState<TransportStopPicker> {
  List<Json> items = [], feeds = [];
  Json? agency, route, selectedFeed;
  int step = 0;
  bool busy = true, more = false;
  String search = '', error = '';
  String? cursor;
  final selected = <String, Json>{};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool next = false}) async {
    setState(() {
      busy = true;
      error = '';
      if (!next) {
        items = [];
        cursor = null;
      }
    });
    try {
      final cloud = await ref.read(cloudServicesProvider.future);
      cloud.requireAdmin();
      final repo = GtfsRepository(cloud.firestore);
      final name = [
        'transport_agencies',
        'transport_routes',
        'transport_stops',
      ][step];
      final rows = <Json>[];
      if (step == 0) {
        // Agency documents are small; no timetable is fetched here.
        feeds = await repo.feeds();
        for (final f in feeds.where(
          (f) => !widget.manualOnly && f['activeVersionId'] != null,
        )) {
          for (final r in await repo.agencies(f)) {
            rows.add({...r, '_feed': f});
          }
        }
      }
      if (step == 0 || selectedFeed == null) {
        Query<Json> q = cloud.firestore.collection(name);
        if (step == 1) q = q.where('agencyId', isEqualTo: agency!['id']);
        if (step == 2) q = q.where('routeIds', arrayContains: route!['id']);
        q = q.orderBy(FieldPath.documentId).limit(100);
        if (cursor != null) q = q.startAfter([cursor]);
        final docs = await q.get();
        rows.addAll(
          docs.docs.map((d) {
            final data = d.data(), location = data['location'];
            return {
              ...data,
              'id': d.id,
              if (location is GeoPoint) ...{
                'latitude': location.latitude,
                'longitude': location.longitude,
              },
            };
          }),
        );
        more = docs.docs.length == 100;
        if (docs.docs.isNotEmpty) cursor = docs.docs.last.id;
      } else {
        final all = step == 1
            ? await repo.routesFor(selectedFeed!, agency!['id'] as String)
            : await repo.stopsFor(selectedFeed!, route!['id'] as String);
        all.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
        final page = step == 2
            ? all
            : all
                  .where(
                    (r) =>
                        cursor == null ||
                        (r['id'] as String).compareTo(cursor!) > 0,
                  )
                  .take(100)
                  .toList();
        rows.addAll(page);
        more = step == 2 ? false : page.length == 100;
        if (page.isNotEmpty) cursor = page.last['id'] as String;
      }
      if (mounted) setState(() => items.addAll(rows));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(['① 事業者を選ぶ', '② 路線を選ぶ', '③ 停留所を選ぶ'][step]),
    content: SizedBox(
      width: 600,
      height: 480,
      child: Column(
        children: [
          if (step > 0) Text('${agency?['name']} / ${route?['name'] ?? ''}'),
          TextField(
            key: ValueKey(step),
            decoration: const InputDecoration(labelText: '読み込み済み候補を名前・IDで検索'),
            onChanged: (v) => setState(() => search = v),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error.isNotEmpty) Text(error),
          Expanded(
            child: ListView(
              children: [
                if (step == 2)
                  StopGroupOptions(
                    stops: items,
                    search: search,
                    multiple: widget.multipleStops,
                    enabled: !busy,
                    selectedIds: selected.keys.toSet(),
                    onPick: (stop) => Navigator.pop(
                      context,
                      widget.returnStopRecord ? stop : stop['id'],
                    ),
                    onToggle: (stops, value) => setState(() {
                      for (final stop in stops) {
                        if (value) {
                          selected[stop['id'] as String] = stop;
                        } else {
                          selected.remove(stop['id']);
                        }
                      }
                    }),
                  ),
                if (step != 2)
                  for (final r in items.where(
                    (r) =>
                        r['isActive'] != false &&
                        '${r['name']} ${r['id']}'.toLowerCase().contains(
                          search.toLowerCase(),
                        ),
                  ))
                    ListTile(
                      title: Text(
                        '${r['name'] ?? r['displayName'] ?? r['id']}',
                      ),
                      subtitle: Text(
                        '${r['id']} ${r['platformCode'] == null ? '' : '乗り場 ${r['platformCode']}'}',
                      ),
                      onTap: busy
                          ? null
                          : () {
                              if (step == 2 ||
                                  (step == 1 && widget.selectRoute) ||
                                  (step == 0 && widget.selectAgency)) {
                                Navigator.pop(context, r['id']);
                                return;
                              }
                              setState(() {
                                if (step == 0) {
                                  agency = r;
                                  selectedFeed = r['_feed'] as Json?;
                                } else {
                                  route = r;
                                }
                                step++;
                                search = '';
                              });
                              load();
                            },
                    ),
                if (more)
                  TextButton(
                    onPressed: busy ? null : () => load(next: true),
                    child: const Text('次の100件を読み込む'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      if (widget.multipleStops && selected.isNotEmpty)
        TextButton(
          onPressed: busy ? null : () => setState(selected.clear),
          child: const Text('選択をクリア'),
        ),
      if (widget.multipleStops)
        FilledButton(
          onPressed: busy || selected.isEmpty
              ? null
              : () => Navigator.pop(context, selected.values.toList()),
          child: Text('選択した${selected.length}件を登録'),
        ),
      if (step > 0)
        TextButton(
          onPressed: busy
              ? null
              : () {
                  setState(() {
                    step--;
                    search = '';
                  });
                  load();
                },
          child: const Text('戻る'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
    ],
  );
}
