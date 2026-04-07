import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/wled/lumina_custom_effects.dart';
import 'package:nexgen_command/features/wled/pattern_library_browser.dart';
import 'package:nexgen_command/features/wled/pattern_grid_widgets.dart';
import 'package:nexgen_command/features/dashboard/widgets/channel_selector_bar.dart';
import 'package:nexgen_command/features/ai/lumina_bottom_sheet.dart' show showLuminaSheet;
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart' show LuminaSheetMode;
import 'package:nexgen_command/features/explore_patterns/ui/explore_design_system.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';

/// Helper to execute custom Lumina effects (ID >= 1000).
/// Returns true if the effect was a custom effect and was executed.
/// Returns false if it's a native WLED effect (caller should send payload directly).
///
/// Custom Lumina effects animate by sending sequential WLED payloads from the app.
/// The animation plays once and leaves the LEDs in the final frame state.
Future<bool> executeCustomEffectIfNeeded({
  required int effectId,
  required List<List<int>> colors,
  required WledRepository repo,
  int? totalPixels,
}) async {
  // Check if this is a custom Lumina effect
  if (!LuminaCustomEffectsCatalog.isCustomEffect(effectId)) {
    return false; // Not a custom effect, let caller handle normally
  }

  // Get total pixel count if not provided
  final pixelCount = totalPixels ?? await repo.getTotalLedCount() ?? 150;

  // Create the effect service with a callback to send payloads to WLED
  final effectService = LuminaEffectService(
    sendToWled: (payload) async {
      await repo.applyJson(payload);
    },
  );

  // Execute the custom effect animation (plays once, ends on final frame)
  await effectService.executeEffect(
    effectId: effectId,
    colors: colors.isNotEmpty ? colors : [[255, 255, 255, 0]],
    totalPixels: pixelCount,
    durationMs: 3000, // Animation duration - 3 seconds for smooth reveal
    loop: false, // Play once and stop on final frame
  );

  return true;
}

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
  // Library search results containing existing patterns
  LibrarySearchResults? _searchResults;
  // Track current query for display
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
  }

  Future<void> _handleSearch(String raw) async {
    final query = raw.trim();
    debugPrint('ExplorePatternsScreen: _handleSearch called with query="$query"');
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _hasSearched = false;
        _searchResults = null;
        _currentQuery = '';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _currentQuery = query;
    });

    try {
      // Brief delay for smoother UX (debounce handles most of the wait)
      await Future.delayed(const Duration(milliseconds: 300));

      // Search existing patterns in the library (NOT generating new ones)
      final repo = ref.read(patternRepositoryProvider);
      debugPrint('ExplorePatternsScreen: Searching library for "$query"');
      final results = await repo.searchLibrary(query);
      debugPrint('ExplorePatternsScreen: Found ${results.totalCount} results (${results.palettes.length} palettes, ${results.folders.length} folders, ${results.patterns.length} patterns)');

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Library search failed: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() {
        _searchResults = const LibrarySearchResults(palettes: [], folders: [], patterns: []);
        _isSearching = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(patternCategoriesProvider);

    return Scaffold(
      backgroundColor: ExploreDesignTokens.backgroundBase,
      body: Stack(
        children: [
          // Subtle radial gradient background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.3, -0.6),
                  radius: 0.8,
                  colors: [Color(0xFF1A1A2E), Color(0xFF080810)],
                ),
              ),
            ),
          ),
          // Main content
          Column(
            children: [
              // Transparent AppBar
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: const Text(
                  'Explore Patterns',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
                actions: [
                  IconButton(
                    onPressed: () {},
                    icon: Icon(Icons.search, color: ExploreDesignTokens.textSecondary),
                    tooltip: 'Search',
                  ),
                ],
              ),
              // Search bar + channel selector
              pagePadding(
                child: _LuminaAISearchBar(
                  controller: _searchController,
                  onSubmitted: _handleSearch,
                  onClear: () => _handleSearch(''),
                ),
              ),
              const SizedBox(height: 8),
              pagePadding(child: const ChannelSelectorBar()),
              const SizedBox(height: 8),
              // Roofline preview hero — only shown when a design card is selected
              _ExploreRooflinePreview(
                onDismiss: () => ref.read(explorePreviewProvider.notifier).state = null,
              ),
              // Conditional rendering based on search state
              if (_isSearching)
                Expanded(
                  child: Column(
                    children: [
                      const ExploreShimmerGrid(crossAxisCount: 2, itemCount: 6),
                      const SizedBox(height: 8),
                      Text('Searching design library...', style: TextStyle(color: ExploreDesignTokens.textSecondary)),
                    ],
                  ),
                )
              else if (_hasSearched)
                Expanded(
                  child: (_searchResults == null || !_searchResults!.hasResults)
                      ? _NoMatchRedirectWidget(
                          query: _currentQuery,
                          onClearSearch: () {
                            _searchController.clear();
                            _handleSearch('');
                          },
                          onLuminaTap: () => showLuminaSheet(context, ref, mode: LuminaSheetMode.compact),
                        )
                      : _LibrarySearchResultsView(
                          results: _searchResults!,
                          query: _currentQuery,
                        ),
                )
              else
                // Default explore content (no active search)
                Expanded(
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // 1. My Saved Designs section
                      SliverToBoxAdapter(
                        child: pagePadding(child: const MySavedDesignsSection()),
                      ),

                      // 2. Recent Patterns section
                      SliverToBoxAdapter(
                        child: pagePadding(child: const RecentPatternsSection()),
                      ),

                      // 4. Pinned Categories section
                      SliverToBoxAdapter(
                        child: pagePadding(child: const PinnedCategoriesSection()),
                      ),

                      // 5. Browse Design Library header
                      SliverToBoxAdapter(
                        child: pagePadding(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SectionHeader(
                              title: 'Browse Design Library',
                              subtitle: 'Explore all categories',
                            ),
                          ),
                        ),
                      ),

                      // 6. Folder grid
                      categoriesAsync.when(
                        data: (categories) => SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.65,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _FolderHeroCard(
                                category: categories[index],
                                index: index,
                              ),
                              childCount: categories.length,
                            ),
                          ),
                        ),
                        loading: () => const SliverToBoxAdapter(
                          child: ExploreShimmerGrid(crossAxisCount: 2, itemCount: 6),
                        ),
                        error: (_, __) => SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Unable to load categories',
                                style: TextStyle(color: ExploreDesignTokens.textSecondary),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Bottom padding
                      SliverToBoxAdapter(child: SizedBox(height: navBarTotalHeight(context))),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Folder gradient color map (matches category names) ──

const Map<String, List<Color>> _folderGradients = {
  'architectural downlighting (white)': [Color(0xFFE0E0E0), Color(0xFF90CAF9)],
  'holidays':          [Color(0xFFFF5252), Color(0xFF69F0AE)],
  'game day fan zone': [Color(0xFFFF6D00), Color(0xFF2979FF)],
  'seasonal vibes':    [Color(0xFFFFB300), Color(0xFFFF6F00)],
  'parties & events':  [Color(0xFFE040FB), Color(0xFFFF4081)],
  'movies & superheroes': [Color(0xFF7B61FF), Color(0xFFFF4081)],
  'security & alerts': [Color(0xFFFF1744), Color(0xFFFF6F00)],
  'nature & outdoors': [Color(0xFF43A047), Color(0xFF80DEEA)],
  'solid colors':      [Color(0xFF4FC3F7), Color(0xFF7B61FF)],
  'effects':           [Color(0xFFCE93D8), Color(0xFFFF4081)],
  'favorites':         [Color(0xFFFF4081), Color(0xFFF50057)],
};

const List<Color> _defaultFolderGradient = [Color(0xFF4FC3F7), Color(0xFFCE93D8)];

List<Color> _gradientForFolder(String name) {
  return _folderGradients[name.toLowerCase().trim()] ?? _defaultFolderGradient;
}

const Map<String, String> _folderEmojis = {
  'architectural downlighting (white)': '🏛️',
  'holidays':          '🎄',
  'game day fan zone': '🏆',
  'seasonal vibes':    '🍂',
  'parties & events':  '🎉',
  'movies & superheroes': '🎬',
  'security & alerts': '🔐',
  'nature & outdoors': '🌿',
  'solid colors':      '🎨',
  'effects':           '✨',
  'favorites':         '❤️',
};

String _emojiForFolder(String name) {
  return _folderEmojis[name.toLowerCase().trim()] ?? '✨';
}

// ── FolderHeroCard ──

class _FolderHeroCard extends StatelessWidget {
  final PatternCategory category;
  final int index;

  const _FolderHeroCard({required this.category, required this.index});

  @override
  Widget build(BuildContext context) {
    final gradientColors = _gradientForFolder(category.name);
    final emoji = _emojiForFolder(category.name);

    // Staggered entrance animation: 60ms delay per card
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: LuminaGlassCard(
        glowColor: gradientColors[0],
        glowIntensity: 0.2,
        onTap: () {
          context.push(
            '/explore/library/${category.id}',
            extra: {'name': category.name},
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Full-bleed gradient background
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                ),
              ),
              // Dark scrim at bottom for text legibility
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 56,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00000000),
                        Color(0x66000000), // 40% black
                      ],
                    ),
                  ),
                ),
              ),
              // Emoji — vertically centered
              Positioned(
                top: 0,
                bottom: 36,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 30),
                  ),
                ),
              ),
              // Name + pill — bottom-left
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      category.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x33000000), // 20% black
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Tap to explore',
                        style: TextStyle(
                          color: Color(0xCCFFFFFF), // 80% white
                          fontSize: 11,
                        ),
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
}

