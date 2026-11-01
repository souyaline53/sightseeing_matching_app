import 'package:flutter/material.dart';

/// Fixed endpoints live outside the reorderable sightseeing items.
class ItineraryEndpointCard extends StatelessWidget {
  final bool departure, selected;
  final String label;
  final VoidCallback? onTap;
  const ItineraryEndpointCard({
    super.key,
    required this.departure,
    required this.label,
    this.selected = false,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 4, 12, 6),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: .09)
            : colors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  departure ? Icons.trip_origin : Icons.home_outlined,
                  size: 30,
                  color: colors.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  departure ? '出発地' : '帰宅',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (onTap != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      '交通情報を見る',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
