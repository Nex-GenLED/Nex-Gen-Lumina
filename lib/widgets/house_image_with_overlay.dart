import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/models/roofline_mask.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/utils/sky_darkness_provider.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';

/// Composite widget that displays a house image with animated roofline LED overlay.
///
/// Features:
/// - Displays user's house photo or stock demo image
/// - Animated LED effects on roofline area
/// - Preview mode badge for AI suggestions
/// - Gradient vignette for UI legibility
/// - Optional "add photo" button when no custom image
/// - Dynamic sky darkening based on time of day (day/night simulation)
class HouseImageWithOverlay extends ConsumerWidget {
  /// URL of the house image (null uses stock image)
  final String? imageUrl;

  /// Whether the lights are on
  final bool isOn;

  /// LED colors to display
  final List<Color> colors;

  /// WLED effect ID
  final int effectId;

  /// Animation speed (0-255)
  final int speed;

  /// Brightness level (0-255)
  final int brightness;

  /// Custom roofline mask
  final RooflineMask? mask;

  /// Whether this is showing a preview (shows badge)
  final bool showPreviewBadge;

  /// Callback when user taps "add photo" button
  final VoidCallback? onAddPhotoTap;

  /// Whether to show the add photo button when no custom image
  final bool showAddPhotoButton;

  /// Fixed height for the widget
  final double? height;

  /// Box fit for the image
  final BoxFit fit;

  /// Whether to apply dynamic sky darkening based on time of day.
  /// When true, the sky portion of the image will darken at night
  /// and show warm tones during golden hour (sunrise/sunset).
  final bool enableSkyDarkening;

  const HouseImageWithOverlay({
    super.key,
    this.imageUrl,
    this.isOn = true,
    this.colors = const [],
    this.effectId = 0,
    this.speed = 128,
    this.brightness = 255,
    this.mask,
    this.showPreviewBadge = false,
    this.onAddPhotoTap,
    this.showAddPhotoButton = false,
    this.height,
    this.fit = BoxFit.cover,
    this.enableSkyDarkening = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Check if we're in AR preview mode
    final isPreviewMode = ref.watch(isPreviewModeProvider) || showPreviewBadge;

    // Get sky darkness level for time-based rendering
    final skyDarkness = enableSkyDarkening ? ref.watch(currentSkyDarknessProvider) : 0.0;
    final skyTintColor = enableSkyDarkening ? ref.watch(skyTintColorProvider) : Colors.transparent;

    // Determine the image to show
    final hasCustomImage = imageUrl != null && imageUrl!.isNotEmpty;
    final useStock = ref.watch(useStockImageProvider);

    ImageProvider imageProvider;
    if (hasCustomImage && !useStock) {
      imageProvider = NetworkImage(imageUrl!);
    } else {
      imageProvider = const AssetImage('assets/images/Demohomephoto.jpg');
    }

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: House image
            Image(
              image: imageProvider,
              fit: fit,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                // Fallback to stock image on error
                return Image.asset(
                  'assets/images/Demohomephoto.jpg',
                  fit: fit,
                  alignment: Alignment.center,
                );
              },
            ),

            // Layer 2: Sky darkening overlay (time-based)
            // This darkens primarily the upper portion (sky) of the image
            if (enableSkyDarkening && skyDarkness > 0.05)
              Positioned.fill(
                child: _SkyDarkeningOverlay(
                  darkness: skyDarkness,
                  tintColor: skyTintColor,
                ),
              ),

            // Layer 3: Gradient vignette for legibility
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Layer 4: Animated roofline overlay (only when on)
            if (isOn && colors.isNotEmpty)
              Positioned.fill(
                child: AnimatedRooflineOverlay(
                  previewColors: colors,
                  previewEffectId: effectId,
                  previewSpeed: speed,
                  mask: mask,
                  forceOn: isOn,
                  brightness: brightness,
                ),
              ),

            // Layer 5: Preview mode badge
            if (isPreviewMode)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: NexGenPalette.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        'Previewing on your home',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Layer 6: Add photo button (when no custom image and enabled)
            if (showAddPhotoButton && !hasCustomImage)
              Positioned(
                top: 12,
                right: 12,
                child: _AddPhotoButton(onTap: onAddPhotoTap),
              ),
          ],
        ),
      ),
    );
  }
}

/// Floating "add photo" button for the house image
class _AddPhotoButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _AddPhotoButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: NexGenPalette.cyan.withValues(alpha: 0.4),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_a_photo, size: 18, color: Colors.black),
              const SizedBox(width: 6),
              Text(
                'Add Photo',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simplified version for Lumina chat with just preview colors
class LuminaHouseHero extends ConsumerWidget {
  final double height;
  final List<Color> overlayColors;
  final int? effectId;
  final int? speed;

  const LuminaHouseHero({
    super.key,
    required this.height,
    required this.overlayColors,
    this.effectId,
    this.speed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageUrl = ref.watch(houseImageUrlProvider);
    final hasOverlay = overlayColors.isNotEmpty;

    return HouseImageWithOverlay(
      imageUrl: imageUrl,
      height: height,
      isOn: hasOverlay,
      colors: overlayColors,
      effectId: effectId ?? 0,
      speed: speed ?? 128,
      brightness: 255,
      showPreviewBadge: hasOverlay,
      fit: BoxFit.contain,
    );
  }
}

/// Overlay widget that darkens the sky portion of the house image
/// based on the current time of day.
///
/// Uses a gradient that primarily affects the upper portion of the image
/// (where the sky typically is) while leaving the lower portion (house)
/// less affected to maintain visibility of lighting effects.
class _SkyDarkeningOverlay extends StatelessWidget {
  /// Darkness level from 0.0 (full daylight) to 1.0 (full night)
  final double darkness;

  /// Optional color tint to apply (warm for golden hour, blue for night)
  final Color tintColor;

  const _SkyDarkeningOverlay({
    required this.darkness,
    required this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate the darkness intensity for different parts of the image
    // Sky (top) gets more darkness, house (bottom) gets less
    final skyDarknessAlpha = (darkness * 0.7).clamp(0.0, 0.7); // Max 70% dark at night
    final houseDarknessAlpha = (darkness * 0.3).clamp(0.0, 0.3); // Max 30% dark on house

    return Stack(
      fit: StackFit.expand,
      children: [
        // Primary darkness gradient (top-heavy for sky)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.35, 0.65, 1.0],
              colors: [
                Colors.black.withValues(alpha: skyDarknessAlpha),
                Colors.black.withValues(alpha: skyDarknessAlpha * 0.7),
                Colors.black.withValues(alpha: houseDarknessAlpha * 0.5),
                Colors.black.withValues(alpha: houseDarknessAlpha * 0.3),
              ],
            ),
          ),
        ),
        // Color tint overlay (warm for golden hour, blue for night)
        if (tintColor != Colors.transparent)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.5, 1.0],
                colors: [
                  tintColor,
                  tintColor.withValues(alpha: (tintColor.a * 0.5)),
                  Colors.transparent,
                ],
              ),
            ),
          ),
      ],
    );
  }
}
