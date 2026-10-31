import 'package:flutter/material.dart';
import '../../model/experience.dart';
import '../../widgets/travel_photo.dart';

class ItinerarySpotCard extends StatelessWidget {
  final Experience spot;
  final int index, stayMinutes;
  final bool selected, first, last, compact;
  final VoidCallback onSelect, onStay, onPrevious, onNext, onRemove;
  const ItinerarySpotCard({
    super.key,
    required this.spot,
    required this.index,
    required this.stayMinutes,
    required this.selected,
    required this.first,
    required this.last,
    required this.onSelect,
    required this.onStay,
    required this.onPrevious,
    required this.onNext,
    required this.onRemove,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 4, 13, 6),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              color: Colors.white,
              elevation: selected ? 5 : 2,
              shadowColor: color.primary.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(17),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onSelect,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: selected ? color.primary : Colors.white,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: compact ? 64 : 88,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                TravelPhoto(spot),
                                Positioned(
                                  top: 5,
                                  left: 5,
                                  child: Container(
                                    width: 25,
                                    height: 25,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: color.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: ReorderableDragStartListener(
                                    index: index,
                                    child: Semantics(
                                      label:
                                          '${spot.title}の順番をドラッグで変更。タップで操作メニュー',
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Color(0xeeffffff),
                                          shape: BoxShape.circle,
                                        ),
                                        child: PopupMenuButton<String>(
                                          key: ValueKey(
                                            'spot-actions-${spot.id}',
                                          ),
                                          // Hover tooltip overlays cannot be reparented safely by the drag proxy.
                                          tooltip: '',
                                          padding: EdgeInsets.zero,
                                          style: IconButton.styleFrom(
                                            minimumSize: const Size(26, 26),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                          icon: Icon(
                                            Icons.drag_handle,
                                            size: 17,
                                            color: color.primary,
                                          ),
                                          onSelected: (value) {
                                            switch (value) {
                                              case 'previous':
                                                onPrevious();
                                              case 'next':
                                                onNext();
                                              case 'stay':
                                                onStay();
                                              case 'remove':
                                                onRemove();
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'previous',
                                              enabled: !first,
                                              child: const Text('前へ'),
                                            ),
                                            PopupMenuItem(
                                              value: 'next',
                                              enabled: !last,
                                              child: const Text('次へ'),
                                            ),
                                            const PopupMenuItem(
                                              value: 'stay',
                                              child: Text('滞在時間を変更'),
                                            ),
                                            const PopupMenuItem(
                                              value: 'remove',
                                              child: Text('訪問先から削除'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Text(
                            spot.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 11 : 12,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: onStay,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.schedule,
                                  size: 13,
                                  color: color.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    '滞在 $stayMinutes分',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: color.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!last)
            Positioned(
              right: -14,
              top: compact ? 65 : 84,
              child: Icon(
                Icons.east,
                size: 14,
                color: color.primary.withValues(alpha: .6),
              ),
            ),
        ],
      ),
    );
  }
}
