import 'dart:async';
import 'dart:math';
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
import 'package:nexgen_command/features/wled/wled_repository.dart';
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
import 'package:nexgen_command/features/wled/effect_preview_widget.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/features/wled/effect_mood_system.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/lumina_custom_effects.dart';
import 'package:nexgen_command/widgets/pattern_adjustment_panel.dart';

/// Helper to execute custom Lumina effects (ID >= 1000).
/// Returns true if the effect was a custom effect and was executed.
/// Returns false if it's a native WLED effect (caller should send payload directly).
///
/// Custom Lumina effects animate by sending sequential WLED payloads from the app.
/// The animation plays once and leaves the LEDs in the final frame state.
Future<bool> _executeCustomEffectIfNeeded({
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
    // Trigger big event refresh check on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bigEventRefreshTriggerProvider.future).catchError((e) {
        debugPrint('ExplorePatternsScreen: Big event refresh check failed: $e');
      });
    });
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
    final selectedMood = ref.watch(selectedMoodFilterProvider);
    final designsAsync = ref.watch(designsStreamProvider);

    // Check if user has saved designs
    final hasSavedDesigns = designsAsync.whenOrNull(
      data: (designs) => designs.isNotEmpty,
    ) ?? false;

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
        const SizedBox(height: 12),
        // Global mood selector - pre-filter patterns when navigating
        _GlobalMoodSelector(
          selectedMood: selectedMood,
          onMoodSelected: (mood) {
            ref.read(selectedMoodFilterProvider.notifier).state = mood;
          },
        ),
        const SizedBox(height: 16),
        // Category grid
        categoriesAsync.when(
          data: (categories) {
            // Calculate total items: add 1 for saved designs card if user has saved designs
            final totalItems = hasSavedDesigns ? categories.length + 1 : categories.length;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
              ),
              itemCount: totalItems,
              itemBuilder: (context, index) {
                // If we have saved designs, show the saved designs card first
                if (hasSavedDesigns && index == 0) {
                  return const _SavedDesignsCategoryCard();
                }

                // Adjust index for regular categories if saved designs card is shown
                final categoryIndex = hasSavedDesigns ? index - 1 : index;
                final category = categories[categoryIndex];
                return _DesignLibraryCategoryCard(category: category);
              },
            );
          },
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

/// Special category card for "My Saved Designs" - appears first when user has saved designs
class _SavedDesignsCategoryCard extends StatelessWidget {
  const _SavedDesignsCategoryCard();

  static const _icons = [
    Icons.palette_outlined,
    Icons.bookmark_outlined,
    Icons.favorite_outline,
    Icons.folder_special_outlined,
    Icons.auto_awesome_outlined,
    Icons.brush_outlined,
  ];

