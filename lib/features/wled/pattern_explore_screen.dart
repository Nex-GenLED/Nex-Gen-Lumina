import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/mock_pattern_repository.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/features/wled/lumina_custom_effects.dart';
import 'package:nexgen_command/features/wled/pattern_library_browser.dart';
import 'package:nexgen_command/features/wled/pattern_category_detail.dart';
import 'package:nexgen_command/features/wled/pattern_grid_widgets.dart';

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
      const fallback = 'Your Quick Picks';
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
          pagePadding(
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
                  pagePadding(child: const MySavedDesignsSection()),

                  // 2. Your Quick Picks section
                  pagePadding(
                    child: PatternCategoryRow(title: _greetingTitle(), patterns: recs, query: '', isFeatured: true),
                  ),
                  gap(24),

                  // 3. Recent Patterns section
                  pagePadding(child: const RecentPatternsSection()),

                  // 4. Pinned Categories section (user-added folders, in order added)
                  pagePadding(child: const PinnedCategoriesSection()),

                  // 5. Browse Design Library section (at bottom)
                  pagePadding(
                    child: DesignLibraryBrowser(),
                  ),
                  gap(28),
                ]),
              ),
            ),
        ]),
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
