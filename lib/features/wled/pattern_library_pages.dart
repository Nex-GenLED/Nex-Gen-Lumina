import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/mock_pattern_repository.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/models/smart_pattern.dart';
import 'package:nexgen_command/features/patterns/pattern_generator_service.dart';
import 'package:nexgen_command/features/patterns/color_sequence_builder.dart';
import 'package:nexgen_command/features/patterns/canonical_palettes.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/widgets/color_behavior_badge.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

/// Explore screen with Simulated AI search logic
class ExplorePatternsScreen extends ConsumerStatefulWidget {
  const ExplorePatternsScreen({super.key});

  @override
  ConsumerState<ExplorePatternsScreen> createState() => _ExplorePatternsScreenState();
}

class _ExplorePatternsScreenState extends ConsumerState<ExplorePatternsScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _hasSearched = false;
  // When searching, we now surface concrete SmartPattern variations (one per effect)
  List<SmartPattern> _filteredSmart = const [];
  // Track current query and style for refinement chips
  String _currentQuery = '';
  ThemeStyle _currentStyle = ThemeStyle.classic;
  // Track if the current search matched a canonical theme
  bool _hasCanonicalMatch = false;


  Future<void> _handleSearch(String raw, {ThemeStyle style = ThemeStyle.classic}) async {
    final query = raw.trim();
    debugPrint('ExplorePatternsScreen: _handleSearch called with query="$query"');
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _hasSearched = false; // Show default categories when empty
        _filteredSmart = const [];
        _currentQuery = '';
        _hasCanonicalMatch = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _currentQuery = query;
      _currentStyle = style;
    });

    try {
      // Brief delay for smoother UX (debounce handles most of the wait)
      await Future.delayed(const Duration(milliseconds: 300));
      // Generate multiple variations (one per popular WLED effect) for the query
      final generator = PatternGenerator();
      debugPrint('ExplorePatternsScreen: Calling generatePatterns for "$query"');
      final variations = generator.generatePatterns(query, style: style);
      debugPrint('ExplorePatternsScreen: generatePatterns returned ${variations.length} patterns');
      // Check if we matched a canonical theme
      final hasCanonical = CanonicalPalettes.findTheme(query) != null;
      debugPrint('ExplorePatternsScreen: hasCanonical=$hasCanonical');
      setState(() {
        _filteredSmart = variations;
        _isSearching = false;
        _hasCanonicalMatch = hasCanonical;
      });
    } catch (e, stackTrace) {
      debugPrint('Simulated AI search failed: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() {
        _filteredSmart = const [];
        _isSearching = false;
        _hasCanonicalMatch = false;
      });
    }
  }

  void _handleStyleChange(ThemeStyle style) {
    if (_currentQuery.isNotEmpty) {
      _handleSearch(_currentQuery, style: style);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch personalized recommendations and user profile for greeting
    final recs = ref.watch(recommendedPatternsProvider);
    // Load public predefined pattern lists from provider
    final library = ref.watch(publicPatternLibraryProvider);
    final profileAsync = ref.watch(currentUserProfileProvider);
    String _greetingTitle() {
      // Default title
      const fallback = 'Recommended for You';
      final profile = profileAsync.maybeWhen(data: (u) => u, orElse: () => null);
      if (profile == null) return fallback;
      final name = profile.displayName.trim();
      if (name.isEmpty) return fallback;
      // Use evening greeting when appropriate, otherwise fallback label
      final hour = DateTime.now().hour;
      if (hour >= 17 || hour < 5) {
        final first = name.split(' ').first;
        return 'Good Evening, $first';
      }
      return fallback;
    }

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Explore Patterns'),
        actions: [
          IconButton(
            onPressed: () => context.push('/my-scenes'),
            icon: const Icon(Icons.layers_outlined),
            tooltip: 'My Scenes',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _pagePadding(
            child: _LuminaAISearchBar(
              controller: _searchController,
              onSubmitted: _handleSearch,
              onClear: () => _handleSearch(''),
            ),
          ),
          const SizedBox(height: 16),
          // Conditional rendering per simulated AI state
          if (_isSearching)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(height: 12),
                  Text('Lumina is generating suggestions...', style: Theme.of(context).textTheme.bodyLarge),
                ]),
              ),
            )
          else if (_hasSearched)
            Expanded(
              child: _filteredSmart.isEmpty
                  ? Center(
                      child: Text(
                        "No specific AI matches found. Try 'Holiday' or 'Sports'.",
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Style variation chips (only show for canonical themes)
                        if (_hasCanonicalMatch) ...[
                          _pagePadding(
                            child: _StyleVariationChips(
                              currentStyle: _currentStyle,
                              onStyleSelected: _handleStyleChange,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemBuilder: (_, i) => PatternControlCard(pattern: _filteredSmart[i]),
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemCount: _filteredSmart.length,
                          ),
                        ),
                      ],
                    ),
            )
            else
            // Default explore content (no active search)
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 120),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Spotlight hero: show personalized recommendation when available; fallback to Chiefs banner
                  _pagePadding(
                    child: recs.isNotEmpty
                        ? _SpotlightRecommendedHero(title: _greetingTitle(), pattern: recs.first)
                        : const _SpotlightBannerChiefs(),
                  ),
                  _gap(24),
                  // Personalized recommendations row beneath the hero (same cards and dimensions)
                  if (recs.isNotEmpty) ...[
                    _pagePadding(
                      child: PatternCategoryRow(title: _greetingTitle(), patterns: recs, query: '', isFeatured: true),
                    ),
                    _gap(24),
                  ],
                  _pagePadding(child: PatternCategoryRow(title: 'Architectural & Elegant', patterns: library.architecturalElegant, query: '')),
                  _gap(24),
                  _pagePadding(child: PatternCategoryRow(title: 'Holidays & Events', patterns: library.holidaysEvents, query: '')),
                  _gap(24),
                  _pagePadding(child: PatternCategoryRow(title: 'Sports Teams', patterns: library.sportsTeams, query: '')),
                  _gap(28),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