  static const _accentColor = NexGenPalette.cyan;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push('/designs');
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            // Premium dark background with cyan accent gradient
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _accentColor.withValues(alpha: 0.15),
                NexGenPalette.matteBlack.withValues(alpha: 0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _accentColor.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _accentColor.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Accent glow in corner
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
                        _accentColor.withValues(alpha: 0.25),
                        _accentColor.withValues(alpha: 0.0),
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
                    // Icon grid
                    Expanded(
                      child: _buildIconGrid(),
                    ),
                    const SizedBox(height: 8),
                    // Category name
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'My Saved Designs',
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
                          color: _accentColor.withValues(alpha: 0.7),
                          size: 12,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Star badge to indicate this is the user's custom content
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.star,
                    color: _accentColor,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final iconSize = (constraints.maxWidth - 16) / 3.5;

        return Wrap(
          spacing: 4,
          runSpacing: 2,
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          children: _icons.asMap().entries.map((entry) {
            final index = entry.key;
            final icon = entry.value;

            final isHighlighted = index % 2 == 0;
            final iconColor = isHighlighted
                ? _accentColor
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
                          color: _accentColor.withValues(alpha: 0.5),
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
}

/// Individual category card for the Design Library browser
class _DesignLibraryCategoryCard extends ConsumerWidget {
  final PatternCategory category;

  const _DesignLibraryCategoryCard({required this.category});

  /// Returns a single hero icon that represents the category.
  /// For seasonal category, returns dynamic icon based on current season.
  IconData _heroIconForCategory(String categoryId) {
    switch (categoryId) {
      case 'cat_quick_picks':
        return Icons.auto_awesome;
      case 'cat_arch':
        return Icons.villa;
      case 'cat_holiday':
        return Icons.celebration;
      case 'cat_sports':
        return Icons.emoji_events;
      case 'cat_season':
        return _getSeasonalIcon();
      case 'cat_party':
        return Icons.cake;
      case 'cat_security':
        return Icons.shield;
      case 'cat_movies':
        return Icons.movie_filter;
      case 'cat_nature':
        return Icons.forest;
      default:
        return Icons.palette;
    }
  }

  /// Returns the appropriate seasonal icon based on current date.
  IconData _getSeasonalIcon() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    // Spring: March 20 - June 20
    if ((month == 3 && day >= 20) || month == 4 || month == 5 || (month == 6 && day < 21)) {
      return Icons.local_florist; // Flower for spring
    }
    // Summer: June 21 - September 22
    if ((month == 6 && day >= 21) || month == 7 || month == 8 || (month == 9 && day < 23)) {
      return Icons.wb_sunny; // Sun for summer
    }
    // Fall: September 23 - December 20
    if ((month == 9 && day >= 23) || month == 10 || month == 11 || (month == 12 && day < 21)) {
      return Icons.park; // Tree/leaves for fall
    }
    // Winter: December 21 - March 19
    return Icons.ac_unit; // Snowflake for winter
  }

  /// Returns gradient colors for each category background.
  List<Color> _gradientForCategory(String categoryId) {
    switch (categoryId) {
      case 'cat_quick_picks':
        // Electric cyan to purple gradient
        return const [Color(0xFF00D4FF), Color(0xFF9C27B0)];
      case 'cat_arch':
        // Warm amber to burnt orange
        return const [Color(0xFFFFB347), Color(0xFFFF7043)];
      case 'cat_holiday':
        // Festive red to deep magenta
        return const [Color(0xFFFF4444), Color(0xFFC2185B)];
      case 'cat_sports':
        // Championship gold to orange
        return const [Color(0xFFFFD700), Color(0xFFFF9800)];
      case 'cat_season':
        return _getSeasonalGradient();
      case 'cat_party':
        // Party pink to purple
        return const [Color(0xFFFF69B4), Color(0xFF9C27B0)];
      case 'cat_security':
        // Alert blue to deep blue
        return const [Color(0xFF4FC3F7), Color(0xFF1565C0)];
      case 'cat_movies':
        // Cinema purple to deep violet
        return const [Color(0xFFE040FB), Color(0xFF6A1B9A)];
      case 'cat_nature':
        // Forest green to teal
        return const [Color(0xFF4CAF50), Color(0xFF00897B)];
      default:
        return [NexGenPalette.cyan, NexGenPalette.cyan.withValues(alpha: 0.5)];
    }
  }

  /// Returns seasonal gradient based on current date.
  List<Color> _getSeasonalGradient() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    // Spring: Fresh greens and pinks
    if ((month == 3 && day >= 20) || month == 4 || month == 5 || (month == 6 && day < 21)) {
      return const [Color(0xFF81C784), Color(0xFFF8BBD9)];
    }
    // Summer: Sunny yellow to ocean blue
    if ((month == 6 && day >= 21) || month == 7 || month == 8 || (month == 9 && day < 23)) {
      return const [Color(0xFFFFEB3B), Color(0xFF29B6F6)];
    }
    // Fall: Warm orange to burgundy
    if ((month == 9 && day >= 23) || month == 10 || month == 11 || (month == 12 && day < 21)) {
      return const [Color(0xFFFF9800), Color(0xFF8D6E63)];
    }
    // Winter: Icy blue to deep purple
    return const [Color(0xFF81D4FA), Color(0xFF7E57C2)];
  }

  /// Returns accent color for each category (used for icon highlights and glow).
  Color _accentForCategory(String categoryId) {
    switch (categoryId) {
      case 'cat_quick_picks':
        return const Color(0xFF00D4FF); // Electric cyan
      case 'cat_arch':
        return const Color(0xFFFFB347); // Warm amber
      case 'cat_holiday':
        return const Color(0xFFFF4444); // Festive red
      case 'cat_sports':
        return const Color(0xFFFFD700); // Championship gold
      case 'cat_season':
        return _getSeasonalAccentColor();
      case 'cat_party':
        return const Color(0xFFFF69B4); // Party pink
      case 'cat_security':
        return const Color(0xFF4FC3F7); // Alert blue
      case 'cat_movies':
        return const Color(0xFFE040FB); // Cinema purple
      case 'cat_nature':
        return const Color(0xFF4CAF50); // Forest green
      default:
        return NexGenPalette.cyan;
    }
  }

  /// Returns seasonal accent color based on current date.
  Color _getSeasonalAccentColor() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    // Spring: Fresh pink
    if ((month == 3 && day >= 20) || month == 4 || month == 5 || (month == 6 && day < 21)) {
      return const Color(0xFFF8BBD9);
    }
    // Summer: Sunny yellow
    if ((month == 6 && day >= 21) || month == 7 || month == 8 || (month == 9 && day < 23)) {
      return const Color(0xFFFFEB3B);
    }
    // Fall: Warm orange
    if ((month == 9 && day >= 23) || month == 10 || month == 11 || (month == 12 && day < 21)) {
      return const Color(0xFFFF9800);
    }
    // Winter: Icy blue
    return const Color(0xFF81D4FA);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroIcon = _heroIconForCategory(category.id);
    final accentColor = _accentForCategory(category.id);
    final gradientColors = _gradientForCategory(category.id);
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
            // Category-specific gradient background
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                gradientColors[0].withValues(alpha: 0.25),
                gradientColors[1].withValues(alpha: 0.15),
                NexGenPalette.matteBlack.withValues(alpha: 0.95),
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Large radial glow behind icon
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          gradientColors[0].withValues(alpha: 0.3),
                          gradientColors[1].withValues(alpha: 0.1),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Single hero icon - centered and prominent
                    Expanded(
                      child: Center(
                        child: Icon(
                          heroIcon,
                          size: 52,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: accentColor.withValues(alpha: 0.8),
                              blurRadius: 24,
                            ),
                            Shadow(
                              color: gradientColors[0].withValues(alpha: 0.5),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Category name with arrow
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            category.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: accentColor.withValues(alpha: 0.8),
                          size: 10,
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

      // Check if this is a custom Lumina effect (ID >= 1000)
      final isCustomEffect = await _executeCustomEffectIfNeeded(
        effectId: pattern.effectId,
        colors: colors.isNotEmpty ? colors.take(3).toList() : [[255, 180, 100, 0]],
        repo: repo,
      );

      if (!isCustomEffect) {
        // Standard WLED effect - send payload directly
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
      }

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

  /// Returns a hero icon for each sub-category type.
  IconData _heroIconForSubCategory(String subId) {
    switch (subId) {
      // Holidays
      case 'sub_xmas':
        return Icons.park; // Christmas tree
      case 'sub_halloween':
        return Icons.pest_control; // Spider/bug for spooky
      case 'sub_july4':
        return Icons.celebration; // Fireworks/celebration
      case 'sub_easter':
        return Icons.egg; // Easter egg
      case 'sub_valentines':
        return Icons.favorite; // Heart
      case 'sub_st_patricks':
        return Icons.local_florist; // Clover/flower
      // Sports
      case 'sub_kc':
        return Icons.sports_football; // Football
      case 'sub_seattle':
        return Icons.sports_football;
      case 'sub_rb_generic':
      case 'sub_gy_generic':
      case 'sub_ob_generic':
        return Icons.emoji_events; // Trophy
      // Seasonal
      case 'sub_spring':
        return Icons.local_florist; // Flowers
      case 'sub_summer':
        return Icons.wb_sunny; // Sun
      case 'sub_autumn':
        return Icons.park; // Falling leaves
      case 'sub_winter':
        return Icons.ac_unit; // Snowflake
      // Architectural
      case 'sub_warm_whites':
        return Icons.wb_incandescent; // Warm bulb
      case 'sub_cool_whites':
        return Icons.light_mode; // Cool light
      case 'sub_gold_accents':
        return Icons.auto_awesome; // Sparkle/gold
      case 'sub_security_floods':
        return Icons.flashlight_on; // Flood light
      // Party
      case 'sub_birthday':
        return Icons.cake; // Birthday cake
      case 'sub_elegant_dinner':
        return Icons.restaurant; // Dinner
      case 'sub_rave':
        return Icons.speaker; // Music/rave
      case 'sub_baby_shower':
        return Icons.child_friendly; // Baby
      default:
        return Icons.palette; // Default
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = subCategory.themeColors;
    final gradientColors = colors.isEmpty
        ? [NexGenPalette.violet, NexGenPalette.cyan]
        : (colors.length == 1 ? [colors[0], colors[0]] : colors);
    final accentColor = gradientColors.first;
    final heroIcon = _heroIconForSubCategory(subCategory.id);

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
        width: 110,
        decoration: BoxDecoration(
          // Premium gradient background matching main category cards
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              gradientColors[0].withValues(alpha: 0.3),
              gradientColors.length > 1 ? gradientColors[1].withValues(alpha: 0.2) : gradientColors[0].withValues(alpha: 0.2),
              NexGenPalette.matteBlack.withValues(alpha: 0.95),
            ],
            stops: const [0.0, 0.4, 1.0],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Radial glow behind icon
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        gradientColors[0].withValues(alpha: 0.35),
                        gradientColors.length > 1 ? gradientColors[1].withValues(alpha: 0.15) : Colors.transparent,
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Hero icon
                  Icon(
                    heroIcon,
                    size: 28,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: accentColor.withValues(alpha: 0.8),
                        blurRadius: 16,
                      ),
                      Shadow(
                        color: gradientColors[0].withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Name with arrow
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          subCategory.name,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: accentColor.withValues(alpha: 0.8),
                        size: 8,
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
              'grp': _current.grouping,
              'spc': _current.spacing,
            }
          ]
        });
      } catch (e) {
        debugPrint('Apply grp/spc failed: $e');
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
                  childAspectRatio: 1.6,
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

  /// Returns a hero icon for each sub-category type.
  IconData _heroIconForSubCategory(String subId) {
    switch (subId) {
      // Holidays
      case 'sub_xmas':
        return Icons.park;
      case 'sub_halloween':
        return Icons.pest_control;
      case 'sub_july4':
        return Icons.celebration;
      case 'sub_easter':
        return Icons.egg;
      case 'sub_valentines':
        return Icons.favorite;
      case 'sub_st_patricks':
        return Icons.local_florist;
      // Sports
      case 'sub_kc':
        return Icons.sports_football;
      case 'sub_seattle':
        return Icons.sports_football;
      case 'sub_rb_generic':
      case 'sub_gy_generic':
      case 'sub_ob_generic':
        return Icons.emoji_events;
      // Seasonal
      case 'sub_spring':
        return Icons.local_florist;
      case 'sub_summer':
        return Icons.wb_sunny;
      case 'sub_autumn':
        return Icons.park;
      case 'sub_winter':
        return Icons.ac_unit;
      // Architectural
      case 'sub_warm_whites':
        return Icons.wb_incandescent;
      case 'sub_cool_whites':
        return Icons.light_mode;
      case 'sub_gold_accents':
        return Icons.auto_awesome;
      case 'sub_security_floods':
        return Icons.flashlight_on;
      // Party
      case 'sub_birthday':
        return Icons.cake;
      case 'sub_elegant_dinner':
        return Icons.restaurant;
      case 'sub_rave':
        return Icons.speaker;
      case 'sub_baby_shower':
        return Icons.child_friendly;
      default:
        return Icons.palette;
    }
  }

  /// Handpicked gradient pairs for each subcategory — curated for card aesthetics.
  List<Color> _gradientForSubCategory(String subId) {
    switch (subId) {
      // Holidays
      case 'sub_xmas':
        return const [Color(0xFF2E7D32), Color(0xFFC62828)]; // Deep green → deep red
      case 'sub_halloween':
        return const [Color(0xFFFF6D00), Color(0xFF6A1B9A)]; // Vivid orange → purple
      case 'sub_july4':
        return const [Color(0xFFEF5350), Color(0xFF1565C0)]; // Red → blue
      case 'sub_easter':
        return const [Color(0xFFF8BBD0), Color(0xFFB39DDB)]; // Soft pink → lavender
      case 'sub_valentines':
        return const [Color(0xFFE91E63), Color(0xFFAD1457)]; // Hot pink → deep rose
      case 'sub_st_patricks':
        return const [Color(0xFF43A047), Color(0xFF00C853)]; // Forest green → bright green
      // Sports
      case 'sub_kc':
        return const [Color(0xFFD32F2F), Color(0xFFFFB300)]; // Red → gold
      case 'sub_seattle':
        return const [Color(0xFF1B5E20), Color(0xFF1565C0)]; // Green → blue
      case 'sub_rb_generic':
        return const [Color(0xFFD32F2F), Color(0xFF1565C0)]; // Red → blue
      case 'sub_gy_generic':
        return const [Color(0xFF2E7D32), Color(0xFFF9A825)]; // Green → yellow
      case 'sub_ob_generic':
        return const [Color(0xFFEF6C00), Color(0xFF1565C0)]; // Orange → blue
      // Seasonal
      case 'sub_spring':
        return const [Color(0xFF81C784), Color(0xFFF48FB1)]; // Fresh green → pink
      case 'sub_summer':
        return const [Color(0xFFFFEE58), Color(0xFF29B6F6)]; // Sunny yellow → sky blue
      case 'sub_autumn':
        return const [Color(0xFFFF8F00), Color(0xFF6D4C41)]; // Amber → brown
      case 'sub_winter':
        return const [Color(0xFF81D4FA), Color(0xFF7E57C2)]; // Icy blue → purple
      // Architectural
      case 'sub_warm_whites':
        return const [Color(0xFFFFB74D), Color(0xFFFF8A65)]; // Warm amber → peach
      case 'sub_cool_whites':
        return const [Color(0xFF90A4AE), Color(0xFFE0E0E0)]; // Steel → silver
      case 'sub_gold_accents':
        return const [Color(0xFFFFD54F), Color(0xFFFFA000)]; // Light gold → deep gold
      case 'sub_security_floods':
        return const [Color(0xFFE0E0E0), Color(0xFF4FC3F7)]; // White → alert blue
      // Party
      case 'sub_birthday':
        return const [Color(0xFF00E5FF), Color(0xFFFF4081)]; // Cyan → pink
      case 'sub_elegant_dinner':
        return const [Color(0xFFFFB74D), Color(0xFF5D4037)]; // Amber → espresso
      case 'sub_rave':
        return const [Color(0xFFAA00FF), Color(0xFF00E5FF)]; // Electric purple → cyan
      case 'sub_baby_shower':
        return const [Color(0xFF80DEEA), Color(0xFFF8BBD0)]; // Baby blue → baby pink
      default:
        return [NexGenPalette.cyan, NexGenPalette.cyan.withValues(alpha: 0.5)];
    }
  }

  /// Handpicked accent color for each subcategory.
  Color _accentForSubCategory(String subId) {
    switch (subId) {
      // Holidays
      case 'sub_xmas':
        return const Color(0xFF4CAF50); // Christmas green
      case 'sub_halloween':
        return const Color(0xFFFF6D00); // Pumpkin orange
      case 'sub_july4':
        return const Color(0xFFEF5350); // Patriot red
      case 'sub_easter':
        return const Color(0xFFF8BBD0); // Pastel pink
      case 'sub_valentines':
        return const Color(0xFFE91E63); // Hot pink
      case 'sub_st_patricks':
        return const Color(0xFF00C853); // Bright green
      // Sports
      case 'sub_kc':
        return const Color(0xFFD32F2F); // KC red
      case 'sub_seattle':
        return const Color(0xFF43A047); // Seattle green
      case 'sub_rb_generic':
        return const Color(0xFFEF5350); // Red
      case 'sub_gy_generic':
        return const Color(0xFF66BB6A); // Green
      case 'sub_ob_generic':
        return const Color(0xFFEF6C00); // Orange
      // Seasonal
      case 'sub_spring':
        return const Color(0xFFF48FB1); // Spring pink
      case 'sub_summer':
        return const Color(0xFFFFEE58); // Sunny yellow
      case 'sub_autumn':
        return const Color(0xFFFF8F00); // Autumn amber
      case 'sub_winter':
        return const Color(0xFF81D4FA); // Icy blue
      // Architectural
      case 'sub_warm_whites':
        return const Color(0xFFFFB74D); // Warm amber
      case 'sub_cool_whites':
        return const Color(0xFF90A4AE); // Cool steel
      case 'sub_gold_accents':
        return const Color(0xFFFFD54F); // Gold
      case 'sub_security_floods':
        return const Color(0xFF4FC3F7); // Alert blue
      // Party
      case 'sub_birthday':
        return const Color(0xFF00E5FF); // Electric cyan
      case 'sub_elegant_dinner':
        return const Color(0xFFFFB74D); // Warm amber
      case 'sub_rave':
        return const Color(0xFFAA00FF); // Electric purple
      case 'sub_baby_shower':
        return const Color(0xFF80DEEA); // Baby blue
      default:
        return NexGenPalette.cyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final heroIcon = _heroIconForSubCategory(sub.id);
    final accentColor = _accentForSubCategory(sub.id);
    final gradientColors = _gradientForSubCategory(sub.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/explore/$categoryId/sub/${sub.id}', extra: {'name': sub.name}),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                gradientColors[0].withValues(alpha: 0.25),
                gradientColors[1].withValues(alpha: 0.15),
                NexGenPalette.matteBlack.withValues(alpha: 0.95),
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Large radial glow behind icon
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          gradientColors[0].withValues(alpha: 0.3),
                          gradientColors[1].withValues(alpha: 0.1),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Single hero icon - centered and prominent
                    Expanded(
                      child: Center(
                        child: Icon(
                          heroIcon,
                          size: 52,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: accentColor.withValues(alpha: 0.8),
                              blurRadius: 24,
                            ),
                            Shadow(
                              color: gradientColors[0].withValues(alpha: 0.5),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Subcategory name with arrow
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            sub.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: accentColor.withValues(alpha: 0.8),
                          size: 10,
                        ),
                      ],
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

/// Compact pattern item card for 4-column grid layout.
/// Shows a smaller preview with effect name and color slot indicator.
class _CompactPatternItemCard extends ConsumerWidget {
  final PatternItem item;
  final List<Color> themeColors;
  const _CompactPatternItemCard({required this.item, required this.themeColors});

  /// Get how many color slots this effect actually uses.
  /// Returns 0 if the effect generates its own colors / uses palette.
  ///
  /// Effect IDs aligned with WledEffectsCatalog (WLED 0.14+ firmware).
  /// Effects that use selected colors all receive 3 slots so all palette
  /// colors are sent — WLED ignores extras harmlessly.
  static int _getColorSlotsForEffect(int effectId) {
    // Effects that ignore user colors entirely (generate own or use palette).
    // Sourced from WledEffectsCatalog: generatesOwnColors + usesPalette.
    const autoColorEffects = {
      // generatesOwnColors
      4,   // Wipe Random
      5,   // Random Colors
      7,   // Dynamic
      8,   // Colorloop
      9,   // Rainbow
      14,  // Theater Rainbow
      19,  // Dissolve Rnd
      24,  // Strobe Rainbow
      26,  // Blink Rainbow
      29,  // Chase Random
      30,  // Chase Rainbow
      32,  // Chase Flash Rnd
      33,  // Rainbow Runner
      34,  // Colorful
      35,  // Traffic Light
      36,  // Sweep Random
      38,  // Aurora
      45,  // Fire Flicker
      63,  // Pride 2015
      66,  // Fire 2012
      88,  // Candle
      94,  // Sinelon Rainbow
      99,  // Ripple Rainbow
      101, // Pacifica
      104, // Sunrise
      116, // TV Simulator
      117, // Dynamic Smooth
      // usesPalette
      39,  // Stream
      42,  // Fireworks
      43,  // Rain
      61,  // Stream 2
      64,  // Juggle
      65,  // Palette
      67,  // Colorwaves
      68,  // Bpm
      69,  // Fill Noise
      70,  // Noise 1
      71,  // Noise 2
      72,  // Noise 3
      73,  // Noise 4
      74,  // Colortwinkles
      75,  // Lake
      79,  // Ripple
      80,  // Twinklefox
      81,  // Twinklecat
      89,  // Fireworks Starburst
      90,  // Fireworks 1D
      92,  // Sinelon
      93,  // Sinelon Dual
      97,  // Plasma
      105, // Phased
      106, // Twinkleup
      107, // Noise Pal
      108, // Sine
      109, // Phased Noise
      110, // Flow
      115, // Blends
      128, // Pixels
    };

    if (autoColorEffects.contains(effectId)) return 0;

    // All remaining effects that use/blend selected colors get 3 slots.
    // WLED's col array supports up to 3 colors per segment and safely
    // ignores slots an effect doesn't use, so sending all 3 is harmless
    // and ensures multi-color palettes display correctly.
    return 3;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectId = MockPatternRepository.effectIdFromPayload(item.wledPayload) ?? 0;
    final colorSlots = _getColorSlotsForEffect(effectId);
    final extractedColors = _extractColorsFromItem(item);

    // Always show all palette colors in preview so users see the full colorway.
    // Previously this limited to colorSlots which hid the 3rd color on 2-color effects.
    final displayColors = extractedColors;

    // Get effect name for display
    final effectName = _getEffectDisplayName(effectId);

    return InkWell(
      onTap: () => _handleTap(context, ref, effectId, extractedColors),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: NexGenPalette.matteBlack,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NexGenPalette.line.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Realistic effect preview strip (takes 60% of height)
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                child: _EffectPreviewStrip(
                  colors: displayColors.isNotEmpty ? displayColors : [Colors.white],
                  effectId: effectId,
                  speed: _getSpeedFromPayload(item.wledPayload),
                ),
              ),
            ),
            // Text section (takes 40% of height)
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      displayColors.isNotEmpty
                          ? displayColors.first.withValues(alpha: 0.15)
                          : NexGenPalette.cyan.withValues(alpha: 0.1),
                      NexGenPalette.matteBlack,
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Pattern name
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    // Effect type badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: displayColors.isNotEmpty
                            ? displayColors.first.withValues(alpha: 0.3)
                            : NexGenPalette.cyan.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        effectName,
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  /// Get a user-friendly effect name from the effect ID
  static String _getEffectDisplayName(int effectId) {
    const effectNames = {
      0: 'Solid',
      1: 'Blink',
      2: 'Breathe',
      3: 'Wipe',
      6: 'Sweep',
      10: 'Scan',
      12: 'Fade',
      22: 'Running',
      23: 'Chase',
      37: 'Fill Noise',
      43: 'Theater',
      46: 'Twinkle',
      49: 'Fire',
      51: 'Gradient',
      52: 'Loading',
      63: 'Palette',
      65: 'Colorwave',
      67: 'Ripple',
      73: 'Pacifica',
      76: 'Fireworks',
      78: 'Meteor',
      108: 'Meteor',
      120: 'Sparkle',
    };
    return effectNames[effectId] ?? 'Effect';
  }

  /// Extract speed from WLED payload
  static double _getSpeedFromPayload(Map<String, dynamic> payload) {
    try {
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final first = seg.first;
        if (first is Map) {
          final sx = first['sx'];
          if (sx is num) return sx.toDouble();
        }
      }
    } catch (_) {}
    return 128; // Default speed
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref, int effectId, List<Color> extractedColors) async {
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

    // For Solid effect (ID 0), show color picker if multiple colors available
    if (effectId == 0 && themeColors.length > 1) {
      if (context.mounted) {
        final selectedColor = await _showSolidColorPicker(context, themeColors);
        if (selectedColor != null && context.mounted) {
          await _applyPatternWithColor(context, ref, repo, selectedColor);
        }
      }
      return;
    }

    // Send all palette colors to WLED. Previously this showed a color
    // assignment dialog that forced users to drop colors when the effect
    // used fewer slots than available, causing 3-color palettes to lose
    // their 3rd color on 2-color effects. WLED safely ignores extra
    // colors in the col array, so sending all is harmless and ensures
    // the full colorway is applied.
    try {
      await repo.applyJson(item.wledPayload);
      ref.read(activePresetLabelProvider.notifier).state = item.name;
      _updateLocalState(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${item.name}')));
      }
    } catch (e) {
      debugPrint('Apply pattern failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
      }
    }
  }

  void _updateLocalState(WidgetRef ref) {
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
  }

  Future<Color?> _showSolidColorPicker(BuildContext context, List<Color> colors) async {
    return showModalBottomSheet<Color>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SolidColorPickerSheet(colors: colors),
    );
  }

  Future<List<Color>?> _showColorAssignmentDialog(
    BuildContext context,
    List<Color> availableColors,
    int slots,
    int effectId,
  ) async {
    return showModalBottomSheet<List<Color>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ColorAssignmentSheet(
        availableColors: availableColors,
        slots: slots,
        effectId: effectId,
      ),
    );
  }

  Future<void> _applyPatternWithColor(BuildContext context, WidgetRef ref, WledRepository repo, Color color) async {
    try {
      // Create payload with selected color
      final payload = Map<String, dynamic>.from(item.wledPayload);
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final s0 = Map<String, dynamic>.from(seg.first as Map);
        s0['col'] = [[color.red, color.green, color.blue, 0]];
        payload['seg'] = [s0];
      }
      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = item.name;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${item.name}')));
      }
    } catch (e) {
      debugPrint('Apply pattern failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
      }
    }
  }

  Future<void> _applyPatternWithColors(BuildContext context, WidgetRef ref, WledRepository repo, List<Color> colors, int effectId) async {
    try {
      final payload = Map<String, dynamic>.from(item.wledPayload);
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final s0 = Map<String, dynamic>.from(seg.first as Map);
        s0['col'] = colors.map((c) => [c.red, c.green, c.blue, 0]).toList();
        payload['seg'] = [s0];
      }
      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = item.name;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${item.name}')));
      }
    } catch (e) {
      debugPrint('Apply pattern failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
      }
    }
  }
}

/// Bottom sheet for picking a solid color when using Solid effect.
class _SolidColorPickerSheet extends StatelessWidget {
  final List<Color> colors;
  const _SolidColorPickerSheet({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette, color: NexGenPalette.cyan, size: 20),
              const SizedBox(width: 8),
              Text(
                'Choose Solid Color',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: NexGenPalette.textHigh,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Solid effect displays a single color. Select which color to use:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: NexGenPalette.textMedium,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((color) => _ColorPickerTile(
              color: color,
              onTap: () => Navigator.pop(context, color),
            )).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for assigning colors to effect slots.
class _ColorAssignmentSheet extends StatefulWidget {
  final List<Color> availableColors;
  final int slots;
  final int effectId;
  const _ColorAssignmentSheet({
    required this.availableColors,
    required this.slots,
    required this.effectId,
  });

  @override
  State<_ColorAssignmentSheet> createState() => _ColorAssignmentSheetState();
}

class _ColorAssignmentSheetState extends State<_ColorAssignmentSheet> {
  late List<Color> _assignedColors;

  @override
  void initState() {
    super.initState();
    // Pre-fill with first N colors
    _assignedColors = widget.availableColors.take(widget.slots).toList();
    // Pad if needed
    while (_assignedColors.length < widget.slots) {
      _assignedColors.add(widget.availableColors.first);
    }
  }

  String _getSlotLabel(int index) {
    switch (index) {
      case 0: return 'Primary';
      case 1: return 'Secondary';
      case 2: return 'Accent';
      default: return 'Color ${index + 1}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectName = kEffectNames[widget.effectId] ?? 'Effect ${widget.effectId}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: NexGenPalette.cyan, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Assign Colors for $effectName',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This effect uses ${widget.slots} color${widget.slots > 1 ? 's' : ''}. Assign colors to each slot:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: NexGenPalette.textMedium,
            ),
          ),
          const SizedBox(height: 16),
          // Slot assignment rows
          ...List.generate(widget.slots, (slotIndex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      _getSlotLabel(slotIndex),
                      style: const TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: widget.availableColors.map((color) {
                          final isSelected = _assignedColors[slotIndex] == color;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _assignedColors[slotIndex] = color;
                              });
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
                                  width: isSelected ? 3 : 1,
                                ),
                                boxShadow: isSelected ? [
                                  BoxShadow(
                                    color: NexGenPalette.cyan.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ] : null,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          // Preview strip
          Container(
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(colors: _assignedColors),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _assignedColors),
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                  ),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Color picker tile for the solid color picker.
class _ColorPickerTile extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _ColorPickerTile({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.touch_app, color: Colors.white54, size: 20),
        ),
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

/// Realistic effect preview that animates based on the WLED effect type.
/// Shows users what the effect will look like on their lighting system.
class _EffectPreviewStrip extends StatefulWidget {
  final List<Color> colors;
  final int effectId;
  final double speed;

  const _EffectPreviewStrip({
    required this.colors,
    required this.effectId,
    this.speed = 128,
  });

  @override
  State<_EffectPreviewStrip> createState() => _EffectPreviewStripState();
}

class _EffectPreviewStripState extends State<_EffectPreviewStrip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _twinkleOpacities = [];
  final List<int> _twinkleColorIndices = [];

  @override
  void initState() {
    super.initState();
    // Map speed (0-255) to animation duration
    final durationMs = (3000 - (widget.speed / 255) * 2500).clamp(500, 5000).round();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    // Initialize twinkle state for popcorn/sparkle effects
    for (int i = 0; i < 20; i++) {
      _twinkleOpacities.add(0.0);
      _twinkleColorIndices.add(i % widget.colors.length);
    }

    if (widget.effectId != 0) {
      _controller.repeat();
    }
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
        return CustomPaint(
          painter: _EffectPainter(
            colors: widget.colors,
            effectId: widget.effectId,
            progress: _controller.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

/// Custom painter that draws realistic effect previews
class _EffectPainter extends CustomPainter {
  final List<Color> colors;
  final int effectId;
  final double progress;

  _EffectPainter({
    required this.colors,
    required this.effectId,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final ledCount = 30; // Simulated LED count for preview
    final ledWidth = size.width / ledCount;
    final ledHeight = size.height;

    switch (_getEffectType(effectId)) {
      case _EffectType.solid:
        _paintSolid(canvas, size, paint);
        break;
      case _EffectType.breathing:
        _paintBreathing(canvas, size, paint);
        break;
      case _EffectType.chase:
        _paintChase(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.wipe:
        _paintWipe(canvas, size, paint);
        break;
      case _EffectType.sparkle:
        _paintSparkle(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.scan:
        _paintScan(canvas, size, paint, ledWidth, ledHeight);
        break;
      case _EffectType.fade:
        _paintFade(canvas, size, paint);
        break;
      case _EffectType.gradient:
        _paintGradient(canvas, size, paint);
        break;
      case _EffectType.theater:
        _paintTheater(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.running:
        _paintRunning(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.twinkle:
        _paintTwinkle(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.fire:
        _paintFire(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.meteor:
        _paintMeteor(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.wave:
        _paintWave(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
    }
  }

  _EffectType _getEffectType(int effectId) {
    // Map WLED effect IDs to visual effect types
    switch (effectId) {
      case 0: return _EffectType.solid;
      case 1: // Blink
      case 2: // Breathe
        return _EffectType.breathing;
      case 3: // Wipe
      case 4: // Wipe Random
        return _EffectType.wipe;
      case 6: // Sweep
      case 10: // Scan
      case 11: // Dual Scan
      case 13: // Scanner
      case 14: // Dual Scanner
        return _EffectType.scan;
      case 12: // Fade
      case 18: // Dissolve
        return _EffectType.fade;
      case 22: // Running 2
      case 23: // Chase
      case 24: // Chase Rainbow
      case 25: // Running Dual
      case 41: // Running
      case 42: // Running 2
        return _EffectType.running;
      case 43: // Theater Chase
      case 44: // Theater Chase Rainbow
        return _EffectType.theater;
      case 37: // Fill Noise
      case 46: // Twinklefox
      case 47: // Twinklecat
        return _EffectType.twinkle;
      case 51: // Gradient
      case 63: // Palette
      case 65: // Colorwaves
        return _EffectType.gradient;
      case 49: // Fire 2012
      case 54: // Fire Flicker
      case 74: // Candle
      case 75: // Fire
        return _EffectType.fire;
      case 78: // Meteor Rainbow
      case 108: // Meteor
      case 109: // Meteor Smooth
        return _EffectType.meteor;
      case 52: // Loading
      case 67: // Ripple
      case 70: // Lake
      case 73: // Pacifica
        return _EffectType.wave;
      case 76: // Fireworks
      case 77: // Rain
      case 120: // Sparkle
      case 121: // Sparkle+
        return _EffectType.sparkle;
      default:
        return _EffectType.chase; // Default to chase for unknown effects
    }
  }

  void _paintSolid(Canvas canvas, Size size, Paint paint) {
    paint.color = colors.first;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintBreathing(Canvas canvas, Size size, Paint paint) {
    // Smooth sine wave breathing
    final breathValue = (sin(progress * 2 * pi) + 1) / 2;
    paint.color = colors.first.withValues(alpha: 0.3 + breathValue * 0.7);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintChase(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    final chaseLength = 5;
    final chasePos = (progress * ledCount).floor();

    for (int i = 0; i < ledCount; i++) {
      final distFromChase = (i - chasePos + ledCount) % ledCount;
      if (distFromChase < chaseLength) {
        final colorIdx = distFromChase % colors.length;
        final brightness = 1.0 - (distFromChase / chaseLength);
        paint.color = colors[colorIdx].withValues(alpha: brightness);
      } else {
        paint.color = colors.last.withValues(alpha: 0.1);
      }
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintWipe(Canvas canvas, Size size, Paint paint) {
    final wipePos = progress * size.width;
    // First color (wiped area)
    paint.color = colors.first;
    canvas.drawRect(Rect.fromLTWH(0, 0, wipePos, size.height), paint);
    // Second color (unwipped area)
    paint.color = colors.length > 1 ? colors[1] : colors.first.withValues(alpha: 0.3);
    canvas.drawRect(Rect.fromLTWH(wipePos, 0, size.width - wipePos, size.height), paint);
  }

  void _paintSparkle(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Background
    paint.color = colors.last.withValues(alpha: 0.15);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Sparkles - use progress to create pseudo-random positions
    final sparkleCount = 8;
    for (int i = 0; i < sparkleCount; i++) {
      final seed = (progress * 1000 + i * 137).floor() % ledCount;
      final colorIdx = i % colors.length;
      final fadePhase = ((progress * 3 + i * 0.3) % 1.0);
      final opacity = fadePhase < 0.5 ? fadePhase * 2 : (1 - fadePhase) * 2;

      paint.color = colors[colorIdx].withValues(alpha: opacity.clamp(0.0, 1.0));
      final x = seed * ledWidth;
      // Draw as small circle for sparkle effect
      canvas.drawCircle(Offset(x + ledWidth / 2, size.height / 2), ledWidth * 0.8, paint);
    }
  }

  void _paintScan(Canvas canvas, Size size, Paint paint, double ledWidth, double ledHeight) {
    // Background
    paint.color = colors.last.withValues(alpha: 0.1);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Scanning bar that bounces
    final bounce = (sin(progress * 2 * pi) + 1) / 2;
    final scanPos = bounce * (size.width - ledWidth * 3);
    final scanWidth = ledWidth * 3;

    // Glow behind scan bar
    final glowGradient = LinearGradient(
      colors: [
        colors.first.withValues(alpha: 0.0),
        colors.first.withValues(alpha: 0.5),
        colors.first,
        colors.first.withValues(alpha: 0.5),
        colors.first.withValues(alpha: 0.0),
      ],
    );
    paint.shader = glowGradient.createShader(Rect.fromLTWH(scanPos - scanWidth, 0, scanWidth * 3, ledHeight));
    canvas.drawRect(Rect.fromLTWH(scanPos - scanWidth, 0, scanWidth * 3, ledHeight), paint);
    paint.shader = null;
  }

  void _paintFade(Canvas canvas, Size size, Paint paint) {
    // Smooth color fade between colors
    final colorCount = colors.length;
    final colorProgress = progress * colorCount;
    final currentIdx = colorProgress.floor() % colorCount;
    final nextIdx = (currentIdx + 1) % colorCount;
    final blendFactor = colorProgress - colorProgress.floor();

    final blendedColor = Color.lerp(colors[currentIdx], colors[nextIdx], blendFactor)!;
    paint.color = blendedColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintGradient(Canvas canvas, Size size, Paint paint) {
    // Flowing gradient
    final offset = progress * 2;
    final extendedColors = [...colors, ...colors];
    final stops = List.generate(extendedColors.length, (i) => (i / (extendedColors.length - 1) + offset) % 2 / 2);
    stops.sort();

    final gradient = LinearGradient(
      colors: extendedColors,
      stops: stops,
    );
    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    paint.shader = null;
  }

  void _paintTheater(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Theater chase - every 3rd LED lit, shifting
    final offset = (progress * 3).floor() % 3;

    for (int i = 0; i < ledCount; i++) {
      final isLit = (i + offset) % 3 == 0;
      final colorIdx = ((i + offset) ~/ 3) % colors.length;
      paint.color = isLit ? colors[colorIdx] : Colors.black.withValues(alpha: 0.3);
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintRunning(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Running lights - segments of color moving
    final segmentLength = ledCount ~/ colors.length;
    final offset = (progress * ledCount).floor();

    for (int i = 0; i < ledCount; i++) {
      final adjustedI = (i + offset) % ledCount;
      final colorIdx = (adjustedI ~/ segmentLength) % colors.length;
      paint.color = colors[colorIdx];
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintTwinkle(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Base gradient
    final gradient = LinearGradient(colors: colors);
    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    paint.shader = null;

    // Twinkle overlay - bright spots that fade in/out
    final twinkleCount = 6;
    for (int i = 0; i < twinkleCount; i++) {
      final seed = (i * 17 + 7) % ledCount;
      final phase = ((progress * 2 + i * 0.2) % 1.0);
      final brightness = (sin(phase * 2 * pi) + 1) / 2;

      paint.color = Colors.white.withValues(alpha: brightness * 0.7);
      final x = seed * ledWidth + ledWidth / 2;
      canvas.drawCircle(Offset(x, size.height / 2), ledWidth * 0.6, paint);
    }
  }

  void _paintFire(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Fire effect with orange/red/yellow flickering
    final fireColors = colors.isNotEmpty ? colors : [Colors.red, Colors.orange, Colors.yellow];

    for (int i = 0; i < ledCount; i++) {
      // Create pseudo-random flicker based on position and time
      final flicker = (sin(progress * 10 + i * 0.5) + sin(progress * 7 + i * 0.3)) / 4 + 0.5;
      final colorIdx = ((flicker * fireColors.length).floor()).clamp(0, fireColors.length - 1);
      final brightness = 0.5 + flicker * 0.5;

      paint.color = fireColors[colorIdx].withValues(alpha: brightness.clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintMeteor(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Background
    paint.color = Colors.black.withValues(alpha: 0.8);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Meteor with tail
    final meteorPos = (progress * (ledCount + 10)).floor() - 5;
    final tailLength = 8;

    for (int i = 0; i < tailLength; i++) {
      final pos = meteorPos - i;
      if (pos >= 0 && pos < ledCount) {
        final brightness = 1.0 - (i / tailLength);
        final colorIdx = i % colors.length;
        paint.color = colors[colorIdx].withValues(alpha: brightness);
        canvas.drawRect(Rect.fromLTWH(pos * ledWidth, 0, ledWidth + 1, ledHeight), paint);
      }
    }
  }

  void _paintWave(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Smooth wave pattern
    for (int i = 0; i < ledCount; i++) {
      final waveOffset = sin(progress * 2 * pi + i * 0.3);
      final brightness = (waveOffset + 1) / 2;
      final colorIdx = (i * colors.length / ledCount).floor() % colors.length;
      paint.color = colors[colorIdx].withValues(alpha: 0.3 + brightness * 0.7);
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EffectPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.effectId != effectId ||
        oldDelegate.colors != colors;
  }
}

enum _EffectType {
  solid,
  breathing,
  chase,
  wipe,
  sparkle,
  scan,
  fade,
  gradient,
  theater,
  running,
  twinkle,
  fire,
  meteor,
  wave,
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
                            crossAxisCount: 3, // 3 columns for better readability
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.1, // Wider cards, shorter height
                          ),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _CompactPatternItemCard(item: list[i], themeColors: colors),
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
class LibraryBrowserScreen extends ConsumerStatefulWidget {
  final String? nodeId;
  final String? nodeName;

  const LibraryBrowserScreen({super.key, this.nodeId, this.nodeName});

  @override
  ConsumerState<LibraryBrowserScreen> createState() => _LibraryBrowserScreenState();
}

class _LibraryBrowserScreenState extends ConsumerState<LibraryBrowserScreen> {
  bool _isPaletteView = false;

  @override
  void dispose() {
    // Reset mood filter when leaving a palette view
    if (_isPaletteView) {
      // Use Future.microtask to avoid modifying providers during dispose
      Future.microtask(() {
        ref.read(selectedMoodFilterProvider.notifier).state = null;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get current node (if any) and children
    final nodeAsync = widget.nodeId != null
        ? ref.watch(libraryNodeByIdProvider(widget.nodeId!))
        : const AsyncValue<LibraryNode?>.data(null);
    final childrenAsync = ref.watch(libraryChildNodesProvider(widget.nodeId));
    final ancestorsAsync = widget.nodeId != null
        ? ref.watch(libraryAncestorsProvider(widget.nodeId!))
        : const AsyncValue<List<LibraryNode>>.data([]);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        // Reset mood filter when navigating back from a palette view
        if (_isPaletteView && didPop) {
          ref.read(selectedMoodFilterProvider.notifier).state = null;
        }
      },
      child: Scaffold(
        backgroundColor: NexGenPalette.gunmetal,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App bar with back button and title
              _LibraryAppBar(
                nodeId: widget.nodeId,
                nodeName: widget.nodeName,
                nodeAsync: nodeAsync,
              ),
              // Breadcrumb navigation
              if (widget.nodeId != null)
                ancestorsAsync.when(
                  data: (ancestors) => _LibraryBreadcrumb(
                    ancestors: ancestors,
                    currentNodeName: widget.nodeName,
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
                          // Track that we're viewing a palette
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && !_isPaletteView) {
                              setState(() => _isPaletteView = true);
                            }
                          });
                          // Use the new simplified effect selector
                          return ColorwayEffectSelectorPage(paletteNode: node);
                        }
                        // Show children as navigation grid
                        // For Architectural Downlighting, show Kelvin chart above the grid
                        if (widget.nodeId == LibraryCategoryIds.architectural) {
                          return Column(
                            children: [
                              const _KelvinReferenceChart(),
                              Expanded(child: _LibraryNodeGrid(children: children)),
                            ],
                          );
                        }
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

/// Kelvin color temperature reference chart for Architectural Downlighting.
/// Shows a gradient bar from 2000K (warm amber) to 6500K (cool blue-white)
/// with labeled temperature stops so users can identify their preferred white.
class _KelvinReferenceChart extends StatelessWidget {
  const _KelvinReferenceChart();

  /// Kelvin temperature → approximate RGB using Tanner Helland algorithm.
  static Color _kelvinToColor(int kelvin) {
    final temp = kelvin / 100.0;
    double r, g, b;

    // Red
    if (temp <= 66) {
      r = 255;
    } else {
      r = 329.698727446 * pow(temp - 60, -0.1332047592);
      r = r.clamp(0, 255);
    }

    // Green
    if (temp <= 66) {
      g = 99.4708025861 * log(temp) - 161.1195681661;
      g = g.clamp(0, 255);
    } else {
      g = 288.1221695283 * pow(temp - 60, -0.0755148492);
      g = g.clamp(0, 255);
    }

    // Blue
    if (temp >= 66) {
      b = 255;
    } else if (temp <= 19) {
      b = 0;
    } else {
      b = 138.5177312231 * log(temp - 10) - 305.0447927307;
      b = b.clamp(0, 255);
    }

    return Color.fromARGB(255, r.round(), g.round(), b.round());
  }

  static const _stops = [
    (kelvin: 2000, label: '2000K', name: 'Candle'),
    (kelvin: 2700, label: '2700K', name: 'Warm'),
    (kelvin: 3000, label: '3000K', name: ''),
    (kelvin: 3500, label: '3500K', name: 'Soft'),
    (kelvin: 4000, label: '4000K', name: 'Neutral'),
    (kelvin: 4500, label: '4500K', name: ''),
    (kelvin: 5000, label: '5000K', name: 'Day'),
    (kelvin: 5500, label: '5500K', name: ''),
    (kelvin: 6500, label: '6500K', name: 'Moon'),
  ];

  @override
  Widget build(BuildContext context) {
    // Build fine-grained gradient colors across the full range
    final gradientColors = <Color>[];
    final gradientStops = <double>[];
    const minK = 2000;
    const maxK = 6500;
    for (var k = minK; k <= maxK; k += 250) {
      gradientColors.add(_kelvinToColor(k));
      gradientStops.add((k - minK) / (maxK - minK));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              const Icon(Icons.thermostat, color: NexGenPalette.textSecondary, size: 14),
              const SizedBox(width: 6),
              Text(
                'Color Temperature Reference',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: NexGenPalette.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Gradient bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                  stops: gradientStops,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.line, width: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Labels row
          SizedBox(
            height: 32,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: _stops.map((stop) {
                    final fraction = (stop.kelvin - minK) / (maxK - minK);
                    final left = fraction * totalWidth;
                    return Positioned(
                      left: left - 18, // center the label
                      top: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            stop.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (stop.name.isNotEmpty)
                            Text(
                              stop.name,
                              style: TextStyle(
                                color: NexGenPalette.textSecondary,
                                fontSize: 7,
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
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
        childAspectRatio: 1.6,
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

    // Architectural Kelvin folders
    if (id.startsWith('arch_k')) return Icons.thermostat_outlined;
    if (id == 'arch_galaxy') return Icons.auto_awesome_outlined;

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

    // Architectural Kelvin folders — use the node's own theme color
    if (id.startsWith('arch_') && node.themeColors != null && node.themeColors!.isNotEmpty) {
      return node.themeColors!.first;
    }

    return NexGenPalette.cyan;
  }

  /// Get gradient color pair for folder nodes, matching the visual style
  /// used by _DesignLibraryCategoryCard and _SubCategoryCard.
  List<Color> _getGradientForNode() {
    final id = node.id;

    // Category gradients (matching _DesignLibraryCategoryCard)
    if (id == LibraryCategoryIds.architectural) return const [Color(0xFFFFB347), Color(0xFFFF7043)];
    if (id == LibraryCategoryIds.holidays) return const [Color(0xFFFF4444), Color(0xFFC2185B)];
    if (id == LibraryCategoryIds.sports) return const [Color(0xFF1976D2), Color(0xFF0D47A1)];
    if (id == LibraryCategoryIds.seasonal) return const [Color(0xFFFF8F00), Color(0xFFE65100)];
    if (id == LibraryCategoryIds.parties) return const [Color(0xFFFF69B4), Color(0xFF9C27B0)];
    if (id == LibraryCategoryIds.security) return const [Color(0xFF4FC3F7), Color(0xFF1565C0)];
    if (id == LibraryCategoryIds.movies) return const [Color(0xFFE040FB), Color(0xFF6A1B9A)];

    // Movie franchise gradients
    if (id == 'franchise_disney') return const [Color(0xFF42A5F5), Color(0xFF1565C0)];
    if (id == 'franchise_marvel') return const [Color(0xFFE53935), Color(0xFFB71C1C)];
    if (id == 'franchise_starwars') return const [Color(0xFF546E7A), Color(0xFF212121)];
    if (id == 'franchise_dc') return const [Color(0xFF1E88E5), Color(0xFF0D47A1)];
    if (id == 'franchise_pixar') return const [Color(0xFF66BB6A), Color(0xFF2E7D32)];
    if (id == 'franchise_dreamworks') return const [Color(0xFF26C6DA), Color(0xFF00695C)];
    if (id == 'franchise_harrypotter') return const [Color(0xFF8D6E63), Color(0xFF3E2723)];
    if (id == 'franchise_nintendo') return const [Color(0xFFEF5350), Color(0xFFB71C1C)];

    // Sports league gradients
    if (id == 'league_nfl') return const [Color(0xFF1565C0), Color(0xFF013369)];
    if (id == 'league_nba') return const [Color(0xFFE53935), Color(0xFF880E4F)];
    if (id == 'league_mlb') return const [Color(0xFF1976D2), Color(0xFF041E42)];
    if (id == 'league_nhl') return const [Color(0xFF424242), Color(0xFF000000)];
    if (id == 'league_mls') return const [Color(0xFF66BB6A), Color(0xFF2E7D32)];
    if (id == 'league_wnba') return const [Color(0xFFFF8F00), Color(0xFFE65100)];
    if (id == 'league_nwsl') return const [Color(0xFF42A5F5), Color(0xFF0D47A1)];

    // Holiday gradients (matching _SubCategoryCard)
    if (id == 'holiday_christmas') return const [Color(0xFF2E7D32), Color(0xFFC62828)];
    if (id == 'holiday_halloween') return const [Color(0xFFFF6D00), Color(0xFF6A1B9A)];
    if (id == 'holiday_july4' || id == 'holiday_july4th') return const [Color(0xFFEF5350), Color(0xFF1565C0)];
    if (id == 'holiday_valentines') return const [Color(0xFFE91E63), Color(0xFFAD1457)];
    if (id == 'holiday_stpatricks') return const [Color(0xFF43A047), Color(0xFF00C853)];
    if (id == 'holiday_easter') return const [Color(0xFFCE93D8), Color(0xFF7B1FA2)];
    if (id == 'holiday_thanksgiving') return const [Color(0xFFFF9800), Color(0xFF8D6E63)];
    if (id == 'holiday_newyears' || id == 'holiday_newyear') return const [Color(0xFFFFD700), Color(0xFFFF6F00)];

    // Season gradients (matching _SubCategoryCard)
    if (id == 'season_spring') return const [Color(0xFF81C784), Color(0xFFF48FB1)];
    if (id == 'season_summer') return const [Color(0xFFFFEE58), Color(0xFF29B6F6)];
    if (id == 'season_autumn') return const [Color(0xFFFF8F00), Color(0xFF6D4C41)];
    if (id == 'season_winter') return const [Color(0xFF81D4FA), Color(0xFF7E57C2)];

    // Party/event gradients
    if (id == 'event_birthdays' || id == 'event_birthday') return const [Color(0xFF00E5FF), Color(0xFFFF4081)];
    if (id == 'event_bday_boy') return const [Color(0xFF42A5F5), Color(0xFF1565C0)];
    if (id == 'event_bday_girl') return const [Color(0xFFFF80AB), Color(0xFFAD1457)];
    if (id == 'event_bday_adult') return const [Color(0xFFFFD54F), Color(0xFFFF6F00)];
    if (id == 'event_weddings' || id == 'event_wedding') return const [Color(0xFFFFE0B2), Color(0xFFBCAAA4)];
    if (id == 'event_babyshower') return const [Color(0xFF80DEEA), Color(0xFFF8BBD0)];
    if (id == 'event_graduation') return const [Color(0xFF212121), Color(0xFFFFD700)];
    if (id == 'event_anniversary') return const [Color(0xFFFFD700), Color(0xFFE91E63)];

    // NCAA / Conference folders
    if (id.startsWith('ncaafb_')) return const [Color(0xFFB71C1C), Color(0xFF8B0000)];
    if (id.startsWith('ncaabb_')) return const [Color(0xFFFF8F00), Color(0xFFE65100)];
    if (id.startsWith('ncaa_') || id.startsWith('conf_')) return const [Color(0xFF3949AB), Color(0xFF1A237E)];

    // Architectural Kelvin folders — use the node's own theme colors
    if (id.startsWith('arch_') && node.themeColors != null && node.themeColors!.length >= 2) {
      return [node.themeColors![0], node.themeColors![1]];
    }

    // Default: derive from theme color
    final c = _getFolderThemeColor();
    return [c, c.withValues(alpha: 0.5)];
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

  /// Build a folder card with single hero icon design matching main category cards
  Widget _buildFolderCard(BuildContext context) {
    final heroIcon = _iconForNode();
    final accentColor = _getFolderThemeColor();
    final gradientColors = _getGradientForNode();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push('/library/${node.id}', extra: {'name': node.name});
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                gradientColors[0].withValues(alpha: 0.25),
                gradientColors[1].withValues(alpha: 0.15),
                NexGenPalette.matteBlack.withValues(alpha: 0.95),
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Centered radial glow behind icon
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          gradientColors[0].withValues(alpha: 0.3),
                          gradientColors[1].withValues(alpha: 0.1),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Single hero icon - centered and prominent
                    Expanded(
                      child: Center(
                        child: Icon(
                          heroIcon,
                          size: 52,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: accentColor.withValues(alpha: 0.8),
                              blurRadius: 24,
                            ),
                            Shadow(
                              color: gradientColors[0].withValues(alpha: 0.5),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Folder name with arrow
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            node.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: accentColor.withValues(alpha: 0.8),
                          size: 10,
                        ),
                      ],
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

  /// Build a palette card with flowing gradient colors
  Widget _buildPaletteCard(BuildContext context) {
    final colors = node.themeColors ?? [NexGenPalette.cyan, NexGenPalette.blue];
    final gradient = colors.length >= 2
        ? [colors[0], colors[1]]
        : [colors.first, colors.first.withValues(alpha: 0.7)];
    // Adaptive contrast — dark text on light cards, white on dark cards
    final textColor = NexGenPalette.contrastTextFor(gradient);
    final secondaryColor = NexGenPalette.contrastSecondaryFor(gradient);
    final isLight = textColor == const Color(0xFF1A1A1A);
    final dotBorder = isLight ? const Color(0xFF4A4A4A) : Colors.white;
    final watermark = isLight
        ? Colors.black.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.1);

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
                color: watermark,
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
                            border: Border.all(color: dotBorder, width: 2),
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
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: isLight ? Colors.white38 : Colors.black26, blurRadius: 2)],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (node.description != null)
                        Text(
                          node.description!,
                          style: TextStyle(
                            color: secondaryColor,
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
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4, // Match "Recommended for You" layout
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.85, // Slightly wider cards
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

/// Global mood selector for the main Explore page.
/// Allows users to pre-filter patterns by mood before navigating into categories.
/// The selection persists when navigating to color cards.
class _GlobalMoodSelector extends StatelessWidget {
  final EffectMood? selectedMood;
  final ValueChanged<EffectMood?> onMoodSelected;

  const _GlobalMoodSelector({
    required this.selectedMood,
    required this.onMoodSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tune, size: 16, color: NexGenPalette.textSecondary),
            const SizedBox(width: 6),
            Text(
              'Pre-filter by mood',
              style: TextStyle(
                color: NexGenPalette.textSecondary,
                fontSize: 12,
              ),
            ),
            if (selectedMood != null) ...[
              const Spacer(),
              GestureDetector(
                onTap: () => onMoodSelected(null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Clear filter',
                        style: TextStyle(
                          color: NexGenPalette.cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.close, size: 12, color: NexGenPalette.cyan),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // "All" chip (no filter)
              _GlobalMoodChip(
                label: 'All Moods',
                emoji: '',
                isSelected: selectedMood == null,
                color: NexGenPalette.cyan,
                onTap: () => onMoodSelected(null),
              ),
              const SizedBox(width: 8),
              // Mood chips
              for (final mood in EffectMoodSystem.displayOrder) ...[
                _GlobalMoodChip(
                  label: mood.label,
                  emoji: mood.emoji,
                  isSelected: selectedMood == mood,
                  color: mood.color,
                  onTap: () => onMoodSelected(selectedMood == mood ? null : mood),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact mood chip for the global mood selector
class _GlobalMoodChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _GlobalMoodChip({
    required this.label,
    required this.emoji,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : NexGenPalette.line,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji.isNotEmpty) ...[
              Text(emoji, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
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
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Animated effect preview - more prominent for compact cards
            Expanded(
              flex: 3,
              child: EffectPreviewWidget(
                effectId: effectId,
                colors: colors,
                borderRadius: 10,
              ),
            ),
            // Pattern info - compact for 4-column layout
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                pattern.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
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
      // Extract effect ID and colors from payload to check for custom effects
      final effectId = _getEffectId();
      final colorsRgbw = _getColorsRgbw();

      // Check if this is a custom Lumina effect (ID >= 1000)
      final isCustomEffect = await _executeCustomEffectIfNeeded(
        effectId: effectId,
        colors: colorsRgbw,
        repo: repo,
      );

      if (!isCustomEffect) {
        // Standard WLED effect - apply the pattern's wledPayload directly
        final success = await repo.applyJson(pattern.wledPayload);

        if (!success) {
          throw Exception('Device did not accept command');
        }
      }

      // Update the active preset label so home screen reflects the change
      ref.read(activePresetLabelProvider.notifier).state = pattern.name;

      if (context.mounted) {
        // Show pattern adjustment panel in a bottom sheet
        _showAdjustmentPanel(context, ref);
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

  /// Extract colors as RGBW arrays for custom effect execution
  List<List<int>> _getColorsRgbw() {
    try {
      final payload = pattern.wledPayload;
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final firstSeg = seg.first;
        if (firstSeg is Map) {
          final cols = firstSeg['col'];
          if (cols is List && cols.isNotEmpty) {
            final colors = <List<int>>[];
            for (final col in cols) {
              if (col is List && col.length >= 3) {
                colors.add([
                  (col[0] as num).toInt().clamp(0, 255),
                  (col[1] as num).toInt().clamp(0, 255),
                  (col[2] as num).toInt().clamp(0, 255),
                  col.length >= 4 ? (col[3] as num).toInt().clamp(0, 255) : 0,
                ]);
              }
            }
            if (colors.isNotEmpty) return colors;
          }
        }
      }
    } catch (_) {}
    return [[255, 255, 255, 0]];
  }

  void _showAdjustmentPanel(BuildContext context, WidgetRef ref) {
    // Extract pattern values from wledPayload
    final payload = pattern.wledPayload;
    final seg = payload['seg'];
    int effectId = 0;
    int speed = 128;
    int intensity = 128;
    int grouping = 1;
    int spacing = 0;
    List<Color> colors = _getColors();

    if (seg is List && seg.isNotEmpty) {
      final firstSeg = seg.first;
      if (firstSeg is Map) {
        effectId = (firstSeg['fx'] as int?) ?? 0;
        speed = (firstSeg['sx'] as int?) ?? 128;
        intensity = (firstSeg['ix'] as int?) ?? 128;
        // WLED uses 'grp' and 'spc', but check old keys 'gp'/'sp' as fallback
        grouping = (firstSeg['grp'] as int?) ?? (firstSeg['gp'] as int?) ?? 1;
        spacing = (firstSeg['spc'] as int?) ?? (firstSeg['sp'] as int?) ?? 0;
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PatternAdjustmentBottomSheet(
        patternName: pattern.name,
        effectId: effectId,
        speed: speed,
        intensity: intensity,
        grouping: grouping,
        spacing: spacing,
        colors: colors,
      ),
    );
  }
}

/// Bottom sheet containing PatternAdjustmentPanel for fine-tuning a selected pattern
class _PatternAdjustmentBottomSheet extends ConsumerStatefulWidget {
  final String patternName;
  final int effectId;
  final int speed;
  final int intensity;
  final int grouping;
  final int spacing;
  final List<Color> colors;

  const _PatternAdjustmentBottomSheet({
    required this.patternName,
    required this.effectId,
    required this.speed,
    required this.intensity,
    required this.grouping,
    required this.spacing,
    required this.colors,
  });

  @override
  ConsumerState<_PatternAdjustmentBottomSheet> createState() => _PatternAdjustmentBottomSheetState();
}

class _PatternAdjustmentBottomSheetState extends ConsumerState<_PatternAdjustmentBottomSheet> {
  late int _speed;
  late int _intensity;
  late int _grouping;
  late int _spacing;
  late int _effectId;
  late bool _reverse;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _speed = widget.speed;
    _intensity = widget.intensity;
    _grouping = widget.grouping;
    _spacing = widget.spacing;
    _effectId = widget.effectId;
    _reverse = false;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _applyChange(Map<String, dynamic> segUpdate) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final repo = ref.read(wledRepositoryProvider);
      if (repo != null) {
        await repo.applyJson({'seg': [segUpdate]});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isStatic = _effectId == 0;

    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.colors.length >= 2
                            ? [widget.colors[0], widget.colors[1]]
                            : [widget.colors.first, widget.colors.first],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isStatic ? Icons.circle : Icons.auto_awesome,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Now Playing',
                          style: TextStyle(
                            color: NexGenPalette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          widget.patternName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Speed slider (hide for static effects)
              if (!isStatic) ...[
                _buildSliderRow(
                  icon: Icons.speed,
                  label: 'Speed',
                  value: _speed.toDouble(),
                  onChanged: (v) {
                    setState(() => _speed = v.round());
                    _applyChange({'sx': _speed});
                  },
                ),
                const SizedBox(height: 12),
              ],
              // Intensity slider
              _buildSliderRow(
                icon: Icons.tune,
                label: 'Intensity',
                value: _intensity.toDouble(),
                onChanged: (v) {
                  setState(() => _intensity = v.round());
                  _applyChange({'ix': _intensity});
                },
              ),
              const SizedBox(height: 12),
              // Direction toggle (hide for static effects)
              if (!isStatic) ...[
                Row(
                  children: [
                    const Icon(Icons.swap_horiz, color: NexGenPalette.cyan, size: 20),
                    const SizedBox(width: 12),
                    const Text('Direction', style: TextStyle(color: Colors.white, fontSize: 14)),
                    const Spacer(),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('L→R', style: TextStyle(fontSize: 12))),
                        ButtonSegment(value: true, label: Text('R→L', style: TextStyle(fontSize: 12))),
                      ],
                      selected: {_reverse},
                      onSelectionChanged: (s) {
                        final rev = s.isNotEmpty ? s.first : false;
                        setState(() => _reverse = rev);
                        _applyChange({'rev': rev});
                      },
                      style: ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              // Pixel layout section
              Row(
                children: [
                  const Icon(Icons.grid_view, color: NexGenPalette.cyan, size: 20),
                  const SizedBox(width: 8),
                  Text('Pixel Layout', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white)),
                ],
              ),
              const SizedBox(height: 8),
              // Grouping slider
              _buildSliderRow(
                icon: Icons.blur_on,
                label: 'Grouping',
                value: _grouping.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                onChanged: (v) {
                  setState(() => _grouping = v.round());
                  _applyChange({'grp': _grouping});
                },
              ),
              const SizedBox(height: 8),
              // Spacing slider
              _buildSliderRow(
                icon: Icons.space_bar,
                label: 'Spacing',
                value: _spacing.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                onChanged: (v) {
                  setState(() => _spacing = v.round());
                  _applyChange({'spc': _spacing});
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0,
    double max = 255,
    int? divisions,
  }) {
    return Row(
      children: [
        Icon(icon, color: NexGenPalette.cyan, size: 20),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${value.round()}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
