import 'package:flutter/material.dart';
import '../../../model/experience.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/travel_photo.dart';

class DiscoveryHero extends StatelessWidget {
  final Experience? landscape, nature;
  final VoidCallback onSearch;
  const DiscoveryHero({
    super.key,
    required this.landscape,
    required this.nature,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final height =
        222.0 + (MediaQuery.textScalerOf(context).scale(36) - 36) * 2.5;
    return Stack(
      children: [
        SizedBox(
          height: height + 40,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(child: _HomePhoto(landscape)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.ink.withValues(alpha: .32),
                      AppColors.ink.withValues(alpha: .55),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 76,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00fff8f0), AppColors.background],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 22,
          left: 24,
          right: 24,
          height: height - 52,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'まだ知らない、とっておきへ。',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              const Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '北海道で、\n何する？',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 12,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '自然も、歴史も、グルメも。',
                maxLines: 2,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(14, height - 12, 14, 2),
          child: _InterestCard(photo: nature, onPressed: onSearch),
        ),
      ],
    );
  }
}

class _HomePhoto extends StatelessWidget {
  final Experience? experience;
  const _HomePhoto(this.experience);
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xffbd7743), Color(0xff6d442c)],
      ),
    ),
    child: experience == null
        ? null
        : TravelPhoto(experience!, placeholder: const SizedBox.expand()),
  );
}

class _InterestCard extends StatelessWidget {
  final Experience? photo;
  final VoidCallback onPressed;
  const _InterestCard({required this.photo, required this.onPressed});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: .16),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Colors.white, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('home-interest-search'),
        onTap: onPressed,
        child: Stack(
          children: [
            if (photo != null)
              Positioned.fill(
                child: ExcludeSemantics(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: .62,
                      heightFactor: 1,
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.transparent, Color(0xbbffffff)],
                          stops: [.02, 1],
                        ).createShader(bounds),
                        blendMode: BlendMode.dstIn,
                        child: TravelPhoto(
                          photo!,
                          placeholder: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (MediaQuery.textScalerOf(context).scale(20) <= 28) ...[
                        const Icon(
                          Icons.travel_explore,
                          size: 31,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                      ],
                      const Expanded(
                        child: Text(
                          '興味から旅行を作る',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 28,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '好きなことから、次の行き先へ。',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.ink,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const ExcludeSemantics(
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _InterestTag(Icons.park_outlined, '自然'),
                        _InterestTag(Icons.account_balance_outlined, '歴史'),
                        _InterestTag(Icons.restaurant, 'グルメ'),
                        _InterestTag(Icons.photo_camera_outlined, '絶景'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InterestTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InterestTag(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.softSurface.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