// Helpers for consistent page gutters and spacing
Widget _pagePadding({required Widget child}) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child);
Widget _gap(double h) => SizedBox(height: h);

/// Lumina AI Search input with pill shape, gradient border, and live search.
class _LuminaAISearchBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onClear;
  const _LuminaAISearchBar({required this.controller, required this.onSubmitted, this.onClear});

  @override
  State<_LuminaAISearchBar> createState() => _LuminaAISearchBarState();
}

class _LuminaAISearchBarState extends State<_LuminaAISearchBar> {
  bool _hasText = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    // Debounced live search: trigger search after user stops typing for 500ms
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      widget.onSubmitted(widget.controller.text);
    });
  }

  void _handleClear() {
    _debounceTimer?.cancel();
    widget.controller.clear();
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [NexGenPalette.cyan, NexGenPalette.violet]),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(25)),
        child: Row(children: [
          const Icon(Icons.auto_awesome, color: NexGenPalette.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: widget.controller,
              onSubmitted: widget.onSubmitted,
              style: Theme.of(context).textTheme.bodyLarge,
              cursorColor: NexGenPalette.cyan,
              decoration: const InputDecoration(
                hintText: "Ask Lumina for a vibe... (e.g. 'Game Day', 'Spooky')",
                hintStyle: TextStyle(color: Colors.white70),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Show clear button when text is present
          if (_hasText) ...[
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _handleClear,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white70, size: 18),
              ),
            ),
            const SizedBox(width: 8),
          ],
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              _debounceTimer?.cancel();
              widget.onSubmitted(widget.controller.text);
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: NexGenPalette.cyan, shape: BoxShape.circle, boxShadow: [
                BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 2)),
              ]),
              child: const Icon(Icons.send, color: Colors.black, size: 18),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Spotlight hero with bold CTA and Chiefs gradient
