import 'dart:math';
import 'package:flutter/material.dart';
import 'wled_effects_catalog.dart';

/// Preview animation type derived from WLED effect category
enum EffectPreviewType {
  solid,
  breathe,
  wipe,
  chase,
  scanner,
  sparkle,
  meteor,
  fire,
  fireworks,
  ripple,
  rainbow,
  strobe,
  ambient,
  noise,
  popcorn,
  gradient,
}

/// Maps a WLED effect ID to its preview animation type
EffectPreviewType getPreviewType(int effectId) {
  // Look up in catalog by ID
  final effect = WledEffectsCatalog.allEffects.cast<WledEffect?>().firstWhere(
    (e) => e!.id == effectId,
    orElse: () => null,
  );

  if (effect == null) return EffectPreviewType.gradient;

  switch (effect.category) {
    case 'Basic':
      // Sub-classify basic effects
      if (effectId == 0 || effectId == 83 || effectId == 84 || effectId == 85 || effectId == 98) {
        return EffectPreviewType.solid;
      }
      if (effectId == 2 || effectId == 100) return EffectPreviewType.breathe;
      if (effectId == 12 || effectId == 18 || effectId == 56) return EffectPreviewType.breathe;
      if (effectId == 46) return EffectPreviewType.gradient;
      if (effectId == 1 || effectId == 62) return EffectPreviewType.strobe;
      return EffectPreviewType.gradient;
    case 'Wipe':
      return EffectPreviewType.wipe;
    case 'Chase':
      return EffectPreviewType.chase;
    case 'Scanner':
      return EffectPreviewType.scanner;
    case 'Sparkle':
      return EffectPreviewType.sparkle;
    case 'Meteor':
      return EffectPreviewType.meteor;
    case 'Fire':
      return EffectPreviewType.fire;
    case 'Fireworks':
      return EffectPreviewType.fireworks;
    case 'Ripple':
      return EffectPreviewType.ripple;
    case 'Rainbow':
      return EffectPreviewType.rainbow;
    case 'Strobe':
      return EffectPreviewType.strobe;
    case 'Ambient':
      return EffectPreviewType.ambient;
    case 'Noise':
      return EffectPreviewType.noise;
    case 'Game':
      if (effectId == 95) return EffectPreviewType.popcorn; // Popcorn
      if (effectId == 91) return EffectPreviewType.popcorn; // Bouncing Balls
      return EffectPreviewType.chase;
    default:
      return EffectPreviewType.gradient;
  }
}

/// Animated effect preview that shows a subtle representation of what
/// the WLED effect looks like using the pattern's actual colors.
class EffectPreviewWidget extends StatefulWidget {
  final int effectId;
  final List<Color> colors;
  final double borderRadius;

  const EffectPreviewWidget({
    super.key,
    required this.effectId,
    required this.colors,
    this.borderRadius = 12,
  });

  @override
  State<EffectPreviewWidget> createState() => _EffectPreviewWidgetState();
}

