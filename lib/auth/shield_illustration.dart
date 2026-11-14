import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';

/// The shield-and-lock picture at the top of the sign-in screen. The same
/// drawing as the desktop app's sign-in panel. Decorative only, so it's
/// hidden from screen readers.
class ShieldIllustration extends StatelessWidget {
  const ShieldIllustration({super.key, this.size = 112});

  final double size;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _ShieldPainter(
            fill: gradients.illustration,
            glassFill: gradients.glassFill,
            glassBorder: gradients.glassBorder,
          ),
        ),
      ),
    );
  }
}

/// Draws on a 220 × 220 grid, scaled to fit: two rings, a gradient shield,
/// and a white padlock with an indigo keyhole.
class _ShieldPainter extends CustomPainter {
  _ShieldPainter({
    required this.fill,
    required this.glassFill,
    required this.glassBorder,
  });

  final LinearGradient fill;
  final Color glassFill;
  final Color glassBorder;

  static const _centre = Offset(110, 110);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.shortestSide / 220);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = glassBorder;
    canvas.drawCircle(_centre, 104, ring..strokeWidth = 1.5);
    canvas.drawCircle(_centre, 80, Paint()..color = glassFill);
    canvas.drawCircle(_centre, 80, ring..strokeWidth = 1);

    final shield = Path()
      ..moveTo(110, 42)
      ..lineTo(160, 62)
      ..lineTo(160, 108)
      ..cubicTo(160, 140, 138, 162, 110, 174)
      ..cubicTo(82, 162, 60, 140, 60, 108)
      ..lineTo(60, 62)
      ..close();
    canvas.drawPath(
      shield,
      Paint()..shader = fill.createShader(shield.getBounds()),
    );
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.8),
    );

    final white = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(88, 104, 44, 36),
        const Radius.circular(7),
      ),
      white,
    );
    final shackle = Path()
      ..moveTo(96, 104)
      ..lineTo(96, 92)
      ..arcToPoint(const Offset(124, 92), radius: const Radius.circular(14))
      ..lineTo(124, 104);
    canvas.drawPath(
      shackle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white,
    );

    // The keyhole stays the brand indigo in both modes; it sits on white.
    final keyhole = Paint()..color = AppColors.lightPrimary;
    canvas.drawCircle(const Offset(110, 119), 5, keyhole);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(108, 121, 4, 10),
        const Radius.circular(2),
      ),
      keyhole,
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter old) =>
      old.fill != fill ||
      old.glassFill != glassFill ||
      old.glassBorder != glassBorder;
}