class _SpotlightBannerChiefs extends ConsumerWidget {
  const _SpotlightBannerChiefs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AspectRatio(
      // Make the hero shorter to reduce vertical footprint
      aspectRatio: 16 / 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(children: [
          // Gradient background (Chiefs: deep red -> gold)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.red,
                    const Color(0xFFFFD54F),
                  ],
                ),
              ),
            ),
          ),
          // Subtle overlay for readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.35)],
                ),
              ),
            ),
          ),
          // Content
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Trending Now', style: Theme.of(context).textTheme.labelLarge!.withColor(Colors.white70)),
                  const SizedBox(height: 4),
                  Text('Chiefs Kingdom', style: Theme.of(context).textTheme.titleLarge!.withColor(Colors.white)),
                ]),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final repo = ref.read(wledRepositoryProvider);
                  if (repo == null) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
                    return;
                  }
                  try {
                    // Chiefs colors: Red (255,0,0) and Gold (255,215,0)
                    await repo.applyJson({
                      'on': true,
                      'bri': 210,
                      'seg': [
                        {
                          'fx': 0,
                          'sx': 160,
                          'ix': 128,
                          'pal': 0,
                          'col': [
                            rgbToRgbw(255, 0, 0, forceZeroWhite: true),     // Red
                            rgbToRgbw(255, 215, 0, forceZeroWhite: true),   // Gold
                          ]
                        }
                      ]
                    });
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playing: Chiefs Kingdom')));
                  } catch (e) {
                    debugPrint('Spotlight apply failed: $e');
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to play pattern')));
                  }
                },
                icon: const Icon(Icons.play_arrow, color: Colors.black),
                label: const Text('Play'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Spotlight hero that uses the first personalized recommendation.
class _SpotlightRecommendedHero extends ConsumerWidget {
  final String title; // e.g., "Good Evening, Alex" or "Recommended for You"
  final GradientPattern pattern;
  const _SpotlightRecommendedHero({required this.title, required this.pattern});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AspectRatio(
      // Make the personalized hero shorter to match compact layout
      aspectRatio: 16 / 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(children: [
          // Animated gradient background from the recommended pattern colors
          Positioned.fill(child: LiveGradientStrip(colors: pattern.colors, speed: 128)),
          // Subtle overlay for readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.12), Colors.black.withValues(alpha: 0.35)],
                ),
              ),
            ),
          ),
          // Content
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge!.withColor(Colors.white70)),
                  const SizedBox(height: 4),
                  Text(pattern.name, style: Theme.of(context).textTheme.titleLarge!.withColor(Colors.white)),
                ]),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final repo = ref.read(wledRepositoryProvider);
                  if (repo == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
                    }
                    return;
                  }
                  try {
                    // Use the pattern's toWledPayload() method for proper effect/speed/intensity
                    await repo.applyJson(pattern.toWledPayload());
                    // Update the active preset label
                    ref.read(activePresetLabelProvider.notifier).state = pattern.name;
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${pattern.name} applied!')));
                    }
                  } catch (e) {
                    debugPrint('Spotlight recommended apply failed: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to play pattern')));
                    }
                  }
                },
                icon: const Icon(Icons.play_arrow, color: Colors.black),
                label: const Text('Play'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// GradientPattern moved to pattern_models.dart to enable reuse across providers

/// GPU-friendly animated gradient strip that simulates a flowing/chase effect
/// using a LinearGradient and a lightweight GradientTransform.
///
/// Pass a list of colors for the gradient and a speed value (0 = static).
class LiveGradientStrip extends StatefulWidget {
  final List<Color> colors;
  final double speed; // Typical range 0..255
  const LiveGradientStrip({super.key, required this.colors, required this.speed});

  @override
  State<LiveGradientStrip> createState() => _LiveGradientStripState();
}

class _LiveGradientStripState extends State<LiveGradientStrip> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Map speed (0..255) to a loop duration. Faster speed -> shorter duration.
  Duration _durationFor(double speed) {
    final s = speed.clamp(0, 255);
    final ms = 4200 - (s / 255) * 3600; // ~4.2s slow -> ~0.6s fast
    final clamped = ms.clamp(350, 8000).round();
    return Duration(milliseconds: clamped);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _durationFor(widget.speed));
    _maybeStart();
  }

  void _maybeStart() {
    if (widget.speed <= 0) {
      _controller.stop();
      _controller.value = 0; // static
    } else {
      _controller.duration = _durationFor(widget.speed);
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant LiveGradientStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) {
      _maybeStart();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> get _effectiveColors {
    if (widget.colors.isEmpty) return const [Colors.white, Colors.white];
    if (widget.colors.length == 1) return [widget.colors.first, widget.colors.first];
    return widget.colors;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _effectiveColors;

    // Static gradient when speed == 0
    if (widget.speed <= 0) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: colors),
        ),
      );
    }

    // Animated: slide the gradient horizontally in a seamless loop
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: colors,
              tileMode: TileMode.mirror,
              transform: _SlidingGradientTransform(_controller.value),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent; // 0..1
  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final dx = bounds.width * slidePercent;
    // Translate around the center to avoid edge stretching
    final m = Matrix4.identity();
    m.translate(dx);
    return m;
  }
}

/// Netflix-style horizontal row of gradient cards
class PatternCategoryRow extends ConsumerWidget {
  final String title;
  final List<GradientPattern> patterns;
  final String query;
  final bool isFeatured;
  const PatternCategoryRow({super.key, required this.title, required this.patterns, this.query = '', this.isFeatured = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? patterns
        : patterns.where((p) {
            final name = p.name.toLowerCase();
            if (q.contains('spooky')) return name.contains('halloween');
            if (q.contains('game')) return name.contains('chiefs') || name.contains('titans') || name.contains('royals');
            if (q.contains('holiday') || q.contains('christmas') || q.contains('xmas')) return name.contains('christmas') || name.contains('july');
            if (q.contains('elegant') || q.contains('architect')) return name.contains('white') || name.contains('gold');
            return name.contains(q);
          }).toList(growable: false);

    if (filtered.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, i) => _GradientPatternCard(data: filtered[i], isFeatured: isFeatured),
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemCount: filtered.length,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    ]);
  }
}

