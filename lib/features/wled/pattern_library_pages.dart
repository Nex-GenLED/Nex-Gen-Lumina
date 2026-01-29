import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/wled_models.dart' show kEffectNames;
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
import 'package:nexgen_command/nav.dart' show AppRoutes;
import 'package:nexgen_command/widgets/color_behavior_badge.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/features/wled/effect_mood_system.dart';

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
    // Watch smart personalized recommendations (async) and user profile for greeting
    final recsAsync = ref.watch(smartRecommendedPatternsProvider);
    final recs = recsAsync.maybeWhen(
      data: (patterns) => patterns,
      orElse: () => ref.read(recommendedPatternsProvider), // Fallback to sync provider while loading
    );
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
          // Conditional rendering based on search state
          if (_isSearching)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(height: 12),
                  Text('Searching design library...', style: Theme.of(context).textTheme.bodyLarge),
                ]),
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
                    )
                  : _LibrarySearchResultsView(
                      results: _searchResults!,
                      query: _currentQuery,
                    ),
            )
          else
            // Default explore content (no active search)
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 120),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // 1. My Saved Designs section (at top)
                  _pagePadding(child: const _MySavedDesignsSection()),

                  // 2. Recommended for You section
                  _pagePadding(
                    child: PatternCategoryRow(title: _greetingTitle(), patterns: recs, query: '', isFeatured: true),
                  ),
                  _gap(24),

                  // 3. Recent Patterns section
                  _pagePadding(child: const _RecentPatternsSection()),

                  // 4. Pinned Categories section (user-added folders, in order added)
                  _pagePadding(child: const _PinnedCategoriesSection()),

                  // 5. Browse Design Library section (at bottom)
                  _pagePadding(
                    child: _DesignLibraryBrowser(),
                  ),
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

// GradientPattern moved to pattern_models.dart to enable reuse across providers

/// Widget shown when search finds no matches in the existing library.
/// Provides friendly message and options to create custom patterns.
class _NoMatchRedirectWidget extends StatelessWidget {
  final String query;
  final VoidCallback onClearSearch;

