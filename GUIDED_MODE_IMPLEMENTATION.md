# Guided Mode Implementation Guide

## Overview

Guided Mode is a balanced UX enhancement that improves usability for less tech-savvy users while maintaining full functionality for power users. Unlike "Simple Mode" (which hides features), Guided Mode **organizes and clarifies** the existing interface.

## ✅ Completed Infrastructure

### 1. Core Provider (`lib/app_providers.dart`)
- ✅ Added `guidedModeProvider` (default: `true`)
- Toggleable in Settings for users who prefer classic layout

### 2. Favorites System (`lib/features/favorites/favorites_providers.dart`)
- ✅ `FavoritePattern` model with usage tracking
- ✅ `favoritesPatternsProvider` - streams top 5 most-used patterns
- ✅ `recentPatternsProvider` - streams last 5 used patterns
- ✅ `FavoritesNotifier` with methods:
  - `trackPatternUsage()` - auto-adds patterns on use
  - `addToFavorites()` - manual favorite
  - `removeFromFavorites()` - unfavorite
  - `isFavorited()` - check if favorited

### 3. Help System (`lib/widgets/help_button.dart`)
- ✅ `HelpButton` - shows contextual dialog with title, explanation, and tips
- ✅ `InlineHelpIcon` - smaller icon for inline placement
- ✅ `HelpTooltip` - tooltip wrapper for any widget

## 🚧 Pending Implementation

### Priority 1: Dashboard Enhancements

#### A. Larger Brightness Slider
**Current:** 100px wide, 4px track height, cramped in control bar
**Target:** Full-width or 200px, 6px track height, dedicated row with label

**Changes needed in `lib/nav.dart` (lines 1058-1080):**
```dart
// BEFORE:
Row(mainAxisSize: MainAxisSize.min, children: [
  Text('Brightness', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white)),
  const SizedBox(width: 8),
  SizedBox(
    width: 100,  // ← TOO SMALL
    child: Slider(...),
  ),
]),

// AFTER (in Guided Mode):
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Row(
      children: [
        Text('Brightness', style: Theme.of(context).textTheme.labelMedium),
        const Spacer(),
        Consumer(builder: (context, ref, _) {
          final state = ref.watch(wledStateProvider);
          return Text('${(state.brightness / 255 * 100).round()}%',
            style: TextStyle(color: NexGenPalette.cyan, fontWeight: FontWeight.bold),
          );
        }),
        HelpButton(
          title: 'Brightness',
          explanation: 'Drag the slider to adjust how bright your lights are.',
          tip: 'You can also say "Set brightness to 50%" to Lumina',
        ),
      ],
    ),
    SizedBox(
      width: double.infinity,  // ← FULL WIDTH
      child: SliderTheme(
        data: Theme.of(context).sliderTheme.copyWith(
          trackHeight: 6,  // ← THICKER TRACK
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
        ),
        child: Slider(...),
      ),
    ),
  ],
)
```

#### B. "All Off" Button in AppBar
**Add to `lib/nav.dart` AppBar actions (line ~750):**
```dart
appBar: GlassAppBar(
  title: Text('Hello, $userName'),
  actions: [
    // NEW: All Off button
    Consumer(builder: (context, ref, _) {
      final state = ref.watch(wledStateProvider);
      if (!state.isOn) return const SizedBox.shrink();  // Hide when already off

      return IconButton(
        icon: const Icon(Icons.power_off, color: Colors.red),
        tooltip: 'Turn All Off',
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Turn Off All Lights?'),
              content: Text('This will turn off all controllers in your current area.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: Text('Turn Off'),
                ),
              ],
            ),
          );

          if (confirm == true) {
            final ips = ref.read(activeAreaControllerIpsProvider);
            await Future.wait(ips.map((ip) async {
              try {
                final svc = WledService('http://$ip');
                await svc.setState(on: false);
              } catch (e) {
                debugPrint('Turn off failed for $ip: $e');
              }
            }));

            ref.read(activePresetLabelProvider.notifier).clear();
          }
        },
      );
    }),

    // ... existing connection status, controller selector, settings
  ],
)
```