// Helpers for consistent page gutters and spacing
Widget pagePadding({required Widget child}) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child);
Widget gap(double h) => SizedBox(height: h);

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
                hintText: "Search designs... (e.g. 'Christmas', 'Chiefs')",
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
              borderRadius: BorderRadius.circular(22),
              onTap: _handleClear,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white70, size: 22),
              ),
            ),
            const SizedBox(width: 8),
          ],
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () {
              _debounceTimer?.cancel();
              widget.onSubmitted(widget.controller.text);
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: NexGenPalette.cyan, shape: BoxShape.circle, boxShadow: [
                BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 2)),
              ]),
              child: const Icon(Icons.send, color: Colors.black, size: 22),
            ),
          ),
        ]),
      ),
    );
  }
}

// GradientPattern moved to pattern_models.dart to enable reuse across providers

/// Widget shown when search finds no matches in the existing library.
/// Provides friendly message and options to create custom patterns.
class _NoMatchRedirectWidget extends StatelessWidget {
  final String query;
  final VoidCallback onClearSearch;
  final VoidCallback onLuminaTap;

  const _NoMatchRedirectWidget({
    required this.query,
    required this.onClearSearch,
    required this.onLuminaTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [NexGenPalette.cyan.withValues(alpha: 0.3), NexGenPalette.violet.withValues(alpha: 0.3)],
              ),
            ),
            child: const Icon(
              Icons.lightbulb_outline,
              color: NexGenPalette.cyan,
              size: 40,
            ),
          ),
          const SizedBox(height: 24),

          // Friendly message
          Text(
            "We couldn't find '$query' in our design library",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            "But don't worry! Your creativity is our specialty.",
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: NexGenPalette.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Option 1: Lumina AI
          _RedirectOptionCard(
            icon: Icons.auto_awesome,
            iconColor: NexGenPalette.cyan,
            title: 'Describe it to Lumina',
            description: "Tell Lumina what you're imagining and we'll bring it to life with AI-powered pattern creation.",
            buttonText: 'Chat with Lumina',
            onTap: onLuminaTap,
          ),
          const SizedBox(height: 16),

          // Option 2: Design Studio
          _RedirectOptionCard(
            icon: Icons.palette_outlined,
            iconColor: NexGenPalette.violet,
            title: 'Build it in Design Studio',
            description: "Pick your colors, choose your effects, and create exactly what you're thinking.",
            buttonText: 'Open Design Studio',
            onTap: () => context.push(AppRoutes.exploreDesignStudio),
          ),
          const SizedBox(height: 24),

          // Clear search link
          TextButton(
            onPressed: onClearSearch,
            style: TextButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              textStyle: const TextStyle(fontSize: 15),
            ),
            child: Text(
              'Or browse our existing designs',
              style: TextStyle(color: NexGenPalette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card for redirect options in the no-match widget.
class _RedirectOptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String buttonText;
  final VoidCallback onTap;

  const _RedirectOptionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: NexGenPalette.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: iconColor.withValues(alpha: 0.2),
                foregroundColor: iconColor,
                minimumSize: const Size(double.infinity, 56),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(buttonText),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays library search results organized by type.
class _LibrarySearchResultsView extends ConsumerWidget {
  final LibrarySearchResults results;
  final String query;

  const _LibrarySearchResultsView({
    required this.results,
    required this.query,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Results header
        Text(
          'Found ${results.totalCount} results for "$query"',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: NexGenPalette.textSecondary,
          ),
        ),
        const SizedBox(height: 16),

        // Matching Palettes (colorways that can be explored)
        if (results.palettes.isNotEmpty) ...[
          Text(
            'Color Themes',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...results.palettes.map((palette) => _LibraryPaletteResultCard(
            node: palette,
            onTap: () => context.push('/explore/library/${palette.id}'),
          )),
          const SizedBox(height: 20),
        ],

        // Matching Folders (categories/subcategories)
        if (results.folders.isNotEmpty) ...[
          Text(
            'Categories',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...results.folders.map((folder) => _LibraryFolderResultCard(
            node: folder,
            onTap: () => context.push('/explore/library/${folder.id}'),
          )),
          const SizedBox(height: 20),
        ],

        // Matching Pre-built Patterns
        if (results.patterns.isNotEmpty) ...[
          Text(
            'Pre-built Patterns',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...results.patterns.map((pattern) => PatternCard(
            pattern: pattern,
          )),
        ],

        const SizedBox(height: 40),
      ],
    );
  }
}

/// Card displaying a palette result from library search.
class _LibraryPaletteResultCard extends StatelessWidget {
  final LibraryNode node;
  final VoidCallback onTap;

  const _LibraryPaletteResultCard({
    required this.node,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Color preview
              if (node.themeColors != null && node.themeColors!.isNotEmpty)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      colors: node.themeColors!.take(3).toList(),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: NexGenPalette.cyan.withValues(alpha: 0.2),
                  ),
                  child: const Icon(Icons.palette, color: NexGenPalette.cyan),
                ),
              const SizedBox(width: 16),
              // Name and description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (node.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        node.description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: NexGenPalette.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Arrow
              const Icon(Icons.chevron_right, color: NexGenPalette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card displaying a folder/category result from library search.
class _LibraryFolderResultCard extends StatelessWidget {
  final LibraryNode node;
  final VoidCallback onTap;

  const _LibraryFolderResultCard({
    required this.node,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Folder icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: NexGenPalette.violet.withValues(alpha: 0.2),
                ),
                child: const Icon(Icons.folder_outlined, color: NexGenPalette.violet),
              ),
              const SizedBox(width: 16),
              // Name
              Expanded(
                child: Text(
                  node.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Arrow
              const Icon(Icons.chevron_right, color: NexGenPalette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated roofline preview hero for the Explore page.
///
/// Watches [explorePreviewProvider]. When non-null, renders a house photo
/// with an [AnimatedRooflineOverlay] showing the selected design's colors
/// and effect. Collapses to zero height when null.
class _ExploreRooflinePreview extends ConsumerWidget {
  final VoidCallback onDismiss;
  const _ExploreRooflinePreview({required this.onDismiss});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(explorePreviewProvider);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: preview == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 160,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // House photo background
                      Image.asset(
                        'assets/images/Demohomephoto.jpg',
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, 0.3),
                      ),
                      // Roofline overlay
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return AnimatedRooflineOverlay(
                            previewColors: preview.colors,
                            previewEffectId: preview.effectId,
                            previewSpeed: preview.speed,
                            brightness: preview.brightness,
                            forceOn: true,
                            targetAspectRatio: constraints.maxWidth / constraints.maxHeight,
                            useBoxFitCover: true,
                            colorGroupSize: preview.colorGroupSize,
                            spacing: preview.spacing,
                          );
                        },
                      ),
                      // Bottom gradient for label legibility
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 48,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x00000000), Color(0xAA000000)],
                            ),
                          ),
                        ),
                      ),
                      // Design name label
                      if (preview.name.isNotEmpty)
                        Positioned(
                          left: 12,
                          bottom: 8,
                          right: 40,
                          child: Text(
                            preview.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      // Dismiss button
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: onDismiss,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Color(0x66000000),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.white70, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