  const _NoMatchRedirectWidget({
    required this.query,
    required this.onClearSearch,
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
            onTap: () => context.go('/lumina'),
          ),
          const SizedBox(height: 16),

          // Option 2: Design Studio
          _RedirectOptionCard(
            icon: Icons.palette_outlined,
            iconColor: NexGenPalette.violet,
            title: 'Build it in Design Studio',
            description: "Pick your colors, choose your effects, and create exactly what you're thinking.",
            buttonText: 'Open Design Studio',
            onTap: () => context.push('/design-studio'),
          ),
          const SizedBox(height: 24),

          // Clear search link
          TextButton(
            onPressed: onClearSearch,
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
                padding: const EdgeInsets.symmetric(vertical: 12),
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
            onTap: () => context.push('/library/${palette.id}'),
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
            onTap: () => context.push('/library/${folder.id}'),
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
          ...results.patterns.map((pattern) => _PatternCard(
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

/// Browse Design Library section with category cards
class _DesignLibraryBrowser extends ConsumerWidget {
  const _DesignLibraryBrowser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(patternCategoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Browse Design Library',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'Explore all categories',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: NexGenPalette.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Category grid
        categoriesAsync.when(
          data: (categories) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.6,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return _DesignLibraryCategoryCard(category: category);
            },
          ),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, __) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load categories',
                style: TextStyle(color: NexGenPalette.textSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Individual category card for the Design Library browser
class _DesignLibraryCategoryCard extends ConsumerWidget {
  final PatternCategory category;

  const _DesignLibraryCategoryCard({required this.category});

  /// Returns a list of themed icons that represent the category's content.
  /// Each category gets 4-6 relevant icons to display in a grid.
  List<IconData> _iconsForCategory(String categoryId) {
    switch (categoryId) {
      case 'cat_arch':
        // Architectural / Downlighting
        return const [
          Icons.home_outlined,
          Icons.villa_outlined,
          Icons.apartment_outlined,
          Icons.cottage_outlined,
          Icons.deck_outlined,
          Icons.fence_outlined,
        ];
      case 'cat_holiday':
        // Holidays - themed icons for major holidays
        return const [
          Icons.park_outlined, // Christmas tree
          Icons.ac_unit, // Winter/snowflake
          Icons.egg_outlined, // Easter
          Icons.favorite_outline, // Valentine's
          Icons.flag_outlined, // 4th of July
          Icons.local_florist_outlined, // St. Patrick's (clover-like)
        ];
      case 'cat_sports':
        // Game Day Fan Zone - sports icons
        return const [
          Icons.sports_football_outlined,
          Icons.sports_baseball_outlined,
          Icons.sports_basketball_outlined,
          Icons.sports_hockey_outlined,
          Icons.sports_soccer_outlined,
          Icons.emoji_events_outlined, // Trophy
        ];
      case 'cat_season':
        // Seasonal Vibes
        return const [
          Icons.wb_sunny_outlined, // Summer
          Icons.eco_outlined, // Spring
          Icons.park_outlined, // Fall/Autumn
          Icons.ac_unit, // Winter
          Icons.cloud_outlined,
          Icons.nights_stay_outlined,
        ];
      case 'cat_party':
        // Parties & Events
        return const [
          Icons.cake_outlined, // Birthday
          Icons.music_note_outlined,
          Icons.celebration_outlined,
          Icons.local_bar_outlined,
          Icons.star_outline,
          Icons.auto_awesome_outlined,
        ];
      case 'cat_security':
        // Security & Alerts
        return const [
          Icons.security_outlined,
          Icons.shield_outlined,
          Icons.notifications_active_outlined,
          Icons.visibility_outlined,
          Icons.warning_amber_outlined,
          Icons.lightbulb_outlined,
        ];
      case 'cat_movies':
        // Movies & Superheroes
        return const [
          Icons.movie_outlined,
          Icons.theaters_outlined,
          Icons.bolt_outlined, // Superhero/power
          Icons.local_movies_outlined,
          Icons.star_outline,
          Icons.flash_on_outlined,
        ];
      default:
        return const [
          Icons.palette_outlined,
          Icons.color_lens_outlined,
          Icons.gradient_outlined,
          Icons.auto_awesome_outlined,
        ];
    }
  }

  /// Returns accent color for each category (used for icon highlights and glow).
  Color _accentForCategory(String categoryId) {
    switch (categoryId) {
      case 'cat_arch':
        return const Color(0xFFFFB347); // Warm amber
      case 'cat_holiday':
        return const Color(0xFFFF4444); // Festive red
      case 'cat_sports':
        return const Color(0xFFFFD700); // Championship gold
      case 'cat_season':
        return const Color(0xFF00E5FF); // Cyan
      case 'cat_party':
        return const Color(0xFFFF69B4); // Party pink
      case 'cat_security':
        return const Color(0xFF4FC3F7); // Alert blue
      case 'cat_movies':
        return const Color(0xFFE040FB); // Cinema purple
      default:
        return NexGenPalette.cyan;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icons = _iconsForCategory(category.id);
    final accentColor = _accentForCategory(category.id);
    final pinnedIds = ref.watch(pinnedCategoryIdsProvider);
    final isPinned = pinnedIds.contains(category.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push(
            '/library/${category.id}',
            extra: {'name': category.name},
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            // Premium dark background with subtle gradient
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                NexGenPalette.gunmetal90,
                NexGenPalette.matteBlack.withValues(alpha: 0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Subtle accent glow in corner
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accentColor.withValues(alpha: 0.15),
                        accentColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon grid - display themed icons
                    Expanded(
                      child: _buildIconGrid(icons, accentColor),
                    ),
                    const SizedBox(height: 8),
                    // Category name
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: accentColor.withValues(alpha: 0.7),
                          size: 12,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Pin button
              Positioned(
                right: 4,
                top: 4,
                child: GestureDetector(
                  onTap: () => _togglePin(context, ref, isPinned),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: isPinned ? NexGenPalette.cyan : Colors.white.withValues(alpha: 0.7),
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a grid of themed icons with accent color highlights.
  Widget _buildIconGrid(List<IconData> icons, Color accentColor) {
    // Take up to 6 icons, arrange in 2 rows of 3
    final displayIcons = icons.take(6).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate icon size based on available space
        final iconSize = (constraints.maxWidth - 16) / 3.5;

        return Wrap(
          spacing: 4,
          runSpacing: 2,
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          children: displayIcons.asMap().entries.map((entry) {
            final index = entry.key;
            final icon = entry.value;

            // Alternate between accent color and muted for visual interest
            final isHighlighted = index % 2 == 0;
            final iconColor = isHighlighted
                ? accentColor
                : Colors.white.withValues(alpha: 0.5);

            return SizedBox(
              width: iconSize,
              height: iconSize,
              child: Icon(
                icon,
                color: iconColor,
                size: iconSize * 0.7,
                shadows: isHighlighted
                    ? [
                        Shadow(
                          color: accentColor.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _togglePin(BuildContext context, WidgetRef ref, bool isPinned) async {
    final notifier = ref.read(pinnedCategoriesNotifierProvider.notifier);
    final success = isPinned
        ? await notifier.unpinCategory(category.id)
        : await notifier.pinCategory(category.id);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (isPinned ? 'Folder unpinned' : 'Folder pinned to Explore')
                : 'Failed to update pin status',
          ),
        ),
      );
    }
  }
}

/// Section for displaying user's saved custom designs
class _MySavedDesignsSection extends ConsumerWidget {
  const _MySavedDesignsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final designsAsync = ref.watch(designsStreamProvider);

    return designsAsync.when(
      data: (designs) {
        if (designs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header with manage button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined, color: NexGenPalette.cyan, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'My Saved Designs',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    // Navigate to My Designs screen for full management
                    context.push('/designs');
                  },
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Manage'),
                  style: TextButton.styleFrom(
                    foregroundColor: NexGenPalette.cyan,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Horizontal scrolling list of saved designs
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: designs.length.clamp(0, 10), // Max 10 visible
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final design = designs[index];
                  return _SavedDesignCard(
                    design: design,
                    onTap: () => _applyDesign(context, ref, design),
                    onRemove: () => _confirmRemoveDesign(context, ref, design),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _applyDesign(BuildContext context, WidgetRef ref, CustomDesign design) async {
    // Check for active neighborhood sync before changing lights
    final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No device connected')),
        );
      }
      return;
    }

    try {
      final payload = design.toWledPayload();
      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = design.name;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Applied: ${design.name}')),
        );
      }
    } catch (e) {
      debugPrint('Apply design failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to apply design')),
        );
      }
    }
  }

  Future<void> _confirmRemoveDesign(BuildContext context, WidgetRef ref, CustomDesign design) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Design?'),
        content: Text('Remove "${design.name}" from your saved designs?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final deleteDesign = ref.read(deleteDesignProvider);
      final success = await deleteDesign(design.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Design removed' : 'Failed to remove design'),
          ),
        );
      }
    }
  }
}

/// Card for displaying a saved design
class _SavedDesignCard extends StatelessWidget {
  final CustomDesign design;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _SavedDesignCard({
    required this.design,
    required this.onTap,
    required this.onRemove,
  });

  List<Color> _extractColors() {
    final colors = <Color>[];
    for (final channel in design.channels.where((ch) => ch.included)) {
      for (final group in channel.colorGroups.take(3)) {
        if (group.color.length >= 3) {
          colors.add(Color.fromARGB(
            255,
            group.color[0].clamp(0, 255),
            group.color[1].clamp(0, 255),
            group.color[2].clamp(0, 255),
          ));
        }
      }
    }
    if (colors.isEmpty) {
      return [NexGenPalette.violet, NexGenPalette.cyan];
    }
    return colors.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _extractColors();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors.length == 1 ? [colors[0], colors[0]] : colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Dark overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
            ),
            // Remove button
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
            // Design name
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(
                design.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4)],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section for displaying user's recently used patterns
class _RecentPatternsSection extends ConsumerWidget {
  const _RecentPatternsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentPatternsProvider);

    return recentAsync.when(
      data: (patterns) {
        if (patterns.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              children: [
                Icon(Icons.history_rounded, color: NexGenPalette.cyan, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Recent Patterns',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Horizontal scrolling list of recent patterns (most recent on left)
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: patterns.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final pattern = patterns[index];
                  return _RecentPatternCard(
                    pattern: pattern,
                    onTap: () => _applyPattern(context, ref, pattern),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _applyPattern(BuildContext context, WidgetRef ref, GradientPattern pattern) async {
    // Check for active neighborhood sync before changing lights
    final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No device connected')),
        );
      }
      return;
    }

    try {
      // Build WLED JSON payload from pattern
      final colors = pattern.colors.map((c) {
        final rgbw = rgbToRgbw(
          (c.r * 255).round(),
          (c.g * 255).round(),
          (c.b * 255).round(),
          forceZeroWhite: true,
        );
        return [rgbw[0], rgbw[1], rgbw[2], rgbw[3]];
      }).toList();

      final payload = {
        'on': true,
        'bri': pattern.brightness,
        'seg': [
          {
            'fx': pattern.effectId,
            'sx': pattern.speed,
            'ix': pattern.intensity,
            'col': colors.isNotEmpty ? colors.take(3).toList() : [[255, 180, 100, 0]],
          }
        ],
      };

      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = pattern.name;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Applied: ${pattern.name}')),
        );
      }
    } catch (e) {
      debugPrint('Apply recent pattern failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to apply pattern')),
        );
      }
    }
  }
}

/// Card for displaying a recent pattern
class _RecentPatternCard extends StatelessWidget {
  final GradientPattern pattern;
  final VoidCallback onTap;

  const _RecentPatternCard({
    required this.pattern,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = pattern.colors.isNotEmpty
        ? pattern.colors
        : const [Color(0xFFFFB347), Color(0xFFFFE4B5)];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors.length == 1 ? [colors[0], colors[0]] : colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Dark overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
            ),
            // Time ago badge
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  pattern.subtitle ?? '',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
            // Pattern name
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(
                pattern.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4)],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section for displaying user's pinned categories
class _PinnedCategoriesSection extends ConsumerWidget {
  const _PinnedCategoriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinnedAsync = ref.watch(pinnedCategoriesProvider);

    return pinnedAsync.when(
      data: (pinnedCategories) {
        if (pinnedCategories.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final pinned in pinnedCategories) ...[
              _PinnedCategoryRow(pinnedData: pinned),
              const SizedBox(height: 24),
            ],
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Row showing a pinned category with its patterns
class _PinnedCategoryRow extends ConsumerWidget {
  final PinnedCategoryData pinnedData;

  const _PinnedCategoryRow({required this.pinnedData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with unpin button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.push_pin, color: NexGenPalette.cyan, size: 18),
                const SizedBox(width: 8),
                Text(
                  pinnedData.category.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    // Navigate to category detail
                    context.push(
                      AppRoutes.patternCategory.replaceFirst(':categoryId', pinnedData.category.id),
                      extra: pinnedData.category,
                    );
                  },
                  child: const Text('See All'),
                  style: TextButton.styleFrom(foregroundColor: NexGenPalette.textSecondary),
                ),
                IconButton(
                  onPressed: () => _confirmUnpin(context, ref),
                  icon: const Icon(Icons.close, size: 18),
                  color: NexGenPalette.textSecondary,
                  tooltip: 'Unpin folder',
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Sub-categories as horizontal scrolling chips
        if (pinnedData.subCategories.isNotEmpty)
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: pinnedData.subCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final subCat = pinnedData.subCategories[index];
                return _SubCategoryChip(
                  subCategory: subCat,
                  categoryId: pinnedData.category.id,
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _confirmUnpin(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpin Folder?'),
        content: Text('Remove "${pinnedData.category.name}" from your Explore page?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unpin'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final notifier = ref.read(pinnedCategoriesNotifierProvider.notifier);
      final success = await notifier.unpinCategory(pinnedData.category.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Folder unpinned' : 'Failed to unpin folder'),
          ),
        );
      }
    }
  }
}

/// Chip showing a sub-category within a pinned category
class _SubCategoryChip extends StatelessWidget {
  final SubCategory subCategory;
  final String categoryId;

  const _SubCategoryChip({
    required this.subCategory,
    required this.categoryId,
  });

  @override
  Widget build(BuildContext context) {
    final colors = subCategory.themeColors;

    return GestureDetector(
      onTap: () {
        // Navigate to theme selection for this sub-category
        context.push(
          AppRoutes.patternSubCategory
              .replaceFirst(':categoryId', categoryId)
              .replaceFirst(':subId', subCategory.id),
          extra: subCategory.name,
        );
      },
      child: Container(
        width: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors.isEmpty
                ? [NexGenPalette.violet, NexGenPalette.cyan]
                : (colors.length == 1 ? [colors[0], colors[0]] : colors),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            // Dark overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.5),
                    ],
                  ),
                ),
              ),
            ),
            // Name
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  subCategory.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4)],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        // Check for active neighborhood sync before changing lights
        final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
        if (!shouldProceed) return;

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
    // Check for active neighborhood sync before changing lights
    final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
      }
      return;
    }
    try {
      // Use the pattern's toWledPayload() method for proper effect/speed/intensity
      final success = await repo.applyJson(data.toWledPayload());

      if (!success) {
        throw Exception('Device did not accept command');
      }

      // Update the active preset label so home screen reflects the change
      ref.read(activePresetLabelProvider.notifier).state = data.name;

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
    final pinnedIds = ref.watch(pinnedCategoryIdsProvider);
    final isPinned = pinnedIds.contains(categoryId);
    final title = categoryName ?? 'Explore';
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: Icon(
              isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: isPinned ? NexGenPalette.cyan : Colors.white,
            ),
            tooltip: isPinned ? 'Unpin from Explore' : 'Pin to Explore',
            onPressed: () => _togglePin(context, ref, isPinned),
          ),
        ],
      ),
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

  Future<void> _togglePin(BuildContext context, WidgetRef ref, bool isPinned) async {
    final notifier = ref.read(pinnedCategoriesNotifierProvider.notifier);
    final success = isPinned
        ? await notifier.unpinCategory(categoryId)
        : await notifier.pinCategory(categoryId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (isPinned ? 'Folder unpinned from Explore' : 'Folder pinned to Explore')
                : 'Failed to update pin status',
          ),
        ),
      );
    }
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
        // Check for active neighborhood sync before changing lights
        final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
        if (!shouldProceed) return;

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

// ============================================================================
// LIBRARY BROWSER SCREEN - Unified hierarchical navigation
// ============================================================================

/// Unified browser screen for navigating the library hierarchy.
/// Shows root categories when nodeId is null, otherwise shows children of that node.
/// Displays pattern grid for palette nodes, folder grid for intermediate nodes.
class LibraryBrowserScreen extends ConsumerWidget {
  final String? nodeId;
  final String? nodeName;

  const LibraryBrowserScreen({super.key, this.nodeId, this.nodeName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get current node (if any) and children
    final nodeAsync = nodeId != null
        ? ref.watch(libraryNodeByIdProvider(nodeId!))
        : const AsyncValue<LibraryNode?>.data(null);
    final childrenAsync = ref.watch(libraryChildNodesProvider(nodeId));
    final ancestorsAsync = nodeId != null
        ? ref.watch(libraryAncestorsProvider(nodeId!))
        : const AsyncValue<List<LibraryNode>>.data([]);

    return Scaffold(
      backgroundColor: NexGenPalette.gunmetal,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App bar with back button and title
            _LibraryAppBar(
              nodeId: nodeId,
              nodeName: nodeName,
              nodeAsync: nodeAsync,
            ),
            // Breadcrumb navigation
            if (nodeId != null)
              ancestorsAsync.when(
                data: (ancestors) => _LibraryBreadcrumb(
                  ancestors: ancestors,
                  currentNodeName: nodeName,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            // Main content
            Expanded(
              child: childrenAsync.when(
                data: (children) {
                  // Check if this is a palette node - show patterns instead
                  return nodeAsync.when(
                    data: (node) {
                      if (node != null && node.isPalette) {
                        return _PalettePatternGrid(node: node);
                      }
                      // Show children as navigation grid
                      return _LibraryNodeGrid(children: children);
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, __) => _LibraryNodeGrid(children: children),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, __) => Center(
                  child: Text(
                    'Unable to load content',
                    style: TextStyle(color: NexGenPalette.textSecondary),
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

/// App bar for the library browser
class _LibraryAppBar extends StatelessWidget {
  final String? nodeId;
  final String? nodeName;
  final AsyncValue<LibraryNode?> nodeAsync;

  const _LibraryAppBar({
    required this.nodeId,
    required this.nodeName,
    required this.nodeAsync,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = nodeName ?? nodeAsync.whenOrNull(data: (n) => n?.name) ?? 'Design Library';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (nodeId != null)
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          if (nodeId != null) const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Breadcrumb navigation showing path from root to current node
class _LibraryBreadcrumb extends StatelessWidget {
  final List<LibraryNode> ancestors;
  final String? currentNodeName;

  const _LibraryBreadcrumb({
    required this.ancestors,
    this.currentNodeName,
  });

  @override
  Widget build(BuildContext context) {
    if (ancestors.isEmpty && currentNodeName == null) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Home/Library root
          GestureDetector(
            onTap: () {
              // Pop all the way back to library root
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: Row(
              children: [
                Icon(Icons.home, size: 16, color: NexGenPalette.cyan),
                const SizedBox(width: 4),
                Text(
                  'Library',
                  style: TextStyle(
                    color: NexGenPalette.cyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Ancestor breadcrumbs
          for (final ancestor in ancestors) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.chevron_right, size: 16, color: NexGenPalette.textSecondary),
            ),
            GestureDetector(
              onTap: () {
                // Navigate back to this ancestor
                final popsNeeded = ancestors.indexOf(ancestor) + 1;
                for (var i = 0; i < ancestors.length - popsNeeded + 1; i++) {
                  Navigator.of(context).pop();
                }
              },
              child: Text(
                ancestor.name,
                style: TextStyle(
                  color: NexGenPalette.cyan,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          // Current node (not clickable)
          if (currentNodeName != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.chevron_right, size: 16, color: NexGenPalette.textSecondary),
            ),
            Text(
              currentNodeName!,
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grid of library nodes (categories, folders, or palettes)
class _LibraryNodeGrid extends StatelessWidget {
  final List<LibraryNode> children;

  const _LibraryNodeGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Center(
        child: Text(
          'No items found',
          style: TextStyle(color: NexGenPalette.textSecondary),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) {
        final node = children[index];
        return _LibraryNodeCard(node: node);
      },
    );
  }
}

/// Individual node card for navigation
class _LibraryNodeCard extends StatelessWidget {
  final LibraryNode node;

  const _LibraryNodeCard({required this.node});

  /// Returns a list of themed icons for the node (used in grid display).
  /// Each folder type gets 4-6 relevant icons.
  List<IconData> _iconsForNode() {
    final id = node.id;

    // Sports leagues
    if (id == 'league_nfl') {
      return const [
        Icons.sports_football_outlined,
        Icons.stadium_outlined,
        Icons.emoji_events_outlined,
        Icons.groups_outlined,
        Icons.flag_outlined,
        Icons.star_outline,
      ];
    }
    if (id == 'league_nba') {
      return const [
        Icons.sports_basketball_outlined,
        Icons.stadium_outlined,
        Icons.emoji_events_outlined,
        Icons.groups_outlined,
        Icons.star_outline,
        Icons.leaderboard_outlined,
      ];
    }
    if (id == 'league_mlb') {
      return const [
        Icons.sports_baseball_outlined,
        Icons.stadium_outlined,
        Icons.emoji_events_outlined,
        Icons.groups_outlined,
        Icons.star_outline,
        Icons.diamond_outlined,
      ];
    }
    if (id == 'league_nhl') {
      return const [
        Icons.sports_hockey_outlined,
        Icons.ac_unit,
        Icons.emoji_events_outlined,
        Icons.groups_outlined,
        Icons.star_outline,
        Icons.shield_outlined,
      ];
    }
    if (id == 'league_mls') {
      return const [
        Icons.sports_soccer_outlined,
        Icons.stadium_outlined,
        Icons.emoji_events_outlined,
        Icons.groups_outlined,
        Icons.star_outline,
        Icons.public_outlined,
      ];
    }
    if (id == 'league_wnba') {
      return const [
        Icons.sports_basketball_outlined,
        Icons.female_outlined,
        Icons.emoji_events_outlined,
        Icons.star_outline,
        Icons.stadium_outlined,
        Icons.groups_outlined,
      ];
    }
    // NWSL - Women's Professional Soccer League
    if (id == 'league_nwsl') {
      return const [
        Icons.sports_soccer_outlined,
        Icons.female_outlined,
        Icons.emoji_events_outlined,
        Icons.stadium_outlined,
        Icons.shield_outlined,
        Icons.star_outline,
      ];
    }

    // NCAA Football
    if (id == 'ncaa_football') {
      return const [
        Icons.sports_football_outlined,
        Icons.school_outlined,
        Icons.emoji_events_outlined,
        Icons.stadium_outlined,
        Icons.military_tech_outlined,
        Icons.star_outline,
      ];
    }
    // NCAA Basketball
    if (id == 'ncaa_basketball') {
      return const [
        Icons.sports_basketball_outlined,
        Icons.school_outlined,
        Icons.emoji_events_outlined,
        Icons.stadium_outlined,
        Icons.military_tech_outlined,
        Icons.star_outline,
      ];
    }
    // NCAA Football Conference folders (SEC, Big Ten, ACC, etc.)
    if (id.startsWith('ncaafb_')) {
      return const [
        Icons.sports_football_outlined,
        Icons.school_outlined,
        Icons.groups_outlined,
        Icons.emoji_events_outlined,
        Icons.stadium_outlined,
        Icons.leaderboard_outlined,
      ];
    }
    // NCAA Basketball Conference folders
    if (id.startsWith('ncaabb_')) {
      return const [
        Icons.sports_basketball_outlined,
        Icons.school_outlined,
        Icons.groups_outlined,
        Icons.emoji_events_outlined,
        Icons.stadium_outlined,
        Icons.leaderboard_outlined,
      ];
    }
    if (id.startsWith('conf_')) {
      return const [
        Icons.groups_outlined,
        Icons.school_outlined,
        Icons.emoji_events_outlined,
        Icons.star_outline,
        Icons.stadium_outlined,
        Icons.leaderboard_outlined,
      ];
    }

    // Holiday sub-folders
    if (id == 'holiday_christmas') {
      return const [
        Icons.park_outlined,
        Icons.ac_unit,
        Icons.card_giftcard_outlined,
        Icons.star_outline,
        Icons.celebration_outlined,
        Icons.nights_stay_outlined,
      ];
    }
    if (id == 'holiday_halloween') {
      return const [
        Icons.nightlight_outlined,
        Icons.pest_control_outlined,
        Icons.local_fire_department_outlined,
        Icons.nights_stay_outlined,
        Icons.auto_awesome_outlined,
        Icons.face_outlined,
      ];
    }
    // 4th of July - American flag, fireworks, USA patriotic theme
    if (id == 'holiday_july4' || id == 'holiday_july4th') {
      return const [
        Icons.flag_outlined,              // American flag
        Icons.auto_awesome_outlined,      // Fireworks/sparklers
        Icons.star_outline,               // Stars (USA)
        Icons.local_fire_department_outlined, // Fireworks explosion
        Icons.celebration_outlined,       // Celebration
        Icons.public_outlined,            // USA/globe
      ];
    }
    if (id == 'holiday_valentines') {
      return const [
        Icons.favorite_outline,
        Icons.favorite_border,
        Icons.local_florist_outlined,
        Icons.card_giftcard_outlined,
        Icons.star_outline,
        Icons.auto_awesome_outlined,
      ];
    }
    // St. Patrick's Day - shamrock/clover, pot of gold, leprechaun theme
    if (id == 'holiday_stpatricks') {
      return const [
        Icons.eco_outlined,               // 4-leaf clover/shamrock
        Icons.paid_outlined,              // Pot of gold coins
        Icons.local_bar_outlined,         // Irish pub/beer
        Icons.local_florist_outlined,     // Clover/green plants
        Icons.looks_outlined,             // Rainbow (to pot of gold)
        Icons.auto_awesome_outlined,      // Lucky sparkle/magic
      ];
    }
    if (id == 'holiday_easter') {
      return const [
        Icons.egg_outlined,
        Icons.local_florist_outlined,
        Icons.grass_outlined,
        Icons.wb_sunny_outlined,
        Icons.star_outline,
        Icons.auto_awesome_outlined,
      ];
    }
    if (id == 'holiday_thanksgiving') {
      return const [
        Icons.eco_outlined,
        Icons.restaurant_outlined,
        Icons.home_outlined,
        Icons.favorite_outline,
        Icons.park_outlined,
        Icons.celebration_outlined,
      ];
    }
    // New Year's Eve - champagne, clock midnight, disco ball, confetti theme
    if (id == 'holiday_newyears' || id == 'holiday_newyear') {
      return const [
        Icons.local_bar_outlined,         // Champagne glass
        Icons.schedule_outlined,          // Clock striking midnight
        Icons.blur_circular_outlined,     // Disco ball
        Icons.celebration_outlined,       // Confetti/celebration
        Icons.auto_awesome_outlined,      // Fireworks/sparkle
        Icons.music_note_outlined,        // Party music
      ];
    }

    // Season sub-folders
    if (id == 'season_spring') {
      return const [
        Icons.local_florist_outlined,
        Icons.grass_outlined,
        Icons.wb_sunny_outlined,
        Icons.water_drop_outlined,
        Icons.eco_outlined,
        Icons.park_outlined,
      ];
    }
    if (id == 'season_summer') {
      return const [
        Icons.wb_sunny_outlined,
        Icons.beach_access_outlined,
        Icons.pool_outlined,
        Icons.icecream_outlined,
        Icons.waves_outlined,
        Icons.star_outline,
      ];
    }
    if (id == 'season_autumn') {
      return const [
        Icons.park_outlined,
        Icons.eco_outlined,
        Icons.air_outlined,
        Icons.local_fire_department_outlined,
        Icons.nights_stay_outlined,
        Icons.coffee_outlined,
      ];
    }
    if (id == 'season_winter') {
      return const [
        Icons.ac_unit,
        Icons.nights_stay_outlined,
        Icons.cloud_outlined,
        Icons.local_fire_department_outlined,
        Icons.star_outline,
        Icons.home_outlined,
      ];
    }

    // Party/event sub-folders
    // Birthdays parent folder
    if (id == 'event_birthdays' || id == 'event_birthday') {
      return const [
        Icons.cake_outlined,              // Birthday cake
        Icons.celebration_outlined,       // Party celebration
        Icons.card_giftcard_outlined,     // Presents
        Icons.emoji_emotions_outlined,    // Happy faces
        Icons.music_note_outlined,        // Party music
        Icons.auto_awesome_outlined,      // Candle sparkle
      ];
    }
    // Boy Birthday - superhero, dinosaur, sports, adventure themes
    if (id == 'event_bday_boy') {
      return const [
        Icons.rocket_launch_outlined,     // Space/adventure
        Icons.sports_soccer_outlined,     // Sports
        Icons.videogame_asset_outlined,   // Gaming
        Icons.pets_outlined,              // Dinosaur/animals
        Icons.bolt_outlined,              // Superhero power
        Icons.directions_car_outlined,    // Race cars/trucks
      ];
    }
    // Girl Birthday - princess, unicorn, fairy, magical themes
    if (id == 'event_bday_girl') {
      return const [
        Icons.auto_awesome_outlined,      // Magic sparkle/unicorn
        Icons.local_florist_outlined,     // Flowers/fairy garden
        Icons.favorite_outline,           // Hearts/love
        Icons.star_outline,               // Princess star
        Icons.pets_outlined,              // Animals/butterflies
        Icons.castle_outlined,            // Princess castle
      ];
    }
    // Adult Birthday - elegant, party, celebration themes
    if (id == 'event_bday_adult') {
      return const [
        Icons.local_bar_outlined,         // Cocktails/champagne
        Icons.celebration_outlined,       // Party celebration
        Icons.music_note_outlined,        // Party music
        Icons.cake_outlined,              // Birthday cake
        Icons.star_outline,               // Milestone star
        Icons.emoji_events_outlined,      // Trophy/achievement
      ];
    }
    // Weddings - romance, flowers, rings, elegance
    if (id == 'event_weddings' || id == 'event_wedding') {
      return const [
        Icons.favorite_outline,           // Love/hearts
        Icons.diamond_outlined,           // Wedding rings
        Icons.local_florist_outlined,     // Wedding flowers
        Icons.celebration_outlined,       // Celebration
        Icons.music_note_outlined,        // Wedding music
        Icons.church_outlined,            // Ceremony
      ];
    }
    // Baby Shower - babies, gifts, soft themes
    if (id == 'event_babyshower') {
      return const [
        Icons.child_care_outlined,        // Baby
        Icons.child_friendly_outlined,    // Stroller
        Icons.card_giftcard_outlined,     // Baby gifts
        Icons.favorite_outline,           // Love/hearts
        Icons.cloud_outlined,             // Soft clouds
        Icons.star_outline,               // Twinkle stars
      ];
    }
    // Graduation - academic, achievement, celebration
    if (id == 'event_graduation') {
      return const [
        Icons.school_outlined,            // Graduation cap
        Icons.workspace_premium_outlined, // Diploma/certificate
        Icons.emoji_events_outlined,      // Achievement trophy
        Icons.celebration_outlined,       // Celebration
        Icons.auto_awesome_outlined,      // Success sparkle
        Icons.star_outline,               // Achievement star
      ];
    }
    // Anniversary - romance, milestone, elegance
    if (id == 'event_anniversary') {
      return const [
        Icons.favorite_outline,           // Love/hearts
        Icons.diamond_outlined,           // Diamond anniversary
        Icons.local_bar_outlined,         // Champagne toast
        Icons.local_florist_outlined,     // Anniversary flowers
        Icons.celebration_outlined,       // Celebration
        Icons.auto_awesome_outlined,      // Sparkle/romance
      ];
    }

    // Movie franchises
    if (id == 'franchise_disney') {
      return const [
        Icons.castle_outlined,
        Icons.star_outline,
        Icons.auto_awesome_outlined,
        Icons.movie_outlined,
        Icons.music_note_outlined,
        Icons.favorite_outline,
      ];
    }
    if (id == 'franchise_marvel') {
      return const [
        Icons.shield_outlined,
        Icons.bolt_outlined,
        Icons.star_outline,
        Icons.flash_on_outlined,
        Icons.military_tech_outlined,
        Icons.movie_outlined,
      ];
    }
    if (id == 'franchise_starwars') {
      return const [
        Icons.star_outline,
        Icons.nights_stay_outlined,
        Icons.flash_on_outlined,
        Icons.rocket_launch_outlined,
        Icons.movie_outlined,
        Icons.auto_awesome_outlined,
      ];
    }
    if (id == 'franchise_dc') {
      return const [
        Icons.bolt_outlined,
        Icons.shield_outlined,
        Icons.star_outline,
        Icons.flash_on_outlined,
        Icons.nights_stay_outlined,
        Icons.movie_outlined,
      ];
    }
    if (id == 'franchise_pixar') {
      return const [
        Icons.animation_outlined,
        Icons.auto_awesome_outlined,
        Icons.star_outline,
        Icons.lightbulb_outlined,
        Icons.movie_outlined,
        Icons.favorite_outline,
      ];
    }
    if (id == 'franchise_dreamworks') {
      return const [
        Icons.movie_filter_outlined,
        Icons.auto_awesome_outlined,
        Icons.star_outline,
        Icons.animation_outlined,
        Icons.pets_outlined,
        Icons.movie_outlined,
      ];
    }
    if (id == 'franchise_harrypotter') {
      return const [
        Icons.auto_fix_high_outlined,
        Icons.castle_outlined,
        Icons.star_outline,
        Icons.flash_on_outlined,
        Icons.nights_stay_outlined,
        Icons.movie_outlined,
      ];
    }
    if (id == 'franchise_nintendo') {
      return const [
        Icons.videogame_asset_outlined,
        Icons.star_outline,
        Icons.gamepad_outlined,
        Icons.sports_esports_outlined,
        Icons.auto_awesome_outlined,
        Icons.emoji_events_outlined,
      ];
    }

    // Default fallback icons
    if (node.isPalette) {
      return const [
        Icons.palette_outlined,
        Icons.color_lens_outlined,
        Icons.gradient_outlined,
        Icons.auto_awesome_outlined,
      ];
    }
    return const [
      Icons.folder_outlined,
      Icons.category_outlined,
      Icons.grid_view_outlined,
      Icons.auto_awesome_outlined,
    ];
  }

  IconData _iconForNode() {
    final id = node.id;

    // Category icons
    if (id.startsWith('cat_')) {
      switch (id) {
        case LibraryCategoryIds.architectural:
          return Icons.home_outlined;
        case LibraryCategoryIds.holidays:
          return Icons.celebration_outlined;
        case LibraryCategoryIds.sports:
          return Icons.sports_football_outlined;
        case LibraryCategoryIds.seasonal:
          return Icons.wb_sunny_outlined;
        case LibraryCategoryIds.parties:
          return Icons.party_mode_outlined;
        case LibraryCategoryIds.security:
          return Icons.security_outlined;
        case LibraryCategoryIds.movies:
          return Icons.movie_outlined;
      }
    }

    // Sports folders
    if (id.startsWith('league_')) return Icons.sports;
    if (id.contains('ncaa')) return Icons.school_outlined;
    if (id.startsWith('conf_')) return Icons.groups_outlined;

    // Holiday/seasonal folders
    if (id.startsWith('holiday_')) return Icons.celebration;
    if (id.startsWith('season_')) return Icons.nature_outlined;
    if (id.startsWith('event_')) return Icons.event_outlined;

    // Movie franchise folders
    if (id == 'franchise_disney') return Icons.castle_outlined;
    if (id == 'franchise_marvel') return Icons.shield_outlined;
    if (id == 'franchise_starwars') return Icons.star_outlined;
    if (id == 'franchise_dc') return Icons.bolt_outlined;
    if (id == 'franchise_pixar') return Icons.animation_outlined;
    if (id == 'franchise_dreamworks') return Icons.movie_filter_outlined;
    if (id == 'franchise_harrypotter') return Icons.auto_fix_high_outlined;
    if (id == 'franchise_nintendo') return Icons.videogame_asset_outlined;

    // Default based on node type
    if (node.isPalette) return Icons.palette_outlined;
    return Icons.folder_outlined;
  }

  /// Get themed color for folder nodes (static, not flowing gradient)
  Color _getFolderThemeColor() {
    final id = node.id;

    // Category colors
    if (id == LibraryCategoryIds.architectural) return const Color(0xFFFF8C00);
    if (id == LibraryCategoryIds.holidays) return const Color(0xFFE53935);
    if (id == LibraryCategoryIds.sports) return const Color(0xFF1976D2);
    if (id == LibraryCategoryIds.seasonal) return const Color(0xFFE65100);
    if (id == LibraryCategoryIds.parties) return const Color(0xFF9C27B0);
    if (id == LibraryCategoryIds.security) return const Color(0xFFD32F2F);
    if (id == LibraryCategoryIds.movies) return const Color(0xFF6A1B9A);

    // Movie franchise colors
    if (id == 'franchise_disney') return const Color(0xFF1E88E5);
    if (id == 'franchise_marvel') return const Color(0xFFB71C1C);
    if (id == 'franchise_starwars') return const Color(0xFF212121);
    if (id == 'franchise_dc') return const Color(0xFF0D47A1);
    if (id == 'franchise_pixar') return const Color(0xFF43A047);
    if (id == 'franchise_dreamworks') return const Color(0xFF00838F);
    if (id == 'franchise_harrypotter') return const Color(0xFF5D4037);
    if (id == 'franchise_nintendo') return const Color(0xFFE53935);

    // Sports league colors
    if (id == 'league_nfl') return const Color(0xFF013369);
    if (id == 'league_nba') return const Color(0xFFC9082A);
    if (id == 'league_mlb') return const Color(0xFF041E42);
    if (id == 'league_nhl') return const Color(0xFF000000);
    if (id == 'league_mls') return const Color(0xFF3A5A40);
    if (id == 'league_wnba') return const Color(0xFFFF6F00);
    if (id == 'league_nwsl') return const Color(0xFF0D47A1);

    // Holiday colors
    if (id == 'holiday_christmas') return const Color(0xFFC62828);
    if (id == 'holiday_halloween') return const Color(0xFFFF6F00);
    if (id == 'holiday_july4' || id == 'holiday_july4th') return const Color(0xFF1565C0);
    if (id == 'holiday_valentines') return const Color(0xFFD81B60);
    if (id == 'holiday_stpatricks') return const Color(0xFF2E7D32);
    if (id == 'holiday_easter') return const Color(0xFF7B1FA2);
    if (id == 'holiday_thanksgiving') return const Color(0xFFE65100);
    if (id == 'holiday_newyears' || id == 'holiday_newyear') return const Color(0xFFFFD700);

    // Season colors
    if (id == 'season_spring') return const Color(0xFF4CAF50);
    if (id == 'season_summer') return const Color(0xFFFFC107);
    if (id == 'season_autumn') return const Color(0xFFFF5722);
    if (id == 'season_winter') return const Color(0xFF03A9F4);

    // NCAA Football conference colors
    if (id.startsWith('ncaafb_')) return const Color(0xFF8B0000);
    // NCAA Basketball conference colors
    if (id.startsWith('ncaabb_')) return const Color(0xFFFF6F00);
    // NCAA parent folder colors
    if (id.startsWith('ncaa_') || id.startsWith('conf_')) return const Color(0xFF1A237E);

    return NexGenPalette.cyan;
  }

  @override
  Widget build(BuildContext context) {
    // Palettes get flowing gradient cards, folders get solid themed cards
    if (node.isPalette) {
      return _buildPaletteCard(context);
    } else {
      return _buildFolderCard(context);
    }
  }

  /// Build a folder card with icon grid design matching main category cards
  Widget _buildFolderCard(BuildContext context) {
    final themeColor = _getFolderThemeColor();
    final icons = _iconsForNode();

    return GestureDetector(
      onTap: () {
        context.push('/library/${node.id}', extra: {'name': node.name});
      },
      child: Container(
        decoration: BoxDecoration(
          // Premium dark background with subtle gradient
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              NexGenPalette.gunmetal90,
              NexGenPalette.matteBlack.withValues(alpha: 0.95),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: themeColor.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: themeColor.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Subtle accent glow in corner
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      themeColor.withValues(alpha: 0.15),
                      themeColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon grid - display themed icons
                  Expanded(
                    child: _buildIconGrid(icons, themeColor),
                  ),
                  const SizedBox(height: 8),
                  // Folder name
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          node.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: themeColor.withValues(alpha: 0.7),
                        size: 12,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a grid of themed icons with accent color highlights.
  Widget _buildIconGrid(List<IconData> icons, Color accentColor) {
    // Take up to 6 icons, arrange in 2 rows of 3
    final displayIcons = icons.take(6).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate icon size based on available space
        final iconSize = (constraints.maxWidth - 16) / 3.5;

        return Wrap(
          spacing: 4,
          runSpacing: 2,
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          children: displayIcons.asMap().entries.map((entry) {
            final index = entry.key;
            final icon = entry.value;

            // Alternate between accent color and muted for visual interest
            final isHighlighted = index % 2 == 0;
            final iconColor = isHighlighted
                ? accentColor
                : Colors.white.withValues(alpha: 0.5);

            return SizedBox(
              width: iconSize,
              height: iconSize,
              child: Icon(
                icon,
                color: iconColor,
                size: iconSize * 0.7,
                shadows: isHighlighted
                    ? [
                        Shadow(
                          color: accentColor.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Build a palette card with flowing gradient colors
  Widget _buildPaletteCard(BuildContext context) {
    final colors = node.themeColors ?? [NexGenPalette.cyan, NexGenPalette.blue];
    final gradient = colors.length >= 2
        ? [colors[0], colors[1]]
        : [colors.first, colors.first.withValues(alpha: 0.7)];

    return GestureDetector(
      onTap: () {
        context.push('/library/${node.id}', extra: {'name': node.name});
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Subtle icon watermark
            Positioned(
              right: -15,
              bottom: -15,
              child: Icon(
                Icons.palette,
                size: 70,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Color dots preview at top
                  Row(
                    children: [
                      for (var i = 0; i < (colors.length > 4 ? 4 : colors.length); i++)
                        Container(
                          width: 16,
                          height: 16,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: colors[i],
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  // Text content
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black26, blurRadius: 2)],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (node.description != null)
                        Text(
                          node.description!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid of patterns generated from a palette node with mood filter
class _PalettePatternGrid extends ConsumerWidget {
  final LibraryNode node;

  const _PalettePatternGrid({required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch mood filter and filtered patterns
    final selectedMood = ref.watch(selectedMoodFilterProvider);
    final patternsAsync = ref.watch(filteredLibraryNodePatternsProvider(node.id));
    final moodCountsAsync = ref.watch(nodeMoodCountsProvider(node.id));

    return patternsAsync.when(
      data: (patterns) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Palette preview header
            if (node.themeColors != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Color Palette:',
                      style: TextStyle(
                        color: NexGenPalette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    for (final color in node.themeColors!)
                      Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: NexGenPalette.line),
                        ),
                      ),
                  ],
                ),
              ),
            // Mood filter bar
            _MoodFilterBar(
              selectedMood: selectedMood,
              moodCounts: moodCountsAsync.valueOrNull ?? {},
              onMoodSelected: (mood) {
                ref.read(selectedMoodFilterProvider.notifier).state = mood;
              },
            ),
            // Pattern count (updates based on filter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                selectedMood != null
                    ? '${patterns.length} ${selectedMood.label} Patterns'
                    : '${patterns.length} Patterns',
                style: TextStyle(
                  color: NexGenPalette.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Pattern grid or empty state
            Expanded(
              child: patterns.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            selectedMood?.icon ?? Icons.pattern,
                            size: 48,
                            color: NexGenPalette.textSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            selectedMood != null
                                ? 'No ${selectedMood.label} patterns available'
                                : 'No patterns available',
                            style: TextStyle(color: NexGenPalette.textSecondary),
                          ),
                          if (selectedMood != null) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                ref.read(selectedMoodFilterProvider.notifier).state = null;
                              },
                              child: const Text('Show All Patterns'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: patterns.length,
                      itemBuilder: (context, index) {
                        final pattern = patterns[index];
                        return _PatternCard(pattern: pattern);
                      },
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text(
          'Unable to load patterns',
          style: TextStyle(color: NexGenPalette.textSecondary),
        ),
      ),
    );
  }
}

/// Mood filter bar with horizontally scrollable chips
class _MoodFilterBar extends StatelessWidget {
  final EffectMood? selectedMood;
  final Map<EffectMood, int> moodCounts;
  final ValueChanged<EffectMood?> onMoodSelected;

  const _MoodFilterBar({
    required this.selectedMood,
    required this.moodCounts,
    required this.onMoodSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // "All" chip
            _MoodChip(
              label: 'All',
              emoji: '',
              isSelected: selectedMood == null,
              count: moodCounts.values.fold(0, (a, b) => a + b),
              onTap: () => onMoodSelected(null),
            ),
            const SizedBox(width: 8),
            // Mood chips
            for (final mood in EffectMoodSystem.displayOrder) ...[
              _MoodChip(
                label: mood.label,
                emoji: mood.emoji,
                isSelected: selectedMood == mood,
                count: moodCounts[mood] ?? 0,
                color: mood.color,
                onTap: () => onMoodSelected(selectedMood == mood ? null : mood),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Individual mood filter chip
class _MoodChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool isSelected;
  final int count;
  final Color? color;
  final VoidCallback onTap;

  const _MoodChip({
    required this.label,
    required this.emoji,
    required this.isSelected,
    required this.count,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? NexGenPalette.cyan;

    return GestureDetector(
      onTap: count > 0 || isSelected ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha: 0.2)
              : NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? chipColor : NexGenPalette.line,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji.isNotEmpty) ...[
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? chipColor : (count > 0 ? Colors.white : NexGenPalette.textSecondary),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? chipColor.withValues(alpha: 0.3)
                      : NexGenPalette.gunmetal,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? chipColor : NexGenPalette.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Individual pattern card with apply action
class _PatternCard extends ConsumerWidget {
  final PatternItem pattern;

  const _PatternCard({required this.pattern});

  /// Extract colors from wledPayload
  List<Color> _getColors() {
    try {
      final payload = pattern.wledPayload;
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final firstSeg = seg.first;
        if (firstSeg is Map) {
          final cols = firstSeg['col'];
          if (cols is List && cols.isNotEmpty) {
            final colors = <Color>[];
            for (final col in cols) {
              if (col is List && col.length >= 3) {
                colors.add(Color.fromARGB(
                  255,
                  (col[0] as num).toInt().clamp(0, 255),
                  (col[1] as num).toInt().clamp(0, 255),
                  (col[2] as num).toInt().clamp(0, 255),
                ));
              }
            }
            if (colors.isNotEmpty) return colors;
          }
        }
      }
    } catch (_) {}
    return [NexGenPalette.cyan, NexGenPalette.blue];
  }

  /// Extract effect ID from wledPayload
  int _getEffectId() {
    try {
      final payload = pattern.wledPayload;
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final firstSeg = seg.first;
        if (firstSeg is Map) {
          final fx = firstSeg['fx'];
          if (fx is int) return fx;
        }
      }
    } catch (_) {}
    return 0;
  }

  /// Get effect name from effect ID
  String? _getEffectName() {
    final effectId = _getEffectId();
    return kEffectNames[effectId];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = _getColors();
    final effectId = _getEffectId();
    final effectName = _getEffectName();

    return GestureDetector(
      onTap: () async {
        await _applyPattern(context, ref);
      },
      child: Container(
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Color preview
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors.length >= 2
                        ? [colors[0], colors[1]]
                        : [colors.first, colors.first.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Stack(
                  children: [
                    // Effect icon
                    Center(
                      child: Icon(
                        _iconForEffect(effectId),
                        size: 40,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    // Color dots
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Row(
                        children: [
                          for (var i = 0; i < (colors.length > 3 ? 3 : colors.length); i++)
                            Container(
                              width: 14,
                              height: 14,
                              margin: const EdgeInsets.only(left: 2),
                              decoration: BoxDecoration(
                                color: colors[i],
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Pattern info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      pattern.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (effectName != null)
                      Text(
                        effectName,
                        style: TextStyle(
                          color: NexGenPalette.textSecondary,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForEffect(int effectId) {
    if (effectId == 0) return Icons.circle; // Solid
    if (effectId == 12) return Icons.theater_comedy; // Theater chase
    if (effectId == 41) return Icons.moving; // Running
    if (effectId == 38 || effectId == 39) return Icons.blur_on; // Fire effects
    if (effectId >= 101 && effectId <= 110) return Icons.waves; // Gradient effects
    return Icons.auto_awesome;
  }

  Future<void> _applyPattern(BuildContext context, WidgetRef ref) async {
    // Check for active neighborhood sync before changing lights
    final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No device connected')),
        );
      }
      return;
    }

    try {
      // Apply the pattern's wledPayload directly
      final success = await repo.applyJson(pattern.wledPayload);

      if (!success) {
        throw Exception('Device did not accept command');
      }

      // Update the active preset label so home screen reflects the change
      ref.read(activePresetLabelProvider.notifier).state = pattern.name;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Applied: ${pattern.name}'),
            backgroundColor: NexGenPalette.cyan.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to apply pattern: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
