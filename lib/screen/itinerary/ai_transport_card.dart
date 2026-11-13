import 'package:flutter/material.dart';
import '../../model/ai_trip_segment.dart';
import '../../model/transport_journey.dart';

class AiTransportCard extends StatelessWidget {
  final AiTripSegment segment;
  final bool needsReview;
  const AiTransportCard({
    super.key,
    required this.segment,
    this.needsReview = false,
  });
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    String time(int? t) => t == null ? '時刻未提供' : journeyTime(t);
    final routes = segment.routeNames;
    return Container(
      key: ValueKey('ai-transport-${segment.fromId}-${segment.toId}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.primary.withValues(alpha: .045),
        border: Border.all(color: color.primary.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'AIで作成',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (needsReview || segment.requiresReview)
                Tooltip(
                  triggerMode: TooltipTriggerMode.tap,
                  message: needsReview
                      ? '旅程が変更されています。交通情報を再確認してください。'
                      : segment.reviewReasons.isEmpty
                      ? '未確認の情報を含みます。運行情報・乗換をご確認ください。'
                      : segment.reviewReasons.join('\n'),
                  child: Text(
                    '要確認',
                    style: TextStyle(
                      fontSize: 10,
                      color: color.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${time(segment.departureSeconds)} → ${time(segment.arrivalSeconds)}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${segment.fromName} → ${segment.toName}',
            style: const TextStyle(fontSize: 12),
          ),
          if (routes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                routes,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (needsReview)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '旅程が変更されています。交通情報を再確認してください。',
                style: TextStyle(fontSize: 11),
              ),
            ),
          for (final step in segment.steps) ...[
            const SizedBox(height: 7),
            Text(
              _description(step),
              style: TextStyle(fontSize: 12, color: color.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  String _description(Map<String, dynamic> s) {
    final kind = s['kind'];
    final from = s['fromStopName'] as String? ?? segment.names[s['fromStopId']];
    final to = s['toStopName'] as String? ?? segment.names[s['toStopId']];
    final route = segment.routeLabel(s);
    final start = s['departureSeconds'], end = s['arrivalSeconds'];
    final timing = start is int && end is int
        ? '${journeyTime(start)}–${journeyTime(end)}'
        : '';
    if (kind == 'walk') {
      final seconds =
          s['walkingSeconds'] ??
          s['durationSeconds'] ??
          (start is int && end is int ? end - start : null);
      return '徒歩${seconds is num ? ' ${((seconds) / 60).ceil()}分' : ''}${from != null && to != null ? ' · $from → $to' : ''}';
    }
    if (kind == 'wait') return '待ち時間${timing.isEmpty ? '' : ' · $timing'}';
    return [
      ?route,
      if (from != null || to != null)
        '${from ?? '乗車停留所名未提供'} → ${to ?? '降車停留所名未提供'}',
      if (timing.isNotEmpty) timing,
    ].join(' · ');
  }
}
