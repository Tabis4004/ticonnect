import 'package:flutter/material.dart';

import '../core/theme.dart';

/// La marque Ticonnect, dessinée en vectoriel.
///
/// Tracée avec un `CustomPainter` plutôt que chargée depuis un SVG ou un PNG :
/// nette à toutes les tailles, aucun paquet supplémentaire, aucun asset à
/// embarquer. Les courbes sont identiques à `assets/brand/logo-mark.svg`.
class BrandMark extends StatelessWidget {
  final double size;

  /// Couleur du liseré qui sépare les deux lames. Doit correspondre au fond
  /// sur lequel la marque est posée — c'est lui qui rend l'entrelacement
  /// lisible, comme le noir du logo d'origine.
  final Color gap;

  final bool light;

  const BrandMark({
    super.key,
    this.size = 64,
    this.gap = Colors.white,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    // Rapport hauteur/largeur du tracé : 294 / 160.
    return SizedBox(
      width: size * 160 / 294,
      height: size,
      child: CustomPaint(painter: _MarkPainter(gap: gap, light: light)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color gap;
  final bool light;
  const _MarkPainter({required this.gap, required this.light});

  // Coordonnées d'origine du tracé, boîte utile x 40..200, y 12..306.
  static const _vbX = 40.0, _vbY = 12.0, _vbW = 160.0, _vbH = 294.0;

  Path get _greenBlade => Path()
    ..moveTo(108, 12)
    ..cubicTo(158, 74, 172, 132, 152, 178)
    ..cubicTo(134, 220, 92, 244, 44, 254)
    ..cubicTo(40, 196, 40, 138, 60, 92)
    ..cubicTo(74, 58, 88, 32, 108, 12)
    ..close();

  Path get _amberBlade => Path()
    ..moveTo(172, 118)
    ..cubicTo(200, 168, 204, 214, 186, 250)
    ..cubicTo(170, 282, 136, 300, 96, 306)
    ..cubicTo(92, 262, 96, 220, 114, 186)
    ..cubicTo(130, 156, 150, 132, 172, 118)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / _vbH;
    canvas.save();
    canvas.scale(scale);
    canvas.translate(-_vbX, -_vbY);

    const box = Rect.fromLTWH(_vbX, _vbY, _vbW, _vbH);

    final amber = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE08A22), Color(0xFFF2A03D)],
      ).createShader(box);

    final green = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: light
            ? const [Color(0xFF2E7A54), Color(0xFF4CAF7D)]
            : const [AppTheme.primaryDark, AppTheme.primary],
      ).createShader(box);

    final separator = Paint()
      ..color = gap
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(_amberBlade, amber);
    canvas.drawPath(_greenBlade, separator);
    canvas.drawPath(_greenBlade, green);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.gap != gap || old.light != light;
}
