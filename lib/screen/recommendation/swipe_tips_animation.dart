import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Continuously demonstrate the three swipe directions.
class SwipeTipsAnimation extends HookWidget {
  const SwipeTipsAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 5400),
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    useEffect(() {
      if (reduceMotion) {
        controller.stop();
      } else {
        controller.repeat();
      }
      return null;
    }, [reduceMotion]);
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '指を左へ動かすと次へ、右へ動かすと前へ、上へ動かすと保存します',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 124,
              width: double.infinity,
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final progress = controller.value * 3;
                    final step = progress.floor().clamp(0, 2);
                    final phase = progress - step;
                    final motion = math.sin(phase * math.pi);
                    final offset = switch (step) {
                      0 => Offset(-44 * motion, 0),
                      1 => Offset(44 * motion, 0),
                      _ => Offset(0, -38 * motion),
                    };
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 84,
                          height: 100,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        Transform.translate(
                          offset: offset * .5,
                          child: Container(
                            width: 84,
                            height: 100,
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colors.primary),
                            ),
                            child: Icon(
                              step == 2
                                  ? Icons.favorite
                                  : Icons.landscape_outlined,
                              color: colors.onPrimaryContainer,
                              size: 32,
                            ),
                          ),
                        ),
                        Transform.translate(
                          key: const ValueKey('swipe-hint-finger'),
                          offset: offset + const Offset(12, 24),
                          child: Icon(
                            Icons.touch_app,
                            size: 42,
                            color: colors.primary,
                          ),
                        ),
                        Align(
                          alignment: Alignment.topLeft,
                          child: Icon(switch (step) {
                            0 => Icons.arrow_back,
                            1 => Icons.arrow_forward,
                            _ => Icons.arrow_upward,
                          }, color: colors.primary),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