class _GradientPatternCard extends ConsumerWidget {
  final GradientPattern data;
  final bool isFeatured;
  const _GradientPatternCard({required this.data, this.isFeatured = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final br = BorderRadius.circular(16);
    return Container(
      decoration: isFeatured
          ? BoxDecoration(
              borderRadius: br,
              boxShadow: [
                BoxShadow(color: NexGenPalette.gold.withValues(alpha: 0.28), blurRadius: 12, spreadRadius: 0.5, offset: const Offset(0, 2)),
              ],
            )
          : null,
      child: InkWell(
      onTap: () async {
        final repo = ref.read(wledRepositoryProvider);
        if (repo == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
          }
          return;
        }
        try {
          // Use the pattern's toWledPayload() method for proper effect/speed/intensity
          await repo.applyJson(data.toWledPayload());
          // Update the active preset label
          ref.read(activePresetLabelProvider.notifier).state = data.name;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${data.name} applied!')));
          }
        } catch (e) {
          debugPrint('Apply gradient pattern failed: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
          }
        }
        },
        child: ClipRRect(
          borderRadius: br,
          child: SizedBox(
            width: 140,
            height: 140,
            child: Stack(children: [
              // Animated flowing gradient background (speed based on pattern)
              Positioned.fill(child: LiveGradientStrip(colors: data.colors, speed: data.isStatic ? 0 : data.speed.toDouble())),
              // Overlay for readability
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.1), Colors.black.withValues(alpha: 0.7)],
                    ),
                  ),
                ),
              ),
              // Border overlay (featured -> gold, otherwise standard line)
              if (!isFeatured)
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: NexGenPalette.line))))
              else
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: NexGenPalette.gold, width: 1.6)))),
              // Effect badge with color behavior indicator (top-left)
              Positioned(
                left: 8,
                top: 8,
                child: EffectWithColorBehaviorBadge(
                  effectId: data.effectId,
                  effectName: data.effectName,
                  isStatic: data.isStatic,
                ),
              ),
              // Play icon bottom-right
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow, color: Colors.black, size: 18),
                ),
              ),
              // Name and subtitle bottom-left
              Positioned(
                left: 8,
                right: 40,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.name,
                      style: Theme.of(context).textTheme.labelLarge!.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (data.subtitle != null)
                      Text(
                        data.subtitle!,
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white70, fontSize: 9),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              )
            ]),
          ),
        ),
      ),
    );
  }
}

/// Vertical list result item used by the simulated AI search results
class _GradientResultTile extends ConsumerWidget {
  final GradientPattern data;
  const _GradientResultTile({required this.data});

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
      }
      return;
    }
    try {
      // Build color array with W=0 to keep saturated colors accurate
      List<List<int>> cols = [];
      for (final c in data.colors.take(3)) {
        cols.add(rgbToRgbw(c.red, c.green, c.blue, forceZeroWhite: true));
      }
      if (cols.isEmpty) cols = [rgbToRgbw(255, 255, 255, forceZeroWhite: true)];
      await repo.applyJson({
        'on': true,
        'bri': 210,
        'seg': [
          {'fx': 0, 'sx': 128, 'ix': 128, 'pal': 0, 'col': cols}
        ]
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${data.name}')));
      }
    } catch (e) {
      debugPrint('Apply result pattern failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => _apply(context, ref),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Row(children: [
          // Gradient preview
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: data.colors),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(data.name, style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () => _apply(context, ref),
            icon: const Icon(Icons.bolt, color: Colors.black),
            label: const Text('Apply'),
          )
        ]),
      ),
    );
  }
}

/// Rich, expandable control card for a SmartPattern
class PatternControlCard extends ConsumerStatefulWidget {
  final SmartPattern pattern;
  const PatternControlCard({super.key, required this.pattern});

  @override
  ConsumerState<PatternControlCard> createState() => _PatternControlCardState();
}

class _PatternControlCardState extends ConsumerState<PatternControlCard> with TickerProviderStateMixin {
  late SmartPattern _current;
  bool _expanded = false;
  Timer? _debounce;
  Timer? _layoutDebounce;