#### C. Current Status Card Overlay
**Add below hero image (line ~899):**
```dart
// Current status card (Guided Mode only)
if (ref.watch(guidedModeProvider))
  Positioned(
    left: 16,
    bottom: 70,  // Above the control bar
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lightbulb, size: 14, color: NexGenPalette.cyan),
                  const SizedBox(width: 6),
                  Text('Living Room', style: TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 2),
              Consumer(builder: (context, ref, _) {
                final activePreset = ref.watch(activePresetLabelProvider);
                final state = ref.watch(wledStateProvider);
                final label = activePreset ?? (state.connected ? state.effectName : 'Offline');
                return Text(
                  label,
                  style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
                );
              }),
            ],
          ),
        ),
      ),
    ),
  ),
```

#### D. Voice Prompt Hint
**Add after quick preset buttons (around line 1300):**
```dart
// Voice prompt hint (Guided Mode only)
if (ref.watch(guidedModeProvider)) ...[
  const SizedBox(height: 16),
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, color: NexGenPalette.cyan, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Try voice control',
                  style: TextStyle(color: NexGenPalette.cyan, fontWeight: FontWeight.w600),
                ),
                Text(
                  '"Make it festive" or "Turn on warm white"',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.arrow_forward, color: NexGenPalette.cyan),
            onPressed: () {
              // Switch to Lumina tab (index 2)
              ref.read(selectedTabIndexProvider.notifier).state = 2;
            },
          ),
        ],
      ),
    ),
  ),
],
```

### Priority 2: Pattern Library Enhancements

**File:** `lib/features/wled/pattern_library_pages.dart`

Add to `PatternLibraryHome` widget (around line 50, before search bar):

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final isGuided = ref.watch(guidedModeProvider);

  return Column(
    children: [
      // NEW: Favorites section (Guided Mode)
      if (isGuided) ...[
        const SizedBox(height: 16),
        _FavoritesSection(),
        const SizedBox(height: 12),
        _RecentlyUsedSection(),
        const SizedBox(height: 16),
        Divider(color: NexGenPalette.line),
      ],

      // Existing search bar
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(...),
      ),

      // ... rest of existing content
    ],
  );
}

