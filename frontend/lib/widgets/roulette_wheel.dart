import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 参加者を均等な扇形に分けた、描画専用の円形ルーレット。
class RouletteWheel extends StatelessWidget {
  const RouletteWheel({
    super.key,
    required this.names,
    required this.rotation,
    this.winnerIndex,
    this.pointerWobble = 0,
  });

  final List<String> names;
  final double rotation;
  final int? winnerIndex;
  final double pointerWobble;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${names.length}人の端数ルーレット',
      value: winnerIndex == null ? '抽選前' : '${names[winnerIndex!]}が当選',
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RouletteWheelPainter(
                  names: names,
                  rotation: rotation,
                  winnerIndex: winnerIndex,
                  colors: _wheelColors,
                  borderColor: scheme.surface,
                  textColor: scheme.onPrimaryContainer,
                  winnerColor: _rouletteWinnerColor,
                  winnerTextColor: _rouletteWinnerTextColor,
                ),
              ),
            ),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: _rouletteAccentColor, width: 4),
                boxShadow: const [
                  BoxShadow(color: Color(0x24000000), blurRadius: 10),
                ],
              ),
            ),
            Positioned(
              top: -10,
              child: Transform.rotate(
                angle: pointerWobble,
                alignment: Alignment.topCenter,
                child: CustomPaint(
                  size: const Size(34, 38),
                  painter: _PointerPainter(
                    color: _rouletteAccentColor,
                    borderColor: scheme.surface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const List<Color> _wheelColors = [
  Color(0xFFFF3D71),
  Color(0xFFFF6D00),
  Color(0xFFFFC400),
  Color(0xFF00C853),
  Color(0xFF00B8D4),
  Color(0xFF2979FF),
  Color(0xFF651FFF),
  Color(0xFFD500F9),
];

// MegaPayのブランドカラーとは分けた、ルーレット専用の配色。
const _rouletteAccentColor = Color(0xFF263238);
const _rouletteWinnerColor = Color(0xFFFFD600);
const _rouletteWinnerTextColor = Color(0xFF201A00);

class _RouletteWheelPainter extends CustomPainter {
  _RouletteWheelPainter({
    required this.names,
    required this.rotation,
    required this.winnerIndex,
    required this.colors,
    required this.borderColor,
    required this.textColor,
    required this.winnerColor,
    required this.winnerTextColor,
  });

  final List<String> names;
  final double rotation;
  final int? winnerIndex;
  final List<Color> colors;
  final Color borderColor;
  final Color textColor;
  final Color winnerColor;
  final Color winnerTextColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (names.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = math.pi * 2 / names.length;
    final startOffset = -math.pi / 2 - sweep / 2 + rotation;
    final fill = Paint()..style = PaintingStyle.fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = borderColor;

    for (var index = 0; index < names.length; index++) {
      fill.color = index == winnerIndex
          ? winnerColor
          : colors[index % colors.length];
      final start = startOffset + index * sweep;
      canvas.drawArc(rect, start, sweep, true, fill);
      canvas.drawArc(rect, start, sweep, true, border);
      if (names.length <= 20) {
        _paintName(
          canvas,
          center,
          radius,
          start + sweep / 2,
          names[index],
          index == winnerIndex ? winnerTextColor : textColor,
          names.length,
        );
      }
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = borderColor,
    );
  }

  void _paintName(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    String name,
    Color color,
    int count,
  ) {
    final displayName = name.characters.length > 8
        ? '${name.characters.take(7)}…'
        : name;
    final painter = TextPainter(
      text: TextSpan(
        text: displayName,
        style: TextStyle(
          color: color,
          fontSize: count <= 8 ? 13 : 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      ellipsis: '…',
    )..layout(maxWidth: radius * 0.48);
    final position = Offset(
      center.dx + math.cos(angle) * radius * 0.67,
      center.dy + math.sin(angle) * radius * 0.67,
    );
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(angle + math.pi / 2);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RouletteWheelPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.winnerIndex != winnerIndex ||
      oldDelegate.names != names ||
      oldDelegate.colors != colors;
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter({required this.color, required this.borderColor});

  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(2, 3)
      ..quadraticBezierTo(1, 1, 5, 1)
      ..lineTo(size.width - 5, 1)
      ..quadraticBezierTo(size.width - 1, 1, size.width - 2, 3)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PointerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderColor != borderColor;
}