class _EffectPreviewWidgetState extends State<EffectPreviewWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late EffectPreviewType _previewType;

  Color get primary =>
      widget.colors.isNotEmpty ? widget.colors[0] : Colors.white;

  Color get secondary => widget.colors.length > 1
      ? widget.colors[1]
      : primary.withValues(alpha: 0.6);

  Color get tertiary => widget.colors.length > 2 ? widget.colors[2] : secondary;

  @override
  void initState() {
    super.initState();
    _previewType = getPreviewType(widget.effectId);

    if (_previewType == EffectPreviewType.solid ||
        _previewType == EffectPreviewType.gradient) {
      // No animation needed for static effects
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 1),
      );
      return;
    }

    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(_previewType),
    )..repeat(reverse: _shouldReverse(_previewType));
  }

  Duration _durationFor(EffectPreviewType type) {
    switch (type) {
      case EffectPreviewType.breathe:
        return const Duration(milliseconds: 2400);
      case EffectPreviewType.wipe:
        return const Duration(milliseconds: 2200);
      case EffectPreviewType.chase:
        return const Duration(milliseconds: 1800);
      case EffectPreviewType.scanner:
        return const Duration(milliseconds: 1600);
      case EffectPreviewType.sparkle:
        return const Duration(milliseconds: 900);
      case EffectPreviewType.meteor:
        return const Duration(milliseconds: 1400);
      case EffectPreviewType.fire:
        return const Duration(milliseconds: 700);
      case EffectPreviewType.fireworks:
        return const Duration(milliseconds: 1500);
      case EffectPreviewType.ripple:
        return const Duration(milliseconds: 2000);
      case EffectPreviewType.rainbow:
        return const Duration(milliseconds: 3000);
      case EffectPreviewType.strobe:
        return const Duration(milliseconds: 500);
      case EffectPreviewType.ambient:
        return const Duration(milliseconds: 3000);
      case EffectPreviewType.noise:
        return const Duration(milliseconds: 2500);
      case EffectPreviewType.popcorn:
        return const Duration(milliseconds: 1200);
      default:
        return const Duration(seconds: 1);
    }
  }

  bool _shouldReverse(EffectPreviewType type) {
    switch (type) {
      case EffectPreviewType.breathe:
      case EffectPreviewType.fire:
      case EffectPreviewType.scanner:
      case EffectPreviewType.ambient:
      case EffectPreviewType.noise:
        return true;
      default:
        return false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(widget.borderRadius),
        topRight: Radius.circular(widget.borderRadius),
      ),
      child: _buildPreview(),
    );
  }

  Widget _buildPreview() {
    switch (_previewType) {
      case EffectPreviewType.solid:
        return _SolidPreview(color: primary);
      case EffectPreviewType.gradient:
        return _GradientPreview(colors: widget.colors);
      case EffectPreviewType.breathe:
        return _AnimatedPreview(
          animation: _controller,
          painter: _BreathePainter(
            progress: 0,
            primary: primary,
            secondary: secondary,
          ),
          painterBuilder: (progress) => _BreathePainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
          ),
        );
      case EffectPreviewType.wipe:
        return _AnimatedPreview(
          animation: _controller,
          painter: _WipePainter(progress: 0, primary: primary, secondary: secondary, tertiary: tertiary),
          painterBuilder: (progress) => _WipePainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
          ),
        );
      case EffectPreviewType.chase:
        return _AnimatedPreview(
          animation: _controller,
          painter: _ChasePainter(progress: 0, primary: primary, secondary: secondary),
          painterBuilder: (progress) => _ChasePainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
          ),
        );
      case EffectPreviewType.scanner:
        return _AnimatedPreview(
          animation: _controller,
          painter: _ScannerPainter(progress: 0, primary: primary, secondary: secondary),
          painterBuilder: (progress) => _ScannerPainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
          ),
        );
      case EffectPreviewType.sparkle:
        return _AnimatedPreview(
          animation: _controller,
          painter: _SparklePainter(progress: 0, primary: primary, secondary: secondary, tertiary: tertiary),
          painterBuilder: (progress) => _SparklePainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
          ),
          background: primary.withValues(alpha: 0.5),
        );
      case EffectPreviewType.meteor:
        return _AnimatedPreview(
          animation: _controller,
          painter: _MeteorPainter(progress: 0, primary: primary, secondary: secondary),
          painterBuilder: (progress) => _MeteorPainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
          ),
        );
      case EffectPreviewType.fire:
        return _AnimatedPreview(
          animation: _controller,
          painter: _FirePainter(progress: 0, primary: primary, secondary: secondary),
          painterBuilder: (progress) => _FirePainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
          ),
        );
      case EffectPreviewType.fireworks:
        return _AnimatedPreview(
          animation: _controller,
          painter: _FireworksPainter(progress: 0, primary: primary, secondary: secondary, tertiary: tertiary),
          painterBuilder: (progress) => _FireworksPainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
          ),
        );
      case EffectPreviewType.ripple:
        return _AnimatedPreview(
          animation: _controller,
          painter: _RipplePainter(progress: 0, primary: primary, secondary: secondary),
          painterBuilder: (progress) => _RipplePainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
          ),
        );
      case EffectPreviewType.rainbow:
        return _AnimatedPreview(
          animation: _controller,
          painter: _RainbowPainter(progress: 0, colors: widget.colors),
          painterBuilder: (progress) => _RainbowPainter(
            progress: progress,
            colors: widget.colors,
          ),
        );
      case EffectPreviewType.strobe:
        return _AnimatedPreview(
          animation: _controller,
          painter: _StrobePainter(progress: 0, primary: primary, secondary: secondary),
          painterBuilder: (progress) => _StrobePainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
          ),
        );
      case EffectPreviewType.ambient:
        return _AnimatedPreview(
          animation: _controller,
          painter: _AmbientPainter(progress: 0, primary: primary, secondary: secondary, tertiary: tertiary),
          painterBuilder: (progress) => _AmbientPainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
          ),
        );
      case EffectPreviewType.noise:
        return _AnimatedPreview(
          animation: _controller,
          painter: _NoisePainter(progress: 0, primary: primary, secondary: secondary),
          painterBuilder: (progress) => _NoisePainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
          ),
        );
      case EffectPreviewType.popcorn:
        return _AnimatedPreview(
          animation: _controller,
          painter: _PopcornPainter(progress: 0, primary: primary, secondary: secondary, tertiary: tertiary),
          painterBuilder: (progress) => _PopcornPainter(
            progress: progress,
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
          ),
          background: primary,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Static previews
// ─────────────────────────────────────────────────────────────────────────────

class _SolidPreview extends StatelessWidget {
  final Color color;
  const _SolidPreview({required this.color});

  @override
  Widget build(BuildContext context) => Container(color: color);
}

class _GradientPreview extends StatelessWidget {
  final List<Color> colors;
  const _GradientPreview({required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors.length >= 2
        ? colors.take(3).toList()
        : [colors.first, colors.first.withValues(alpha: 0.5)];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: c,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated preview wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedPreview extends StatelessWidget {
  final Animation<double> animation;
  final CustomPainter painter;
  final CustomPainter Function(double progress) painterBuilder;
  final Color? background;

  const _AnimatedPreview({
    required this.animation,
    required this.painter,
    required this.painterBuilder,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return CustomPaint(
          painter: painterBuilder(animation.value),
          child: background != null ? Container(color: background) : null,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painters for each effect type
// ─────────────────────────────────────────────────────────────────────────────

/// Breathe – gentle pulse, primary fades in/out with soft radial glow
class _BreathePainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;

  _BreathePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final intensity = 0.35 + (progress * 0.65);

    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 0.7 + (progress * 0.3),
      colors: [
        primary.withValues(alpha: intensity),
        secondary.withValues(alpha: intensity * 0.4),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_BreathePainter old) => progress != old.progress;
}

/// Wipe – primary sweeps across revealing secondary/tertiary behind
class _WipePainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final Color tertiary;

  _WipePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background is tertiary
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = tertiary.withValues(alpha: 0.5),
    );

    // Secondary band behind primary wipe
    final secondaryEdge = (progress * size.width).clamp(0.0, size.width);
    if (secondaryEdge > 0) {
      final bandWidth = size.width * 0.12;
      final bandStart = (secondaryEdge - bandWidth).clamp(0.0, size.width);
      canvas.drawRect(
        Rect.fromLTWH(bandStart, 0, bandWidth, size.height),
        Paint()..color = secondary,
      );
    }

    // Primary sweeps from left
    canvas.drawRect(
      Rect.fromLTWH(0, 0, secondaryEdge, size.height),
      Paint()..color = primary,
    );
  }

  @override
  bool shouldRepaint(_WipePainter old) => progress != old.progress;
}

/// Chase – small lit segments moving across a dim background
class _ChasePainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;

  _ChasePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dim background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = primary.withValues(alpha: 0.15),
    );

    final segmentCount = 7;
    final segmentW = size.width / segmentCount;
    // 3 lit segments chasing
    for (var i = 0; i < 3; i++) {
      final offset = (progress * segmentCount + i * 2.3) % segmentCount;
      final x = offset * segmentW;
      final color = i == 0 ? primary : secondary;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, segmentW * 0.6, size.height),
        Paint()..color = color.withValues(alpha: 0.9 - (i * 0.2)),
      );
    }
  }

  @override
  bool shouldRepaint(_ChasePainter old) => progress != old.progress;
}

