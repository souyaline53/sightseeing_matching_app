import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// A folded map and travel snapshots, independent of recommendations or favorites.
class BookletIllustration extends StatelessWidget {
  const BookletIllustration({super.key});
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      const Positioned.fill(child: CustomPaint(painter: _MapPainter())),
      Positioned(
        left: 22,
        top: 28,
        child: _Snapshot(
          angle: -.19,
          icon: Icons.forest_rounded,
          colors: const [Color(0xffb6cf9e), Color(0xff668953)],
        ),
      ),
      Positioned(
        right: 21,
        top: 38,
        child: _Snapshot(
          angle: .16,
          icon: Icons.train_rounded,
          colors: const [Color(0xffffd79b), Color(0xffcd813d)],
        ),
      ),
      Positioned(
        right: 12,
        bottom: 7,
        child: _Snapshot(
          angle: .12,
          icon: Icons.icecream_rounded,
          colors: const [Color(0xffffe5a7), Color(0xffffb56b)],
        ),
      ),
      const Positioned(
        left: 155,
        top: 110,
        child: Icon(
          Icons.location_on_rounded,
          color: AppColors.accent,
          size: 38,
        ),
      ),
    ],
  );
}

class _Snapshot extends StatelessWidget {
  final double angle;
  final IconData icon;
  final List<Color> colors;
  const _Snapshot({
    required this.angle,
    required this.icon,
    required this.colors,
  });
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: angle,
    child: Container(
      width: 78,
      height: 88,
      padding: const EdgeInsets.fromLTRB(5, 5, 5, 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x209a622f),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Icon(icon, size: 44, color: Colors.white.withValues(alpha: .9)),
      ),
    ),
  );
}

class _MapPainter extends CustomPainter {
  const _MapPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 310, size.height / 230);
    canvas.drawOval(
      const Rect.fromLTWH(2, 42, 306, 180),
      Paint()..color = AppColors.soft.withValues(alpha: .45),
    );
    final map = Path()
      ..moveTo(33, 191)
      ..lineTo(70, 90)
      ..lineTo(131, 110)
      ..lineTo(204, 87)
      ..lineTo(265, 175)
      ..lineTo(202, 206)
      ..lineTo(132, 185)
      ..lineTo(60, 214)
      ..close();
    canvas.drawShadow(map, const Color(0xffc89666), 6, false);
    canvas.drawPath(map, Paint()..color = AppColors.surface);
    canvas.save();
    canvas.clipPath(map);
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromLTWH(58 + i * 68, 82, 68, 135),
        Paint()
          ..color = i.isEven
              ? const Color(0xfff5e8cb)
              : const Color(0xfffff1d9),
      );
    }
    final hills = Path()
      ..moveTo(42, 178)
      ..lineTo(79, 137)
      ..quadraticBezierTo(91, 121, 101, 140)
      ..lineTo(125, 163)
      ..lineTo(157, 139)
      ..lineTo(191, 173)
      ..lineTo(218, 142)
      ..lineTo(274, 190)
      ..close();
    canvas.drawPath(hills, Paint()..color = const Color(0xffc7d3a6));
    final route = Path()
      ..moveTo(57, 184)
      ..cubicTo(80, 133, 94, 205, 129, 171)
      ..cubicTo(145, 149, 158, 174, 175, 143);
    final dash = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final metric in route.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 12) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 6, metric.length)),
          dash,
        );
      }
    }
    canvas.restore();
    canvas.drawPath(
      map,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
    final rays = Paint()
      ..color = const Color(0xffffbd4e)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(245, 27), const Offset(251, 10), rays);
    canvas.drawLine(const Offset(258, 40), const Offset(274, 29), rays);
    canvas.drawLine(const Offset(265, 54), const Offset(284, 52), rays);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => false;
}
