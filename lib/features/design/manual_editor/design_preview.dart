import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/design_frame.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/roofline_light_painter.dart';

/// Design Studio Slice 4 (1b) — the ONE mode-agnostic preview both studio modes
/// render on. It takes a per-LED color [frame] and paints it on the house photo
/// via [RooflineLightPainter]'s real-index mode WHENEVER the active controller
/// has a roofline trace + photo. When there's no trace/photo it degrades to a
/// horizontal LED strip. AI designs and manual paint are just two producers of
/// the [frame] — neither renders a strip when a trace exists.
class DesignPreview extends ConsumerWidget {
  const DesignPreview({super.key, required this.frame, this.height = 200});

  final DesignFrame frame;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(currentRooflineConfigProvider).valueOrNull;
    final photo = ref.watch(houseImageUrlProvider);
    final traced = config != null &&
        config.segments.any((s) => s.points.length >= 2);

    if (traced && photo != null) {
      return _HousePreview(
          config: config, frame: frame, photoUrl: photo, height: height);
    }
    return _StripPreview(frame: frame, height: height);
  }
}

class _HousePreview extends StatelessWidget {
  const _HousePreview({
    required this.config,
    required this.frame,
    required this.photoUrl,
    required this.height,
  });

  final RooflineConfiguration config;
  final DesignFrame frame;
  final String photoUrl;
  final double height;

  Color? _tintFor(RooflineSegment s) {
    if (s.type == SegmentType.peak ||
        s.architecturalRole == ArchitecturalRole.peak) {
      return const Color(0xFFFFAA00);
    }
    if (s.type == SegmentType.corner ||
        s.architecturalRole == ArchitecturalRole.corner) {
      return NexGenPalette.cyan;
    }
    return null;
  }

  List<Color> _ledColorsFor(RooflineSegment s) {
    final chColors = frame[s.channelIndex];
    if (chColors == null) return const [];
    return [
      for (int i = s.startPixel; i <= s.endPixel && i < chColors.length; i++)
        chColors[i],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, constraints) {
        final aspect = constraints.maxWidth / constraints.maxHeight;
        final segmentPaths = [
          for (final s in config.segments)
            if (s.points.length >= 2)
              SegmentPathData(
                points: s.points,
                channelIndex: s.channelIndex,
                pixelCount: s.pixelCount,
                ledColors: _ledColorsFor(s),
                featureTint: _tintFor(s),
              ),
        ];
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _photo(photoUrl),
              Container(color: Colors.black.withValues(alpha: 0.15)),
              Positioned.fill(
                child: CustomPaint(
                  painter: RooflineLightPainter(
                    colors: const [Colors.white],
                    segmentPaths: segmentPaths,
                    realIndexMode: true,
                    useBoxFitCover: true,
                    targetAspectRatio: aspect,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _photo(String url) {
    if (url.startsWith('http')) {
      return Image.network(url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Image.asset('assets/images/Demohomephoto.jpg', fit: BoxFit.cover));
    }
    return Image.asset(url.isEmpty ? 'assets/images/Demohomephoto.jpg' : url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Container(color: NexGenPalette.matteBlack));
  }
}

/// Trace-less fallback — a single horizontal LED strip in channel order.
class _StripPreview extends StatelessWidget {
  const _StripPreview({required this.frame, required this.height});
  final DesignFrame frame;
  final double height;

  @override
  Widget build(BuildContext context) {
    final channels = frame.keys.toList()..sort();
    final leds = <Color>[for (final ch in channels) ...frame[ch] ?? const []];
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      alignment: Alignment.center,
      child: leds.isEmpty
          ? const Text('No pixels',
              style: TextStyle(color: NexGenPalette.textMedium))
          : LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - 16) / leds.length;
              return Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    for (final color in leds)
                      Container(
                        width: w.clamp(1.0, 12.0),
                        height: 22,
                        margin: const EdgeInsets.symmetric(horizontal: 0.3),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: color.computeLuminance() > 0.05
                              ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4)]
                              : null,
                        ),
                      ),
                  ],
                ),
              );
            }),
    );
  }
}