  @override
  void initState() {
    super.initState();
    _current = widget.pattern;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _layoutDebounce?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _payloadFromCurrent({bool ensureOn = true}) {
    final map = _current.toJson();
    if (ensureOn) map['on'] = true;
    return map;
  }

  Future<void> _applyNow({bool toast = false}) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
      return;
    }
    try {
      await repo.applyJson(_payloadFromCurrent());
      // Update the active preset label to show this pattern name
      ref.read(activePresetLabelProvider.notifier).state = _current.name;
      if (toast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playing: ${_current.name}')));
      }
    } catch (e) {
      debugPrint('Pattern apply failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
      }
    }
  }

  void _scheduleDebouncedApply() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _applyNow());
  }

  void _scheduleDebouncedLayoutApply() {
    _layoutDebounce?.cancel();
    _layoutDebounce = Timer(const Duration(milliseconds: 180), () async {
      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return;
      try {
        await repo.applyJson({
          'seg': [
            {
              'gp': _current.grouping,
              'sp': _current.spacing,
            }
          ]
        });
      } catch (e) {
        debugPrint('Apply gp/sp failed: $e');
      }
    });
  }

  String _effectNameFromId(int id) {
    try {
      final m = PatternGenerator.wledEffects.firstWhere((e) => e['id'] == id);
      return (m['name'] as String?) ?? 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectName = _effectNameFromId(_current.effectId);
    final isStatic = _current.effectId == 0 || effectName.toLowerCase().contains('static') || effectName.toLowerCase().contains('solid');
    final badgeText = isStatic ? 'Static' : 'Motion: $effectName';
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Preview swatch
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _current.colors
                        .take(3)
                        .map((rgb) => Color.fromARGB(255, rgb[0].clamp(0, 255), rgb[1].clamp(0, 255), rgb[2].clamp(0, 255)))
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_current.name, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                _EffectBadge(text: badgeText, effectId: _current.effectId),
              ]),
            ),
            IconButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: Colors.white),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _applyNow(toast: true),
              icon: const Icon(Icons.play_arrow, color: Colors.black),
              label: const Text('Turn On'),
            ),
          ]),
          if (_expanded) ...[
            const SizedBox(height: 12),
            // Speed slider
            Row(children: [
              const Icon(Icons.speed, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _current.speed.toDouble(),
                  min: 0,
                  max: 255,
                  onChanged: (v) {
                    setState(() => _current = SmartPattern(
                          id: _current.id,
                          name: _current.name,
                          colors: _current.colors,
                          effectId: _current.effectId,
                          speed: v.round().clamp(0, 255),
                          intensity: _current.intensity,
                          paletteId: _current.paletteId,
                          reverse: _current.reverse,
                          grouping: _current.grouping,
                          spacing: _current.spacing,
                        ));
                    _scheduleDebouncedApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.speed}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 6),
            // Effect Strength slider (formerly Intensity)
            Row(children: [
              Tooltip(
                message: 'Effect Strength',
                child: const Icon(Icons.tune, color: NexGenPalette.cyan),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _current.intensity.toDouble(),
                  min: 0,
                  max: 255,
                  onChanged: (v) {
                    setState(() => _current = SmartPattern(
                          id: _current.id,
                          name: _current.name,
                          colors: _current.colors,
                          effectId: _current.effectId,
                          speed: _current.speed,
                          intensity: v.round().clamp(0, 255),
                          paletteId: _current.paletteId,
                          reverse: _current.reverse,
                          grouping: _current.grouping,
                          spacing: _current.spacing,
                        ));
                    _scheduleDebouncedApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.intensity}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 6),
            // Direction toggle
            Row(children: [
              const Icon(Icons.swap_horiz, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Left→Right')),
                    ButtonSegment(value: true, label: Text('Right→Left')),
                  ],
                  selected: {_current.reverse},
                  onSelectionChanged: (s) {
                    final rev = s.isNotEmpty ? s.first : false;
                    setState(() => _current = SmartPattern(
                          id: _current.id,
                          name: _current.name,
                          colors: _current.colors,
                          effectId: _current.effectId,
                          speed: _current.speed,
                          intensity: _current.intensity,
                          paletteId: _current.paletteId,
                          reverse: rev,
                          grouping: _current.grouping,
                          spacing: _current.spacing,
                        ));
                    _scheduleDebouncedApply();
                  },
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // Pixel Layout section
            Row(children: [
              const Icon(Icons.grid_view, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Text('Pixel Layout', style: Theme.of(context).textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
            // Bulb Grouping slider (gp)
            Row(children: [
              const Icon(Icons.blur_on, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _current.grouping.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '${_current.grouping}',
                  onChanged: (v) {
                    final g = v.round().clamp(1, 10);
                    setState(() => _current = SmartPattern(
                          id: _current.id,
                          name: _current.name,
                          colors: _current.colors,
                          effectId: _current.effectId,
                          speed: _current.speed,
                          intensity: _current.intensity,
                          paletteId: _current.paletteId,
                          reverse: _current.reverse,
                          grouping: g,
                          spacing: _current.spacing,
                        ));
                    _scheduleDebouncedLayoutApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.grouping}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 6),
            // Spacing/Gaps slider (sp)
            Row(children: [
              const Icon(Icons.space_bar, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _current.spacing.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: '${_current.spacing}',
                  onChanged: (v) {
                    final s = v.round().clamp(0, 10);
                    setState(() => _current = SmartPattern(
                          id: _current.id,
                          name: _current.name,
                          colors: _current.colors,
                          effectId: _current.effectId,
                          speed: _current.speed,
                          intensity: _current.intensity,
                          paletteId: _current.paletteId,
                          reverse: _current.reverse,
                          grouping: _current.grouping,
                          spacing: s,
                        ));
                    _scheduleDebouncedLayoutApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.spacing}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 10),
            // Color Sequence Builder
            Row(children: [
              const Icon(Icons.palette, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Text('Color Sequence', style: Theme.of(context).textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              // Deduplicate base colors to present a clean picker (team colors only)
              final seen = <String>{};
              final baseColors = <List<int>>[];
              for (final rgb in _current.colors) {
                if (rgb.length < 3) continue;
                final key = '${rgb[0]}-${rgb[1]}-${rgb[2]}';
                if (seen.add(key)) baseColors.add([rgb[0], rgb[1], rgb[2]]);
              }
              final initial = _current.colors.map((c) => [c[0], c[1], c[2]]).toList(growable: false);
              return ColorSequenceBuilder(
                baseColors: baseColors.isNotEmpty ? baseColors : initial,
                initialSequence: initial,
                onChanged: (seq) async {
                  final repo = ref.read(wledRepositoryProvider);
                  if (repo == null) return;
                  try {
                    await repo.applyJson({
                      'seg': [
                        {
                          'pal': seq,
                        }
                      ]
                    });
                  } catch (e) {
                    debugPrint('Apply custom palette failed: $e');
                  }
                },
              );
            }),
            const SizedBox(height: 12),
            // Footer actions
            Row(children: [
              TextButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to Favorites')));
                },
                icon: const Icon(Icons.favorite_border, color: NexGenPalette.cyan),
                label: const Text('Save to Favorites'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () async {
                  final savePattern = ref.read(savePatternAsSceneProvider);
                  final result = await savePattern(_current);
                  if (mounted) {
                    if (result != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${_current.name} saved to My Scenes'),
                          action: SnackBarAction(
                            label: 'View',
                            onPressed: () => context.push('/my-scenes'),
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to save. Please sign in.')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.save_alt, color: NexGenPalette.cyan),
                label: const Text('Save to My Scenes'),
              ),
            ]),
          ]
        ]),
      ),
    );
  }
}

class _EffectBadge extends StatelessWidget {
  final String text;
  final int? effectId;
  const _EffectBadge({required this.text, this.effectId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effect = effectId != null ? WledEffectsCatalog.getById(effectId!) : null;
    final behavior = effect?.colorBehavior;
    final behaviorColor = behavior != null ? _colorForBehavior(behavior) : NexGenPalette.cyan;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Effect name badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.auto_awesome_motion, size: 14, color: NexGenPalette.cyan),
            const SizedBox(width: 6),
            Text(text, style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
        // Color behavior badge (if effect ID provided)
        if (behavior != null) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: behavior.description,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: behaviorColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: behaviorColor.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_iconForBehavior(behavior), size: 12, color: behaviorColor),
                const SizedBox(width: 4),
                Text(
                  behavior.shortName,
                  style: TextStyle(color: behaviorColor, fontSize: 10, fontWeight: FontWeight.w500),
                ),
              ]),
            ),
          ),
        ],
      ],
    );
  }

  IconData _iconForBehavior(ColorBehavior behavior) {
    switch (behavior) {
      case ColorBehavior.usesSelectedColors:
        return Icons.palette_outlined;
      case ColorBehavior.blendsSelectedColors:
        return Icons.gradient;
      case ColorBehavior.generatesOwnColors:
        return Icons.auto_awesome;
      case ColorBehavior.usesPalette:
        return Icons.color_lens_outlined;
    }
  }

  Color _colorForBehavior(ColorBehavior behavior) {
    switch (behavior) {
      case ColorBehavior.usesSelectedColors:
        return NexGenPalette.cyan;
      case ColorBehavior.blendsSelectedColors:
        return const Color(0xFF64B5F6);
      case ColorBehavior.generatesOwnColors:
        return const Color(0xFFFFB74D);
      case ColorBehavior.usesPalette:
        return const Color(0xFFBA68C8);
    }
  }
}

class _CategoryCard extends StatelessWidget {
  final PatternCategory category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/explore/${category.id}', extra: category),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(image: NetworkImage(category.imageUrl), fit: BoxFit.cover),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    NexGenPalette.matteBlack.withValues(alpha: 0.1),
                    NexGenPalette.matteBlack.withValues(alpha: 0.6),
                  ],
                ),
                border: Border.all(color: NexGenPalette.line),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(category.name, style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Detail screen for a single Pattern Category now shows Sub-Category folders
class CategoryDetailScreen extends ConsumerWidget {
  final String categoryId;
  final String? categoryName;
  const CategoryDetailScreen({super.key, required this.categoryId, this.categoryName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSubs = ref.watch(patternSubCategoriesByCategoryProvider(categoryId));
    final title = categoryName ?? 'Explore';
    return Scaffold(
      appBar: GlassAppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: asyncSubs.when(
            data: (subs) {
              if (subs.isEmpty) return const _CenteredText('No sub-categories yet');
              return GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.0,
                ),
                itemCount: subs.length,
                itemBuilder: (_, i) => _SubCategoryCard(categoryId: categoryId, sub: subs[i]),
              );
            },
            error: (e, st) => _ErrorState(error: '$e'),
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ),
    );
  }
}

class _SubCategoryCard extends StatelessWidget {
  final String categoryId;
  final SubCategory sub;
  const _SubCategoryCard({required this.categoryId, required this.sub});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/explore/$categoryId/sub/${sub.id}', extra: {'name': sub.name}),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: NexGenPalette.line),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          // Color swatch cluster
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: sub.themeColors.take(4).map((c) => _ColorDot(color: c)).toList(growable: false),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(sub.name, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.chevron_right, color: Colors.white),
        ]),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: NexGenPalette.matteBlack, width: 1)),
    );
  }
}