/// Scanner – beam sweeps back and forth
class _ScannerPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;

  _ScannerPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = secondary.withValues(alpha: 0.12),
    );

    final beamWidth = size.width * 0.2;
    final beamX = progress * (size.width - beamWidth);

    // Beam glow
    final rect = Rect.fromLTWH(beamX - beamWidth * 0.3, 0, beamWidth * 1.6, size.height);
    final gradient = LinearGradient(
      colors: [
        primary.withValues(alpha: 0.0),
        primary.withValues(alpha: 0.5),
        primary,
        primary.withValues(alpha: 0.5),
        primary.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_ScannerPainter old) => progress != old.progress;
}

/// Sparkle – random twinkles over a dim primary fill
class _SparklePainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final Color tertiary;

  _SparklePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Deterministic sparkle positions
    final spots = [
      (0.18, 0.25),
      (0.65, 0.15),
      (0.42, 0.55),
      (0.82, 0.65),
      (0.28, 0.80),
      (0.55, 0.35),
      (0.90, 0.40),
    ];

    final colors = [secondary, tertiary, secondary, tertiary, secondary, tertiary, secondary];

    for (var i = 0; i < spots.length; i++) {
      // Stagger each sparkle with a different phase
      final phase = (progress + (i * 0.143)) % 1.0;
      // Sharp on-off twinkle
      final alpha = (phase < 0.3) ? (phase / 0.3) : (phase < 0.4 ? 1.0 : max(0.0, 1.0 - ((phase - 0.4) / 0.2)));
      if (alpha <= 0) continue;

      final x = spots[i].$1 * size.width;
      final y = spots[i].$2 * size.height;
      final r = 2.0 + (alpha * 3.5);

      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = colors[i].withValues(alpha: alpha.clamp(0.0, 1.0) * 0.95),
      );
      // Glow
      canvas.drawCircle(
        Offset(x, y),
        r * 2,
        Paint()..color = colors[i].withValues(alpha: alpha.clamp(0.0, 1.0) * 0.2),
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => progress != old.progress;
}

