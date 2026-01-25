import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/analytics/analytics_providers.dart';

class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key});

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  final _displayNameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final Set<String> _selectedCategoryIds = <String>{};
  final List<String> _interestTags = <String>[];
  bool _allowSuggestions = true;
  bool _analyticsEnabled = true;

  User? _firebaseUser;

  @override
  void initState() {
    super.initState();
    // Initialize from auth state if possible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firebaseUser = ref.read(authManagerProvider).currentUser;
      final u = _firebaseUser;
      if (u != null) {
        _displayNameCtrl.text = u.displayName ?? '';
      }
    });
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _locationCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromModel(UserModel model) {
    _displayNameCtrl.text = model.displayName;
    _locationCtrl.text = model.location ?? '';
    _selectedCategoryIds
      ..clear()
      ..addAll(model.preferredCategoryIds);
    _interestTags
      ..clear()
      ..addAll(model.interestTags);
    _allowSuggestions = model.allowSuggestions;
    _analyticsEnabled = model.analyticsEnabled;
  }

  Future<void> _onSave(User? firebaseUser, UserModel? existing) async {
    if (firebaseUser == null) return;
    final svc = ref.read(userServiceProvider);
    final now = DateTime.now();
    final model = (existing ?? UserModel(
      id: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      displayName: _displayNameCtrl.text.trim().isEmpty ? (firebaseUser.displayName ?? '') : _displayNameCtrl.text.trim(),
      ownerId: firebaseUser.uid,
      createdAt: now,
      updatedAt: now,
    )).copyWith(
      displayName: _displayNameCtrl.text.trim().isEmpty ? null : _displayNameCtrl.text.trim(),
      location: _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
      timeZone: DateTime.now().timeZoneName,
      preferredCategoryIds: _selectedCategoryIds.toList(),
      interestTags: _interestTags,
      allowSuggestions: _allowSuggestions,
      analyticsEnabled: _analyticsEnabled,
      updatedAt: now,
    );
    try {
      if (existing == null) {
        await svc.createUser(model);
      } else {
        await svc.updateUser(model);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
      context.pop();
    } catch (e) {
      debugPrint('Failed to save profile: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final categoriesAsync = ref.watch(patternCategoriesProvider);
    final profileAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      appBar: const GlassAppBar(title: Text('My Profile')),
      body: authState.when(
        data: (firebaseUser) {
          if (firebaseUser == null) {
            return _SignedOutState(onBack: () => context.pop());
          }

          return profileAsync.when(
            data: (model) {
              // hydrate local state on first read
              if (model != null && _displayNameCtrl.text.isEmpty && _locationCtrl.text.isEmpty && _selectedCategoryIds.isEmpty && _interestTags.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _hydrateFromModel(model);
                });
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _Header(email: firebaseUser.email ?? ''),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Basic', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        TextField(controller: _displayNameCtrl, decoration: const InputDecoration(labelText: 'Display name', prefixIcon: Icon(Icons.person_outline))),
                        const SizedBox(height: 12),
                        TextField(controller: _locationCtrl, decoration: const InputDecoration(labelText: 'Location (City, Country)', prefixIcon: Icon(Icons.location_on_outlined))),
                        const SizedBox(height: 12),
                        Row(children: [
                          Switch(value: _allowSuggestions, onChanged: (v) => setState(() => _allowSuggestions = v), activeColor: NexGenPalette.cyan),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Allow seasonal & event-based suggestions', style: Theme.of(context).textTheme.bodyMedium)),
                        ]),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.analytics_outlined, color: NexGenPalette.cyan),
                          const SizedBox(width: 8),
                          Text('Privacy & Analytics', style: Theme.of(context).textTheme.titleMedium),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Switch(
                            value: _analyticsEnabled,
                            onChanged: (v) => setState(() => _analyticsEnabled = v),
                            activeColor: NexGenPalette.cyan
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Contribute to Pattern Trends', style: Theme.of(context).textTheme.bodyMedium),
                                const SizedBox(height: 4),
                                Text(
                                  'Help improve Lumina by sharing anonymized usage data to identify trending patterns and areas for improvement',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: NexGenPalette.cyan.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.security, size: 16, color: NexGenPalette.cyan),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Your identity remains private. All data is anonymized and used only to improve pattern recommendations.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Pattern Preferences', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('Preferred Categories', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        categoriesAsync.when(
                          data: (cats) {
                            return Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final c in cats)
                                FilterChip(
                                  selected: _selectedCategoryIds.contains(c.id),
                                  onSelected: (sel) => setState(() {
                                    if (sel) {
                                      _selectedCategoryIds.add(c.id);
                                    } else {
                                      _selectedCategoryIds.remove(c.id);
                                    }
                                  }),
                                  label: Text(c.name),
                                  selectedColor: NexGenPalette.cyan.withValues(alpha: 0.18),
                                  checkmarkColor: NexGenPalette.cyan,
                                  side: BorderSide(color: NexGenPalette.line),
                                ),
                            ]);
                          },
                          error: (e, st) => Text('Failed to load categories: $e'),
                          loading: () => const LinearProgressIndicator(minHeight: 2),
                        ),
                        const SizedBox(height: 12),
                        Text('Interests & Tags (teams, holidays, etc.)', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final t in _interestTags)
                            InputChip(
                              label: Text(t),
                              onDeleted: () => setState(() => _interestTags.remove(t)),
                              deleteIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: TextField(controller: _tagCtrl, decoration: const InputDecoration(labelText: 'Add tag', prefixIcon: Icon(Icons.add_circle_outline)) , onSubmitted: (v) {
                            final t = v.trim();
                            if (t.isEmpty) return;
                            setState(() { _interestTags.add(t); _tagCtrl.clear(); });
                          })),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: () {
                            final t = _tagCtrl.text.trim();
                            if (t.isEmpty) return;
                            setState(() { _interestTags.add(t); _tagCtrl.clear(); });
                          }, child: const Text('Add')),
                        ]),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () => _onSave(firebaseUser, profileAsync.valueOrNull),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save Profile'),
                    ),
                  ),
                ],
              );
            },
            error: (e, st) => Center(child: Text('Error: $e')),
            loading: () => const Center(child: CircularProgressIndicator()),
          );
        },
        error: (e, st) => Center(child: Text('Auth error: $e')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String email;
  const _Header({required this.email});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.badge_outlined, color: NexGenPalette.violet),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Registered Email', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(email, style: Theme.of(context).textTheme.bodyLarge),
          ])),
        ]),
      ),
    );
  }
}

class _SignedOutState extends StatelessWidget {
  final VoidCallback onBack;
  const _SignedOutState({required this.onBack});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.person_off_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 40),
          const SizedBox(height: 12),
          Text('Sign in required', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Please sign in to create or edit your profile.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: onBack, icon: const Icon(Icons.arrow_back), label: const Text('Back')),
        ]),
      ),
    );
  }
}