class _PatternItemCard extends ConsumerWidget {
  final PatternItem item;
  const _PatternItemCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () async {
        final repo = ref.read(wledRepositoryProvider);
        if (repo == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
          }
          return;
        }
        try {
          await repo.applyJson(item.wledPayload);
          // Update the active preset label
          ref.read(activePresetLabelProvider.notifier).state = item.name;
          // Attempt immediate local reflection similar to Scenes card
          final notifier = ref.read(wledStateProvider.notifier);
          final bri = item.wledPayload['bri'];
          if (bri is int) notifier.setBrightness(bri);
          final seg = item.wledPayload['seg'];
          if (seg is List && seg.isNotEmpty && seg.first is Map) {
            final s0 = seg.first as Map;
            final sx = s0['sx'];
            if (sx is int) notifier.setSpeed(sx);
            final col = s0['col'];
            if (col is List && col.isNotEmpty && col.first is List) {
              final c = col.first as List;
              if (c.length >= 3) {
                notifier.setColor(Color.fromARGB(255, (c[0] as num).toInt(), (c[1] as num).toInt(), (c[2] as num).toInt()));
              }
            }
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${item.name}')));
          }
        } catch (e) {
          debugPrint('Apply pattern failed: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
          }
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(children: [
          // Animated gradient preview from the item's palette
          Positioned.fill(child: _ItemLiveGradient(colors: _extractColorsFromItem(item), speed: 128)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    NexGenPalette.matteBlack.withValues(alpha: 0.08),
                    NexGenPalette.matteBlack.withValues(alpha: 0.65),
                  ],
                ),
                border: Border.all(color: NexGenPalette.line),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(item.name, style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Wrapper to keep LiveGradientStrip lightweight in item cards.
class _ItemLiveGradient extends StatelessWidget {
  final List<Color> colors;
  final double speed;
  const _ItemLiveGradient({required this.colors, required this.speed});

  @override
  Widget build(BuildContext context) => LiveGradientStrip(colors: colors, speed: speed);
}

List<Color> _extractColorsFromItem(PatternItem item) {
  try {
    final seg = item.wledPayload['seg'];
    if (seg is List && seg.isNotEmpty) {
      final first = seg.first;
      if (first is Map) {
        final col = first['col'];
        if (col is List) {
          final result = <Color>[];
          for (final c in col) {
            if (c is List && c.length >= 3) {
              final r = (c[0] as num).toInt().clamp(0, 255);
              final g = (c[1] as num).toInt().clamp(0, 255);
              final b = (c[2] as num).toInt().clamp(0, 255);
              result.add(Color.fromARGB(255, r, g, b));
            }
          }
          if (result.isNotEmpty) return result;
        }
      }
    }
  } catch (e) {
    debugPrint('Failed to extract colors from PatternItem: $e');
  }
  return const [Colors.white, Colors.white];
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});
  @override
  Widget build(BuildContext context) => Center(child: Text(error));
}

class _CenteredText extends StatelessWidget {
  final String text;
  const _CenteredText(this.text);
  @override
  Widget build(BuildContext context) => Center(child: Text(text));
}

/// Screen 3: Theme Selection for a Sub-Category
/// Shows the sub-category's palette as selectable swatches (future: drive effect presets)
class ThemeSelectionScreen extends ConsumerWidget {
  final String categoryId;
  final String subCategoryId;
  final String? subCategoryName;
  const ThemeSelectionScreen({super.key, required this.categoryId, required this.subCategoryId, this.subCategoryName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSub = ref.watch(subCategoryByIdProvider(subCategoryId));
    return asyncSub.when(
      data: (sub) {
        if (sub == null) {
          return const Scaffold(body: _CenteredText('Sub-category not found'));
        }
        final colors = sub.themeColors;
        final asyncItems = ref.watch(patternGeneratedItemsBySubCategoryProvider(sub.id));
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: GlassAppBar(
              title: Text(subCategoryName ?? sub.name),
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'All'),
                  Tab(text: 'Elegant'),
                  Tab(text: 'Motion'),
                  Tab(text: 'Energy'),
                ],
              ),
            ),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: asyncItems.when(
                data: (items) {
                  if (items.isEmpty) return const _CenteredText('No generated items');
                  // Precompute filtered lists by vibe
                  List<PatternItem> filterBy(String vibe) {
                    if (vibe == 'All') return items;
                    return items.where((it) {
                      final fx = MockPatternRepository.effectIdFromPayload(it.wledPayload);
                      if (fx == null) return false;
                      final v = MockPatternRepository.vibeForFx(fx);
                      return v == vibe;
                    }).toList(growable: false);
                  }

                  final all = items;
                  final elegant = filterBy('Elegant');
                  final motion = filterBy('Motion');
                  final energy = filterBy('Energy');

                  Widget buildGrid(List<PatternItem> list) {
                    if (list.isEmpty) return const _CenteredText('No items for this vibe');
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('Auto-generated patterns', style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(width: 8),
                        Wrap(spacing: 6, children: colors.take(3).map((c) => _ColorDot(color: c)).toList(growable: false)),
                      ]),
                      const SizedBox(height: 12),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.1,
                          ),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _PatternItemCard(item: list[i]),
                        ),
                      ),
                    ]);
                  }

                  return TabBarView(children: [
                    buildGrid(all),
                    buildGrid(elegant),
                    buildGrid(motion),
                    buildGrid(energy),
                  ]);
                },
                error: (e, st) => _ErrorState(error: '$e'),
                loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
          ),
        );
      },
      error: (e, st) => Scaffold(appBar: const GlassAppBar(), body: _ErrorState(error: '$e')),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
}