/// Meteor – bright head with fading trail moving across
class _MeteorPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;

  _MeteorPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = secondary.withValues(alpha: 0.08),
    );

    final headX = progress * size.width * 1.3 - size.width * 0.15;
    final tailLength = size.width * 0.4;
    final y = size.height * 0.5;

    // Trail
    for (var i = 0; i < 8; i++) {
      final t = i / 8.0;
      final x = headX - (t * tailLength);
      if (x < 0 || x > size.width) continue;
      final r = 3.5 * (1.0 - t * 0.7);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = primary.withValues(alpha: (1.0 - t) * 0.7),
      );
    }

    // Bright head
    if (headX >= 0 && headX <= size.width) {
      canvas.drawCircle(Offset(headX, y), 4.5, Paint()..color = primary);
      canvas.drawCircle(
        Offset(headX, y),
        8,
        Paint()..color = primary.withValues(alpha: 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(_MeteorPainter old) => progress != old.progress;
}

/// Fire – flickering warm gradient from bottom
class _FirePainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;

  _FirePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final flicker = 0.65 + (progress * 0.35);

    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        primary.withValues(alpha: flicker),
        secondary.withValues(alpha: flicker * 0.6),
        Colors.black.withValues(alpha: 0.25),
      ],
      stops: const [0.0, 0.55, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));

    // Subtle flame tips
    final count = 4;
    final w = size.width / count;
    for (var i = 0; i < count; i++) {
      final cx = (i + 0.5) * w;
      final vary = (i.isEven ? progress : 1.0 - progress);
      final tipY = size.height * (0.22 + vary * 0.12);
      final path = Path()
        ..moveTo(cx - w * 0.25, size.height * 0.6)
        ..quadraticBezierTo(cx, tipY, cx + w * 0.25, size.height * 0.6);
      canvas.drawPath(
        path,
        Paint()
          ..color = primary.withValues(alpha: 0.45)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_FirePainter old) => progress != old.progress;
}