// NEW: Favorites widget
class _FavoritesSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoritesPatternsProvider);

    return favoritesAsync.when(
      data: (favorites) {
        if (favorites.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.star, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'My Favorites',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      // TODO: Navigate to favorites management screen
                    },
                    child: Text('Edit'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: favorites.length,
                itemBuilder: (context, index) {
                  final favorite = favorites[index];
                  return _FavoriteCard(favorite: favorite);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// NEW: Favorite card widget
class _FavoriteCard extends ConsumerWidget {
  final FavoritePattern favorite;

  const _FavoriteCard({required this.favorite});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () async {
          // Apply the favorite pattern
          final repo = ref.read(wledRepositoryProvider);
          if (repo != null) {
            await repo.applyJson(favorite.wledPayload);
            ref.read(activePresetLabelProvider.notifier).state = favorite.name;

            // Track usage
            ref.read(favoritesNotifierProvider.notifier).trackPatternUsage(
              patternId: favorite.patternId,
              patternName: favorite.name,
              wledPayload: favorite.wledPayload,
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.palette,
                color: NexGenPalette.cyan,
                size: 32,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  favorite.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${favorite.usageCount} uses',
                style: TextStyle(fontSize: 10, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// NEW: Recently Used section
class _RecentlyUsedSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentPatternsProvider);

    return recentAsync.when(
      data: (recent) {
        if (recent.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history, color: NexGenPalette.cyan, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Recently Used',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recent.map((pattern) {
                  return ActionChip(
                    label: Text(pattern.name),
                    avatar: Icon(Icons.access_time, size: 16),
                    onPressed: () async {
                      // Apply pattern
                      final repo = ref.read(wledRepositoryProvider);
                      if (repo != null) {
                        await repo.applyJson(pattern.wledPayload);
                        ref.read(activePresetLabelProvider.notifier).state = pattern.name;

                        // Track usage
                        ref.read(favoritesNotifierProvider.notifier).trackPatternUsage(
                          patternId: pattern.patternId,
                          patternName: pattern.name,
                          wledPayload: pattern.wledPayload,
                        );
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
```

### Priority 3: Schedule Quick Input

**File:** `lib/features/schedule/my_schedule_page.dart`

Add after Autopilot card (line ~58):

```dart
// Quick Schedule Input (Guided Mode)
if (ref.watch(guidedModeProvider)) ...[
  const SizedBox(height: 16),
  _QuickScheduleInput(),
  const SizedBox(height: 16),
],
```

Widget already partially exists in the file but needs voice integration:

```dart
class _QuickScheduleInput extends ConsumerStatefulWidget {
  const _QuickScheduleInput();

  @override
  ConsumerState<_QuickScheduleInput> createState() => _QuickScheduleInputState();
}

class _QuickScheduleInputState extends ConsumerState<_QuickScheduleInput> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _askLumina(BuildContext context) async {
    // ... existing implementation already handles this
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: NexGenPalette.gunmetal,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: NexGenPalette.cyan, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Quick Schedule',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                HelpButton(
                  title: 'Quick Schedule',
                  explanation: 'Type or speak a natural request like "Turn on warm white every night at sunset"',
                  tip: 'Lumina will automatically parse your request and create the schedule for you.',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Examples:',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              '• "Turn on warm white every night at sunset"\n'
              '• "Weekdays at 8am, bright white"\n'
              '• "Turn off lights at 11:30 PM"',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white54,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type or speak to Lumina...',
                      filled: true,
                      fillColor: NexGenPalette.matteBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: NexGenPalette.line),
                      ),
                    ),
                    onSubmitted: (_) => _askLumina(context),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.mic,
                    color: NexGenPalette.cyan,
                    size: 28,
                  ),
                  onPressed: () async {
                    // TODO: Integrate speech-to-text from nav.dart voice implementation
                  },
                ),
                IconButton(
                  icon: _loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.send, color: NexGenPalette.cyan),
                  onPressed: _loading ? null : () => _askLumina(context),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Colors.red.shade300, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

### Priority 4: Settings Reorganization

**File:** `lib/features/site/settings_page.dart`

Replace flat list (line ~59) with grouped sections:

```dart
body: ListView(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
  children: [
    // Guided Mode toggle (show at top)
    if (true) ...[  // Always show toggle
      ListTile(
        leading: Icon(Icons.auto_awesome, color: NexGenPalette.cyan),
        title: Text('Guided Mode'),
        subtitle: Text('Simplified interface with helpful hints'),
        trailing: Consumer(builder: (context, ref, _) {
          final isGuided = ref.watch(guidedModeProvider);
          return Switch(
            value: isGuided,
            onChanged: (value) {
              ref.read(guidedModeProvider.notifier).state = value;
            },
          );
        }),
      ),
      Divider(color: NexGenPalette.line),
      const SizedBox(height: 8),
    ],

    // User Profile (existing)
    _UserProfileEntry(),
    const SizedBox(height: 24),

    // 🏠 My Home section
    _SectionHeader(
      icon: Icons.home,
      title: 'My Home',
      color: NexGenPalette.cyan,
    ),
    const SizedBox(height: 12),
    _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.photo_camera,
          title: 'House Photo',
          subtitle: 'Update your home photo',
          trailing: Text('Change', style: TextStyle(color: NexGenPalette.cyan)),
          onTap: () => context.push(AppRoutes.profileEdit),
        ),
        Divider(color: NexGenPalette.line),
        _SettingsTile(
          icon: Icons.location_city,
          title: 'Property',
          subtitle: Consumer(builder: (context, ref, _) {
            final areasList = ref.watch(propertyAreasProvider);
            return Text('${areasList.length} propert${areasList.length == 1 ? 'y' : 'ies'}');
          }),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => context.push(AppRoutes.myProperties),
        ),
        Divider(color: NexGenPalette.line),
        _SettingsTile(
          icon: Icons.lightbulb,
          title: 'Controllers & Devices',
          subtitle: Consumer(builder: (context, ref, _) {
            final controllers = ref.watch(controllersStreamProvider).maybeWhen(
              data: (list) => list,
              orElse: () => <ControllerInfo>[],
            );
            final online = controllers.where((c) => c.isOnline).length;
            return Text('$online/${controllers.length} online');
          }),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => context.push(AppRoutes.settingsSystem),
        ),
      ],
    ),

    const SizedBox(height: 24),

    // 🎙️ Voice & Shortcuts section
    _SectionHeader(
      icon: Icons.mic,
      title: 'Voice & Shortcuts',
      color: Colors.purple,
    ),
    const SizedBox(height: 12),
    _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.record_voice_over,
          title: 'Siri Shortcuts',
          subtitle: Text('Connected'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => context.push(AppRoutes.voiceAssistants),
        ),
        Divider(color: NexGenPalette.line),
        _SettingsTile(
          icon: Icons.assistant,
          title: 'Google Assistant',
          subtitle: Text('Not set up'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => context.push(AppRoutes.voiceAssistants),
        ),
        Divider(color: NexGenPalette.line),
        _SettingsTile(
          icon: Icons.smart_toy,
          title: 'Alexa',
          subtitle: Text('Not set up'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => context.push(AppRoutes.voiceAssistants),
        ),
      ],
    ),

    const SizedBox(height: 24),

    // ⚡ Automation section
    _SectionHeader(
      icon: Icons.auto_awesome,
      title: 'Automation',
      color: Colors.orange,
    ),
    const SizedBox(height: 12),
    _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.smart_toy,
          title: 'Autopilot',
          subtitle: Consumer(builder: (context, ref, _) {
            final enabled = ref.watch(autopilotEnabledProvider);
            return Text(enabled ? 'Active' : 'Disabled');
          }),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => context.push('/schedule'),  // Switch to schedule tab
        ),
        Divider(color: NexGenPalette.line),
        _SettingsTile(
          icon: Icons.location_on,
          title: 'Geofencing',
          subtitle: Text('Automate based on location'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => context.push(AppRoutes.geofenceSetup),
        ),
      ],
    ),

    const SizedBox(height: 24),

    // 🆘 Help & Support section
    _SectionHeader(
      icon: Icons.help,
      title: 'Help & Support',
      color: Colors.green,
    ),
    const SizedBox(height: 12),
    _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.video_library,
          title: 'Video Tutorials',
          subtitle: Text('Step-by-step guides'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () async {
            // Open YouTube playlist
            final url = Uri.parse('https://youtube.com/playlist?list=YOUR_PLAYLIST_ID');
            if (await canLaunchUrl(url)) {
              await launchUrl(url);
            }
          },
        ),
        Divider(color: NexGenPalette.line),
        _SettingsTile(
          icon: Icons.phone,
          title: 'Contact Support',
          subtitle: Text('Get help from our team'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => context.push(AppRoutes.helpCenter),
        ),
        Divider(color: NexGenPalette.line),
        _SettingsTile(
          icon: Icons.chat,
          title: 'Live Chat',
          subtitle: Text('Chat with support'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
            // TODO: Implement live chat
          },
        ),
      ],
    ),

    const SizedBox(height: 24),

    // ⚙️ Advanced Settings (collapsed by default in Guided Mode)
    Consumer(builder: (context, ref, _) {
      final isGuided = ref.watch(guidedModeProvider);
      if (isGuided) {
        // Show as expandable tile
        return ExpansionTile(
          leading: Icon(Icons.settings, color: Colors.grey),
          title: Text('Advanced Settings'),
          subtitle: Text('Hardware, zones, technical config'),
          children: [
            _SettingsTile(
              icon: Icons.hardware,
              title: 'Hardware Config',
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.push(AppRoutes.hardwareConfig),
            ),
            _SettingsTile(
              icon: Icons.hub,
              title: 'Zone Configuration',
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.push(AppRoutes.wledZones),
            ),
            _SettingsTile(
              icon: Icons.cloud,
              title: 'Remote Access',
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.push(AppRoutes.remoteAccess),
            ),
          ],
        );
      } else {
        // Show as regular section in non-guided mode
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.settings,
              title: 'Advanced',
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            _SettingsCard(
              children: [
                // ... advanced settings tiles
              ],
            ),
          ],
        );
      }
    }),
  ],
)

// NEW: Helper widgets
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: NexGenPalette.cyan, size: 20),
      title: Text(title),
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
```

## Integration with Existing Features

### Track Pattern Usage
Whenever a pattern is applied, call the favorites tracker:

**In `lib/nav.dart` (Quick Preset buttons):**
```dart
// After applying pattern
ref.read(favoritesNotifierProvider.notifier).trackPatternUsage(
  patternId: 'warm_white',  // Generate stable ID
  patternName: 'Warm White',
  wledPayload: payload,
);
```

**In `lib/features/wled/pattern_library_pages.dart` (Pattern cards):**
```dart
// When user taps "Play" button
onPressed: () async {
  await repo.applyJson(pattern.toWledPayload());

  // Track usage
  ref.read(favoritesNotifierProvider.notifier).trackPatternUsage(
    patternId: pattern.id,
    patternName: pattern.name,
    wledPayload: pattern.toWledPayload(),
  );
}
```

**In `lib/features/ai/lumina_chat_screen.dart` (AI-generated patterns):**
```dart
// After applying Lumina suggestion
ref.read(favoritesNotifierProvider.notifier).trackPatternUsage(
  patternId: 'ai_${DateTime.now().millisecondsSinceEpoch}',
  patternName: msg.text,  // Use the user's prompt as name
  wledPayload: msg.wledPayload,
);
```

## Testing Checklist

### Guided Mode Toggle
- [ ] Toggle appears in Settings
- [ ] Switching modes persists across app restarts
- [ ] UI updates immediately when toggled

### Dashboard
- [ ] Brightness slider is larger in Guided Mode
- [ ] "All Off" button appears in AppBar when lights are on
- [ ] Current status card shows active pattern name
- [ ] Voice prompt hint appears at bottom
- [ ] Help buttons show contextual dialogs

### Favorites
- [ ] Patterns are auto-added to favorites after 1 use
- [ ] Favorites appear in Pattern Library (top section)
- [ ] Tapping favorite applies pattern immediately
- [ ] Usage count increments on each use

### Recently Used
- [ ] Last 5 patterns appear as chips
- [ ] Chips are sorted by last used timestamp
- [ ] Tapping chip re-applies pattern

### Schedule Quick Input
- [ ] Natural language parsing works for common phrases
- [ ] Voice input activates speech-to-text
- [ ] Schedule is created and appears in weekly view
- [ ] Error handling for unparseable requests

### Settings
- [ ] Sections are grouped by purpose
- [ ] Status summaries show inline (e.g., "2 controllers online")
- [ ] Advanced settings collapsed in Guided Mode
- [ ] Video tutorial links work

## Performance Considerations

1. **Favorites Stream**: Limits to 5 items, indexed on `usageCount`
2. **Recent Patterns Stream**: Limits to 5 items, indexed on `lastUsed`
3. **Help Dialogs**: Lightweight, no images or network calls
4. **Guided Mode Check**: Simple boolean provider, negligible overhead

## Future Enhancements

1. **Favorites Management Screen**: Allow manual reordering, deletion
2. **Pattern Collections**: Group favorites into custom collections (e.g., "Holiday", "Daily")
3. **Smart Suggestions**: "Based on your usage, try these patterns"
4. **Onboarding Tour**: First-time user guide highlighting Guided Mode features
5. **Accessibility**: Voice navigation for entire app (not just Lumina chat)

## Migration Path for Existing Users

When rolling out Guided Mode:
1. Default ON for new users
2. Show one-time prompt for existing users: "Try Guided Mode for easier navigation"
3. Allow dismissal (don't force)
4. Track adoption rate via analytics

## Analytics to Track

- Guided Mode adoption rate
- Most-favorited patterns
- Quick Schedule usage vs manual editor
- Help button tap rate (which features need more clarification)
- Voice prompt hint tap rate (indicates interest in voice control)