class _PaletteTile extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _PaletteTile({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: NexGenPalette.line),
        ),
      ),
    );
  }
}

/// Style variation chips for refining search results.
/// Shows different style options (classic, subtle, bold, etc.) that users can
/// tap to see variations of the same theme.
class _StyleVariationChips extends StatelessWidget {
  final ThemeStyle currentStyle;
  final ValueChanged<ThemeStyle> onStyleSelected;
  const _StyleVariationChips({required this.currentStyle, required this.onStyleSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.tune, color: NexGenPalette.cyan, size: 16),
            const SizedBox(width: 6),
            Text(
              'Style Variations',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: NexGenPalette.textMedium),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ThemeStyle.values.map((style) => _StyleChip(
            style: style,
            isSelected: style == currentStyle,
            onTap: () => onStyleSelected(style),
          )).toList(),
        ),
      ],
    );
  }
}

class _StyleChip extends StatelessWidget {
  final ThemeStyle style;
  final bool isSelected;
  final VoidCallback onTap;
  const _StyleChip({required this.style, required this.isSelected, required this.onTap});

  IconData _iconForStyle(ThemeStyle style) {
    switch (style) {
      case ThemeStyle.classic:
        return Icons.auto_awesome;
      case ThemeStyle.subtle:
        return Icons.contrast;
      case ThemeStyle.bold:
        return Icons.wb_sunny;
      case ThemeStyle.vintage:
        return Icons.filter_vintage;
      case ThemeStyle.modern:
        return Icons.architecture;
      case ThemeStyle.playful:
        return Icons.celebration;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? NexGenPalette.cyan.withValues(alpha: 0.2) : NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForStyle(style),
                size: 16,
                color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
              ),
              const SizedBox(width: 6),
              Text(
                style.displayName,
                style: TextStyle(
                  color: isSelected ? NexGenPalette.textHigh : NexGenPalette.textMedium,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
