import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/material.dart';
import '../model/experience.dart';

class TravelPhoto extends HookConsumerWidget {
  final Experience experience;
  const TravelPhoto(this.experience, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Image.network(
    experience.imageUrl,
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    errorBuilder: (_, error, stack) => Container(
      color: const Color(0xffd9e7df),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.landscape_outlined,
                size: 52,
                color: Color(0xff285c4b),
              ),
              Text(experience.area, maxLines: 1),
              const Text('風景のイメージ', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    ),
  );
}
