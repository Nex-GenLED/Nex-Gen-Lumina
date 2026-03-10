import 'dart:math' show sqrt;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nexgen_command/app_colors.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION 1: ExploreDesignTokens
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class ExploreDesignTokens {
  ExploreDesignTokens._();

  // Colors
  static const Color backgroundBase = Color(0xFF0A0A0A);
  static const Color backgroundCard = Color(0x0FFFFFFF); // 6% white
  static const Color cardBorder = Color(0x1EFFFFFF); // 12% white
  static const Color cardBorderActive = Color(0x66FFFFFF);
  static const Color textPrimary = NexGenPalette.textHigh;
  static const Color textSecondary = Color(0xB3FFFFFF); // 70%
  static const Color textMuted = Color(0x66FFFFFF); // 40%
  static const Color accentBlue = Color(0xFF4FC3F7);
  static const Color accentPurple = Color(0xFF7B61FF);

  // Radii
  static const double cardRadius = 16.0;
  static const double buttonRadius = 12.0;
  static const double heroRadius = 20.0;

  // Sizes
  static const double buttonMinHeight = 56.0;

  // Spacing
  static const double cardPaddingH = 16.0;
  static const double cardPaddingV = 14.0;
  static const double cardSpacing = 12.0;
  static const double sectionSpacing = 28.0;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION 2: FolderTheme model + registry
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class FolderTheme {
  final List<Color> gradientColors; // always exactly 2
  final String emoji;
  final String? backgroundDescription;

  const FolderTheme({
    required this.gradientColors,
    required this.emoji,
    this.backgroundDescription,
  });
}

const Map<String, FolderTheme> kFolderThemes = {
  'holidays': FolderTheme(
    gradientColors: [Color(0xFFFF3B3B), Color(0xFF2ECC71)],
    emoji: '🎄',
  ),
  'game day fan zone': FolderTheme(
    gradientColors: [Color(0xFFFF6D00), Color(0xFF2979FF)],
    emoji: '🏆',
  ),
  'nature & outdoors': FolderTheme(
    gradientColors: [Color(0xFF43A047), Color(0xFF80DEEA)],
    emoji: '🌿',
  ),
  'security & alerts': FolderTheme(
    gradientColors: [Color(0xFFFF1744), Color(0xFFFF6F00)],
    emoji: '🔐',
  ),
  'parties & events': FolderTheme(
    gradientColors: [Color(0xFFE040FB), Color(0xFFFF4081)],
    emoji: '🎉',
  ),
  'seasonal vibes': FolderTheme(
    gradientColors: [Color(0xFFFFB300), Color(0xFFFF7043)],
    emoji: '🍂',
  ),
  'architectural white and downlighting': FolderTheme(
    gradientColors: [Color(0xFFE0E0E0), Color(0xFF90CAF9)],
    emoji: '🏛️',
  ),
  'movies & super heroes': FolderTheme(
    gradientColors: [Color(0xFF7B61FF), Color(0xFFFF4081)],
    emoji: '🎬',
  ),
  // ── Soccer sub-folder themes ────────────────────────────────────────────
  'soccer': FolderTheme(
    gradientColors: [Color(0xFF00D4FF), Color(0xFF0088AA)],
    emoji: '\u{26BD}',
  ),
  'mls': FolderTheme(
    gradientColors: [Color(0xFF005293), Color(0xFF003060)],
    emoji: '\u{26BD}',
  ),
  'premier league': FolderTheme(
    gradientColors: [Color(0xFF3D195B), Color(0xFF280E3B)],
    emoji: '\u{26BD}',
  ),
  'la liga': FolderTheme(
    gradientColors: [Color(0xFFFF6B35), Color(0xFFCC4400)],
    emoji: '\u{26BD}',
  ),
  'bundesliga': FolderTheme(
    gradientColors: [Color(0xFFD4020D), Color(0xFF8B0000)],
    emoji: '\u{26BD}',
  ),
  'serie a': FolderTheme(
    gradientColors: [Color(0xFF1B4FBB), Color(0xFF0D2D6B)],
    emoji: '\u{26BD}',
  ),
  'nwsl': FolderTheme(
    gradientColors: [Color(0xFF00A3AD), Color(0xFF006D75)],
    emoji: '\u{26BD}',
  ),
  'champions league': FolderTheme(
    gradientColors: [Color(0xFF0D47A1), Color(0xFF1A237E)],
    emoji: '\u{1F3C6}',
  ),
  'fifa world cup 2026': FolderTheme(
    gradientColors: [Color(0xFFD4AF37), Color(0xFF1565C0)],
    emoji: '\u{1F30D}',
  ),
  // ── NCAA folder themes ──────────────────────────────────────────────────
  'college football': FolderTheme(
    gradientColors: [Color(0xFFB71C1C), Color(0xFF8B0000)],
    emoji: '\u{1F3C8}',
  ),
  'college basketball': FolderTheme(
    gradientColors: [Color(0xFFFF8F00), Color(0xFFE65100)],
    emoji: '\u{1F3C0}',
  ),
};

const FolderTheme kDefaultFolderTheme = FolderTheme(
  gradientColors: [Color(0xFF4FC3F7), Color(0xFF7B61FF)],
  emoji: '✨',
);

FolderTheme getFolderTheme(String folderName) {
  return kFolderThemes[folderName.toLowerCase().trim()] ?? kDefaultFolderTheme;
}

FolderTheme resolveChildTheme(String childName, FolderTheme parentTheme) {
  final direct = kFolderThemes[childName.toLowerCase().trim()];
  if (direct != null) return direct;
  return FolderTheme(
    gradientColors: [
      parentTheme.gradientColors[0].withValues(alpha: 0.85),
      parentTheme.gradientColors[1].withValues(alpha: 0.85),
    ],
    emoji: parentTheme.emoji,
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION 3: Reusable widgets
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// ── Widget 1: LuminaGlassCard ──

class LuminaGlassCard extends StatefulWidget {
  final Widget child;
  final Color? glowColor;
  final double glowIntensity;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool animate;

  const LuminaGlassCard({
    super.key,
    required this.child,
    this.glowColor,
    this.glowIntensity = 0.22,
    this.borderRadius = 16.0,
    this.padding,
    this.onTap,
    this.animate = true,
  });

  @override
  State<LuminaGlassCard> createState() => _LuminaGlassCardState();
}

class _LuminaGlassCardState extends State<LuminaGlassCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _rippleController;
  Offset? _tapPosition;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final rippleColor =
        widget.glowColor ?? ExploreDesignTokens.accentBlue;

    Widget card = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          inner: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Container(
              padding: widget.padding,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x17FFFFFF), // ~9% white
                    Color(0x08FFFFFF), // ~3% white
                  ],
                ),
                border: Border.all(
                  color: ExploreDesignTokens.cardBorder,
                  width: 1.0,
                ),
                borderRadius: radius,
                boxShadow: widget.glowColor != null
                    ? [
                        BoxShadow(
                          color: widget.glowColor!
                              .withValues(alpha: widget.glowIntensity),
                          blurRadius: 22,
                          spreadRadius: 0,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: widget.child,
            ),
            // Radial ripple overlay
            if (widget.onTap != null && widget.animate)
              AnimatedBuilder(
                animation: _rippleController,
                builder: (context, _) {
                  if (_rippleController.value <= 0 ||
                      _tapPosition == null) {
                    return const SizedBox.shrink();
                  }
                  return Positioned.fill(
                    child: CustomPaint(
                      painter: _RippleGlowPainter(
                        center: _tapPosition!,
                        progress: _rippleController.value,
                        color: rippleColor,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );

    if (widget.onTap != null && widget.animate) {
      card = GestureDetector(
        onTapDown: (details) {
          setState(() => _pressed = true);
          _tapPosition = details.localPosition;
          _rippleController.forward(from: 0.0);
        },
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap!();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: card,
        ),
      );
    } else if (widget.onTap != null) {
      card = GestureDetector(onTap: widget.onTap, child: card);
    }

    return card;
  }
}

/// Paints a radial glow that expands outward from a tap point.
class _RippleGlowPainter extends CustomPainter {
  final Offset center;
  final double progress;
  final Color color;

  _RippleGlowPainter({
    required this.center,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final diagonal = sqrt(size.width * size.width + size.height * size.height);
    final currentRadius = diagonal * progress;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.20 * (1.0 - progress)),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(
          Rect.fromCircle(center: center, radius: currentRadius));
    canvas.drawCircle(center, currentRadius, paint);
  }

  @override
  bool shouldRepaint(_RippleGlowPainter old) =>
      old.progress != progress || old.center != center;
}

// ── Widget 2: LuminaGradientButton ──

class LuminaGradientButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final List<Color>? gradientColors;
  final IconData? icon;
  final bool isLoading;
  final double height;
  final bool fullWidth;

  const LuminaGradientButton({
    super.key,
    required this.label,
    this.onTap,
    this.gradientColors,
    this.icon,
    this.isLoading = false,
    this.height = 56.0,
    this.fullWidth = true,
  });

  @override
  State<LuminaGradientButton> createState() => _LuminaGradientButtonState();
}

class _LuminaGradientButtonState extends State<LuminaGradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.gradientColors ??
        [ExploreDesignTokens.accentBlue, ExploreDesignTokens.accentPurple];
    final effectiveHeight =
        widget.height < ExploreDesignTokens.buttonMinHeight
            ? ExploreDesignTokens.buttonMinHeight
            : widget.height;

    Widget button = Container(
      height: effectiveHeight,
      width: widget.fullWidth ? double.infinity : null,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(ExploreDesignTokens.buttonRadius),
        boxShadow: [
          BoxShadow(
            color: colors[0].withValues(alpha: 0.35),
            blurRadius: 18,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              BorderRadius.circular(ExploreDesignTokens.buttonRadius),
          onTap: widget.isLoading ? null : widget.onTap,
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: button,
      ),
    );
  }
}

// ── Widget 3: ColorSwatchDot ──

class ColorSwatchDot extends StatelessWidget {
  final Color color;
  final double size;

  const ColorSwatchDot({
    super.key,
    required this.color,
    this.size = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          width: 1,
          color: Colors.white.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.65),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }
}

// ── Widget 4: PatternColorStrip ──

class PatternColorStrip extends StatelessWidget {
  final List<Color> colors;
  final double height;

  const PatternColorStrip({
    super.key,
    required this.colors,
    this.height = 6.0,
  });

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: height,
      child: Row(
        children: List.generate(colors.length, (i) {
          BorderRadius? radius;
          if (colors.length == 1) {
            radius = BorderRadius.circular(height / 2);
          } else if (i == 0) {
            radius = BorderRadius.horizontal(
              left: Radius.circular(height / 2),
            );
          } else if (i == colors.length - 1) {
            radius = BorderRadius.horizontal(
              right: Radius.circular(height / 2),
            );
          }

          return Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors[i],
                borderRadius: radius,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Widget 5: SectionHeader ──

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: ExploreDesignTokens.textPrimary,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ExploreDesignTokens.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ── Widget 6: BreadcrumbTrail ──

class BreadcrumbTrail extends StatelessWidget {
  final List<String> crumbs;

  const BreadcrumbTrail({super.key, required this.crumbs});

  @override
  Widget build(BuildContext context) {
    if (crumbs.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < crumbs.length; i++) ...[
          if (i > 0)
            const Icon(
              Icons.chevron_right,
              size: 14,
              color: ExploreDesignTokens.textMuted,
            ),
          Flexible(
            child: Text(
              crumbs[i],
              style: TextStyle(
                fontSize: 11,
                color: i == crumbs.length - 1
                    ? ExploreDesignTokens.textSecondary
                    : ExploreDesignTokens.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Widget 7: LuminaShimmerCard ──

class LuminaShimmerCard extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const LuminaShimmerCard({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 16.0,
  });

  @override
  State<LuminaShimmerCard> createState() => _LuminaShimmerCardState();
}

class _LuminaShimmerCardState extends State<LuminaShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final translate = -widget.width + (_controller.value * 2 * widget.width);
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Color(0x08FFFFFF), // ~3% white
                  Color(0x17FFFFFF), // ~9% white
                  Color(0x08FFFFFF), // ~3% white
                ],
                stops: const [0.0, 0.5, 1.0],
                transform: _SlidingGradientTransform(translate),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double translateX;
  const _SlidingGradientTransform(this.translateX);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(translateX, 0.0, 0.0);
  }
}

// ── Widget 8: ExploreShimmerGrid ──

/// A grid of [LuminaShimmerCard] placeholders used as loading states.
class ExploreShimmerGrid extends StatelessWidget {
  final int crossAxisCount;
  final int itemCount;
  final double childAspectRatio;
  final double spacing;

  const ExploreShimmerGrid({
    super.key,
    this.crossAxisCount = 2,
    this.itemCount = 6,
    this.childAspectRatio = 0.85,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalSpacing = spacing * (crossAxisCount - 1);
          final cardWidth =
              (constraints.maxWidth - totalSpacing) / crossAxisCount;
          final cardHeight = cardWidth / childAspectRatio;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: List.generate(
              itemCount,
              (i) => LuminaShimmerCard(
                width: cardWidth,
                height: cardHeight,
              ),
            ),
          );
        },
      ),
    );
  }
}
