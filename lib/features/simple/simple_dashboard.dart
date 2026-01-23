import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/simple/simple_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/nav.dart';

/// Simplified dashboard for less tech-savvy users.
/// Shows large, easy-to-use controls with minimal complexity.
class SimpleDashboard extends ConsumerWidget {
  const SimpleDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wledState = ref.watch(wledStateProvider);
    final brightness = wledState?.brightness ?? 128;
    final isOn = wledState?.isOn ?? false;

    return Scaffold(
      backgroundColor: NexGenPalette.deepNavy,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            // Header
            _buildHeader(context),
            const SizedBox(height: 32),

            // Large On/Off Buttons
            _buildPowerButtons(context, ref, isOn),
            const SizedBox(height: 32),

            // Brightness Slider
            _buildBrightnessSlider(context, ref, brightness),
            const SizedBox(height: 32),

            // My Favorites Section
            _buildFavoritesSection(context, ref),
            const SizedBox(height: 32),

            // Voice Control Button
            _buildVoiceButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Lights',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Simple, easy control',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white.withOpacity(0.7),
              ),
        ),
      ],
    );
  }

  Widget _buildPowerButtons(BuildContext context, WidgetRef ref, bool isOn) {
    return Row(
      children: [
        Expanded(
          child: _LargePowerButton(
            label: 'All On',
            icon: Icons.lightbulb,
            isActive: isOn,
            activeColor: NexGenPalette.cyan,
            onPressed: () => _turnOn(ref),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _LargePowerButton(
            label: 'All Off',
            icon: Icons.lightbulb_outline,
            isActive: !isOn,
            activeColor: Colors.grey.shade700,
            onPressed: () => _turnOff(ref),
          ),
        ),
      ],
    );
  }

  Widget _buildBrightnessSlider(BuildContext context, WidgetRef ref, int brightness) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.brightness_6, color: NexGenPalette.cyan, size: 28),
              const SizedBox(width: 12),
              Text(
                'Brightness',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 60,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 12,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 18),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 32),
                activeTrackColor: NexGenPalette.cyan,
                inactiveTrackColor: Colors.white.withOpacity(0.1),
                thumbColor: NexGenPalette.cyan,
                overlayColor: NexGenPalette.cyan.withOpacity(0.2),
              ),
              child: Slider(
                value: brightness.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  _setBrightness(ref, value.toInt());
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(brightness / 255 * 100).round()}%',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: NexGenPalette.cyan,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesSection(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(simpleFavoritesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star, color: NexGenPalette.violet, size: 28),
            const SizedBox(width: 12),
            Text(
              'My Favorites',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        favoritesAsync.when(
          data: (favoriteIds) {
            if (favoriteIds.isEmpty) {
              return _buildEmptyFavorites(context);
            }
            return Column(
              children: favoriteIds.take(5).map((patternId) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FavoritePatternCard(patternId: patternId),
                );
              }).toList(),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, stack) => _buildEmptyFavorites(context),
        ),
      ],
    );
  }

  Widget _buildEmptyFavorites(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.star_border, color: Colors.white.withOpacity(0.5), size: 48),
          const SizedBox(height: 12),
          Text(
            'No favorites yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withOpacity(0.7),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your favorite lighting patterns in Settings',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.5),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceButton(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.voiceAssistants),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [NexGenPalette.violet, NexGenPalette.cyan],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: NexGenPalette.cyan.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic, color: Colors.white, size: 36),
            const SizedBox(width: 16),
            Text(
              'Voice Control',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _turnOn(WidgetRef ref) {
    HapticFeedback.mediumImpact();
    ref.read(wledStateProvider.notifier).togglePower(true);
  }

  void _turnOff(WidgetRef ref) {
    HapticFeedback.mediumImpact();
    ref.read(wledStateProvider.notifier).togglePower(false);
  }

  void _setBrightness(WidgetRef ref, int brightness) {
    ref.read(wledStateProvider.notifier).setBrightness(brightness);
  }
}

/// Large power button for Simple Mode
class _LargePowerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onPressed;

  const _LargePowerButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? activeColor : Colors.white.withOpacity(0.1),
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 56,
              color: isActive ? activeColor : Colors.white.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: isActive ? activeColor : Colors.white.withOpacity(0.5),
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Favorite pattern card for Simple Mode
class _FavoritePatternCard extends ConsumerWidget {
  final String patternId;

  const _FavoritePatternCard({required this.patternId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patterns = ref.watch(publicPatternLibraryProvider);

    // Find the pattern by ID (searching through all pattern lists)
    GradientPattern? pattern;
    for (final p in patterns.all) {
      if (p.name.toLowerCase().replaceAll(' ', '_') == patternId.toLowerCase()) {
        pattern = p;
        break;
      }
    }

    // Fallback pattern if not found
    final displayName = pattern?.name ?? _getFallbackName(patternId);
    final displayIcon = pattern != null ? _getIconForPattern(pattern) : Icons.lightbulb;

    return GestureDetector(
      onTap: () => _applyPattern(ref, pattern),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              NexGenPalette.cyan.withOpacity(0.1),
              NexGenPalette.violet.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 20),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(displayIcon, color: NexGenPalette.cyan, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                displayName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  String _getFallbackName(String id) {
    // Convert ID to readable name
    return id.split('_').map((word) => word[0].toUpperCase() + word.substring(1)).join(' ');
  }

  IconData _getIconForPattern(GradientPattern pattern) {
    final name = pattern.name.toLowerCase();
    if (name.contains('white')) return Icons.wb_sunny;
    if (name.contains('christmas') || name.contains('holiday')) return Icons.celebration;
    if (name.contains('halloween')) return Icons.auto_awesome;
    if (name.contains('fire') || name.contains('flame')) return Icons.local_fire_department;
    if (name.contains('rainbow')) return Icons.water_drop;
    if (name.contains('patriot') || name.contains('america')) return Icons.flag;
    return Icons.auto_awesome;
  }

  void _applyPattern(WidgetRef ref, GradientPattern? pattern) async {
    if (pattern == null) return;

    HapticFeedback.mediumImpact();

    // Record usage for analytics (using pattern name as ID)
    final patternId = pattern.name.toLowerCase().replaceAll(' ', '_');
    ref.read(patternUsageProvider.notifier).recordUsage(patternId);

    // Apply the pattern
    final repo = ref.read(wledRepositoryProvider);
    if (repo != null) {
      await repo.applyJson(pattern.toWledPayload());
    }
  }
}