/// Fireworks – bursts that expand and fade
class _FireworksPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final Color tertiary;

  _FireworksPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    final bursts = [
      (0.3, 0.35, 0.0, primary),
      (0.7, 0.45, 0.35, secondary),
      (0.5, 0.25, 0.65, tertiary),
    ];

    for (final (bx, by, delay, color) in bursts) {
      final t = ((progress + (1 - delay)) % 1.0);
      if (t < 0.15) continue; // Fuse delay
      final burstProgress = ((t - 0.15) / 0.85).clamp(0.0, 1.0);
      final radius = burstProgress * size.width * 0.28;
      final alpha = (1.0 - burstProgress).clamp(0.0, 1.0);

      final cx = bx * size.width;
      final cy = by * size.height;

      // Rays
      for (var r = 0; r < 6; r++) {
        final angle = (r / 6.0) * 2 * pi;
        final ex = cx + cos(angle) * radius;
        final ey = cy + sin(angle) * radius;
        canvas.drawLine(
          Offset(cx, cy),
          Offset(ex, ey),
          Paint()
            ..color = color.withValues(alpha: alpha * 0.6)
            ..strokeWidth = 1.5,
        );
        // Dot at end
        canvas.drawCircle(
          Offset(ex, ey),
          2,
          Paint()..color = color.withValues(alpha: alpha * 0.9),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter old) => progress != old.progress;
}

/// Ripple – concentric rings expanding from center
class _RipplePainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;

  _RipplePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = secondary.withValues(alpha: 0.15),
    );

    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = size.width * 0.5;

    for (var i = 0; i < 3; i++) {
      final phase = (progress + i * 0.33) % 1.0;
      final radius = phase * maxR;
      final alpha = (1.0 - phase).clamp(0.0, 1.0);

      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..color = primary.withValues(alpha: alpha * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => progress != old.progress;
}

/// Rainbow – smooth color band scrolling horizontally
class _RainbowPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;

  _RainbowPainter({required this.progress, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final c = colors.length >= 3
        ? colors
        : [Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple];

    // Shift colors
    final shifted = <Color>[];
    final shift = (progress * c.length).floor();
    for (var i = 0; i < c.length; i++) {
      shifted.add(c[(i + shift) % c.length]);
    }

    final gradient = LinearGradient(colors: shifted);
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_RainbowPainter old) => progress != old.progress;
}

/// Strobe – sharp on/off flash
class _StrobePainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;

  _StrobePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // On for first half, off for second half
    final on = progress < 0.5;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = on ? primary : secondary.withValues(alpha: 0.15),
    );
  }

  @override
  bool shouldRepaint(_StrobePainter old) => progress != old.progress;
}

/// Ambient – slow drifting blended glow
class _AmbientPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final Color tertiary;

  _AmbientPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Slowly shifting gradient angle
    final angle = progress * pi;
    final begin = Alignment(cos(angle), sin(angle));
    final end = Alignment(-cos(angle), -sin(angle));

    final gradient = LinearGradient(
      begin: begin,
      end: end,
      colors: [
        primary.withValues(alpha: 0.8),
        secondary.withValues(alpha: 0.6),
        tertiary.withValues(alpha: 0.5),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => progress != old.progress;
}

/// Noise – shifting color patches
class _NoisePainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;

  _NoisePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Two overlapping radial gradients that drift
    final cx1 = 0.3 + progress * 0.4;
    final cy1 = 0.3 + progress * 0.2;
    final g1 = RadialGradient(
      center: Alignment(cx1 * 2 - 1, cy1 * 2 - 1),
      radius: 0.8,
      colors: [primary.withValues(alpha: 0.7), Colors.transparent],
    );
    canvas.drawRect(rect, Paint()..shader = g1.createShader(rect));

    final cx2 = 0.7 - progress * 0.3;
    final cy2 = 0.6 - progress * 0.2;
    final g2 = RadialGradient(
      center: Alignment(cx2 * 2 - 1, cy2 * 2 - 1),
      radius: 0.6,
      colors: [secondary.withValues(alpha: 0.6), Colors.transparent],
    );
    canvas.drawRect(rect, Paint()..shader = g2.createShader(rect));
  }

  @override
  bool shouldRepaint(_NoisePainter old) => progress != old.progress;
}

/// Popcorn – circles pop up from bottom and fade
class _PopcornPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final Color tertiary;

  _PopcornPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pops = [
      (x: 0.20, delay: 0.00),
      (x: 0.50, delay: 0.25),
      (x: 0.80, delay: 0.50),
      (x: 0.35, delay: 0.70),
    ];
    final colors = [secondary, tertiary, secondary, tertiary];

    for (var i = 0; i < pops.length; i++) {
      final t = ((progress + (1 - pops[i].delay)) % 1.0);

      if (t < 0.65) {
        // Rising
        final rise = t / 0.65;
        final x = pops[i].x * size.width;
        final y = size.height - (rise * size.height * 0.75);
        final r = 3.0 + rise * 4.0;
        final a = 0.3 + rise * 0.7;
        canvas.drawCircle(
          Offset(x, y), r,
          Paint()..color = colors[i].withValues(alpha: a),
        );
      } else {
        // Fading
        final fade = (t - 0.65) / 0.35;
        final x = pops[i].x * size.width;
        final y = size.height * 0.25;
        final r = 7.0 - fade * 4.0;
        final a = 1.0 - fade;
        canvas.drawCircle(
          Offset(x, y), r,
          Paint()..color = colors[i].withValues(alpha: a),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PopcornPainter old) => progress != old.progress;
}
