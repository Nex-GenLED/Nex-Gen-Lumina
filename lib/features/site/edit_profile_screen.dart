import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/schedule/geocoding_service.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/widgets/house_photo_uploader.dart';
import 'package:nexgen_command/widgets/team_autocomplete.dart';
import 'package:nexgen_command/widgets/address_autocomplete.dart';
import 'package:nexgen_command/utils/sun_utils.dart';
import 'package:nexgen_command/models/autopilot_profile.dart';
import 'package:nexgen_command/models/custom_holiday.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _saving = false;
  bool _hydrated = false; // Prevent re-hydrating on every build

  // Lifestyle fields
  final _teamInputCtrl = TextEditingController();
  List<String> _sportsTeams = [];
  Set<String> _favoriteHolidays = {};
  double _vibeLevel = 0.5; // 0 subtle .. 1 bold

  // HOA Guardian fields
  bool _hoaCompliance = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 23, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 6, minute: 0);
  int _autonomyLevel = 1; // 0..2
  // Privacy toggles
  bool _communityPatternSharing = false; // opt-in
  bool _allowPersonalization = true; // mirrors allowSuggestions

  // Background sun times
  Timer? _debounce;
  String? _sunInfo;

  // Property architecture fields
  String? _builder;
  String? _floorPlan;
  int? _buildYear;

  // Seasonal Color Windows
  List<SeasonalColorWindow> _seasonalWindows = [];

  // Autopilot settings
  bool _autopilotEnabled = false;
  int _changeToleranceLevel = 2; // 0-5 scale
  List<String> _preferredEffectStyles = ['static', 'animated'];
  List<CustomHoliday> _customHolidays = [];
  List<String> _sportsTeamPriority = [];
  bool _weeklySchedulePreviewEnabled = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _teamInputCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _hydrate(UserModel? m, String? authDisplayName) {
    // Only hydrate once to prevent overwriting user changes on rebuild
    if (_hydrated) return;

    if (m == null && (_nameCtrl.text.isEmpty)) {
      _nameCtrl.text = (authDisplayName ?? '').trim();
      return;
    }
    if (m != null) {
      _hydrated = true; // Mark as hydrated once we have a valid model
      if (_nameCtrl.text.isEmpty) _nameCtrl.text = m.displayName;
      if (_emailCtrl.text.isEmpty) _emailCtrl.text = m.email;
      if (_phoneCtrl.text.isEmpty) _phoneCtrl.text = m.phoneNumber ?? '';
      if (_addressCtrl.text.isEmpty) _addressCtrl.text = m.address ?? (m.location ?? '');
      if (_sportsTeams.isEmpty && m.sportsTeams.isNotEmpty) _sportsTeams = List.from(m.sportsTeams);
      if (_favoriteHolidays.isEmpty && m.favoriteHolidays.isNotEmpty) _favoriteHolidays = m.favoriteHolidays.toSet();
      if (m.vibeLevel != null) _vibeLevel = m.vibeLevel!.clamp(0.0, 1.0);
      if (m.hoaComplianceEnabled != null) _hoaCompliance = m.hoaComplianceEnabled!;
      if (m.quietHoursStartMinutes != null) _quietStart = _minutesToTimeOfDay(m.quietHoursStartMinutes!);
      if (m.quietHoursEndMinutes != null) _quietEnd = _minutesToTimeOfDay(m.quietHoursEndMinutes!);
      if (m.autonomyLevel != null) _autonomyLevel = m.autonomyLevel!.clamp(0, 2);
      _communityPatternSharing = m.communityPatternSharing;
      _allowPersonalization = m.allowSuggestions;
      // Architecture
      _builder ??= m.builder;
      _floorPlan ??= m.floorPlan;
      _buildYear ??= m.buildYear;
      if (_seasonalWindows.isEmpty && m.seasonalColorWindows.isNotEmpty) {
        _seasonalWindows = List.from(m.seasonalColorWindows);
      }
      // Autopilot settings
      _autopilotEnabled = m.autopilotEnabled;
      _changeToleranceLevel = m.changeToleranceLevel;
      if (m.preferredEffectStyles.isNotEmpty) _preferredEffectStyles = List.from(m.preferredEffectStyles);
      if (_customHolidays.isEmpty && m.customHolidays.isNotEmpty) _customHolidays = List.from(m.customHolidays);
      if (_sportsTeamPriority.isEmpty && m.sportsTeamPriority.isNotEmpty) {
        _sportsTeamPriority = List.from(m.sportsTeamPriority);
      } else if (_sportsTeamPriority.isEmpty && m.sportsTeams.isNotEmpty) {
        // Initialize priority from teams list if not set
        _sportsTeamPriority = List.from(m.sportsTeams);
      }
      _weeklySchedulePreviewEnabled = m.weeklySchedulePreviewEnabled;
    }
  }

  Future<void> _onSave() async {
    final authAsync = ref.read(authStateProvider);
    final authUser = authAsync.value;
    if (authUser == null) return;
    final profileAsync = ref.read(currentUserProfileProvider);
    final existing = profileAsync.value;
    final svc = ref.read(userServiceProvider);
    final now = DateTime.now();
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final addressChanged = address.isNotEmpty && address != (existing?.address ?? '');

    setState(() => _saving = true);
    try {
      UserModel base = (existing ?? UserModel(
        id: authUser.uid,
        email: authUser.email ?? _emailCtrl.text.trim(),
        displayName: name.isEmpty ? (authUser.displayName ?? '') : name,
        ownerId: authUser.uid,
        createdAt: now,
        updatedAt: now,
      ));
      base = base.copyWith(
        displayName: name.isEmpty ? null : name,
        phoneNumber: phone.isEmpty ? null : phone,
        address: address.isEmpty ? null : address,
        location: address.isEmpty ? base.location : address, // keep location aligned with address
        timeZone: DateTime.now().timeZoneName,
        updatedAt: now,
        sportsTeams: _sportsTeams,
        favoriteHolidays: _favoriteHolidays.toList(),
        vibeLevel: _vibeLevel,
        hoaComplianceEnabled: _hoaCompliance,
        quietHoursStartMinutes: _timeOfDayToMinutes(_quietStart),
        quietHoursEndMinutes: _timeOfDayToMinutes(_quietEnd),
        autonomyLevel: _autonomyLevel,
        allowSuggestions: _allowPersonalization,
        communityPatternSharing: _communityPatternSharing,
        builder: _builder,
        floorPlan: _floorPlan,
        buildYear: _buildYear,
        seasonalColorWindows: _seasonalWindows,
        // Autopilot settings
        autopilotEnabled: _autopilotEnabled,
        changeToleranceLevel: _changeToleranceLevel,
        preferredEffectStyles: _preferredEffectStyles,
        customHolidays: _customHolidays,
        sportsTeamPriority: _sportsTeamPriority,
        weeklySchedulePreviewEnabled: _weeklySchedulePreviewEnabled,
      );

      if (existing == null) {
        await svc.createUser(base);
      } else {
        await svc.updateUser(base);
      }

      // If address changed, geocode and push to WLED; also compute sun times
      if (addressChanged) {
        final geocoder = ref.read(geocodingServiceProvider);
        final result = await geocoder.geocode(address);
        if (result != null) {
          // Update coordinates in profile
          final withGeo = base.copyWith(latitude: result.lat, longitude: result.lon, updatedAt: DateTime.now());
          await svc.updateUser(withGeo);

          // Push to WLED config so solar timers use the new location
          final repo = ref.read(wledRepositoryProvider);
          if (repo != null) {
            final ok = await repo.applyConfig({'loc': {'lat': result.lat, 'lon': result.lon}});
            if (!ok) debugPrint('EditProfile: WLED location push failed');
          } else {
            debugPrint('EditProfile: No WLED device selected; skipped location push');
          }

          // Background compute of today's sunset and tomorrow's sunrise
          final nowLocal = DateTime.now();
          final sunset = SunUtils.sunsetLocal(result.lat, result.lon, nowLocal);
          final sunrise = SunUtils.sunriseLocal(result.lat, result.lon, nowLocal.add(const Duration(days: 1)));
          debugPrint('Sun calc for new address: sunset=${sunset?.toLocal()} sunrise=${sunrise?.toLocal()}');
        } else {
          debugPrint('EditProfile: Geocoding failed for address');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Profile Updated & Solar Sync Complete.'),
        backgroundColor: Color(0xFF2ECC71), // green
      ));
    } catch (e) {
      debugPrint('EditProfile: Save failed $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Save failed: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Helpers
  int _timeOfDayToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;
  TimeOfDay _minutesToTimeOfDay(int m) => TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
  String _formatTimeOfDay(TimeOfDay t) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    final local = TimeOfDay.fromDateTime(dt);
    return local.format(context);
  }

  void _onAddressChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      final addr = value.trim();
      if (addr.isEmpty) {
        setState(() => _sunInfo = null);
        return;
      }
      try {
        final geocoder = ref.read(geocodingServiceProvider);
        final res = await geocoder.geocode(addr);
        if (res == null) return;
        _updateSunInfo(res.lat, res.lon);
      } catch (e) {
        debugPrint('EditProfile: sun calc failed $e');
      }
    });
  }

  void _onAddressSelected(AddressSuggestion suggestion) {
    // Immediately compute sun times since we already have coordinates
    _debounce?.cancel();
    _updateSunInfo(suggestion.lat, suggestion.lon);
  }

  void _updateSunInfo(double lat, double lon) {
    final sunset = SunUtils.sunsetLocal(lat, lon, DateTime.now());
    final sunrise = SunUtils.sunriseLocal(lat, lon, DateTime.now().add(const Duration(days: 1)));
    String info = '';
    if (sunset != null) info += 'Sunset: ${TimeOfDay.fromDateTime(sunset).format(context)}';
    if (sunrise != null) info += (info.isEmpty ? '' : '  •  ') + 'Sunrise: ${TimeOfDay.fromDateTime(sunrise).format(context)}';
    if (mounted) setState(() => _sunInfo = info.isEmpty ? null : info);
  }

  Future<void> _showAddSeasonalWindowSheet() async {
    final months = const [
      'January','February','March','April','May','June','July','August','September','October','November','December'
    ];
    int startMonth = 10; // October default
    int startDay = 1;
    int endMonth = 1; // January default
    int endDay = 5;

    int daysIn(int month) {
      switch (month) {
        case 2:
          return 29; // allow leap-day; yearless recurring
        case 4:
        case 6:
        case 9:
        case 11:
          return 30;
        default:
          return 31;
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final startDays = [for (int d = 1; d <= daysIn(startMonth); d++) d];
            final endDays = [for (int d = 1; d <= daysIn(endMonth); d++) d];
            startDay = startDay.clamp(1, startDays.last);
            endDay = endDay.clamp(1, endDays.last);
            return Padding(
              padding: EdgeInsets.only(
                left: 16, right: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, top: 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add Seasonal Color Window', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('These dates repeat every year. Colors allowed within ranges; white outside.', style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: startMonth,
                          items: [for (int m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(months[m - 1]))],
                          onChanged: (v) => setSheet(() => startMonth = v ?? startMonth),
                          decoration: const InputDecoration(labelText: 'Start Month', prefixIcon: Icon(Icons.event_outlined)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: startDay,
                          items: [for (final d in startDays) DropdownMenuItem(value: d, child: Text(d.toString()))],
                          onChanged: (v) => setSheet(() => startDay = v ?? startDay),
                          decoration: const InputDecoration(labelText: 'Start Day'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: endMonth,
                          items: [for (int m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(months[m - 1]))],
                          onChanged: (v) => setSheet(() => endMonth = v ?? endMonth),
                          decoration: const InputDecoration(labelText: 'End Month', prefixIcon: Icon(Icons.event)) ,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: endDay,
                          items: [for (final d in endDays) DropdownMenuItem(value: d, child: Text(d.toString()))],
                          onChanged: (v) => setSheet(() => endDay = v ?? endDay),
                          decoration: const InputDecoration(labelText: 'End Day'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            setState(() {
                              _seasonalWindows = [
                                ..._seasonalWindows,
                                SeasonalColorWindow(
                                  startMonth: startMonth,
                                  startDay: startDay,
                                  endMonth: endMonth,
                                  endDay: endDay,
                                ),
                              ];
                            });
                            Navigator.of(ctx).pop();
                          },
                          label: const Text('Add Window'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _monthName(int m) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    if (m < 1 || m > 12) return '?';
    return months[m - 1];
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final profile = ref.watch(currentUserProfileProvider);
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Lumina Lifestyle Profile')),
      body: auth.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Sign in required'));
          }
          final model = profile.valueOrNull;
          _hydrate(model, user.displayName);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              // House Photo Section for AR Preview
              _HousePhotoCard(),
              const SizedBox(height: 16),
              _IdentityCard(
                nameCtrl: _nameCtrl,
                emailCtrl: _emailCtrl..text = (model?.email ?? user.email ?? _emailCtrl.text),
                phoneCtrl: _phoneCtrl,
                addressCtrl: _addressCtrl,
                onAddressChanged: _onAddressChanged,
                onAddressSelected: _onAddressSelected,
                sunInfo: _sunInfo,
              ),
              const SizedBox(height: 16),
              _ArchitectureCard(
                builderValue: _builder,
                onBuilderChanged: (v) => setState(() {
                  _builder = v;
                  // Reset floor plan if builder changes
                  _floorPlan = null;
                }),
                floorPlanValue: _floorPlan,
                onFloorPlanChanged: (v) => setState(() => _floorPlan = v),
                buildYearValue: _buildYear,
                onBuildYearChanged: (v) => setState(() => _buildYear = v),
              ),
              const SizedBox(height: 16),
              _InterestsCard(
                teamInputCtrl: _teamInputCtrl,
                teams: _sportsTeams,
                onAddTeam: (t) => setState(() { if (t.isNotEmpty && !_sportsTeams.contains(t)) _sportsTeams = [..._sportsTeams, t]; _teamInputCtrl.clear(); }),
                onRemoveTeam: (t) => setState(() => _sportsTeams = _sportsTeams.where((e) => e != t).toList()),
                favoriteHolidays: _favoriteHolidays,
                onToggleHoliday: (h) => setState(() {
                  if (_favoriteHolidays.contains(h)) { _favoriteHolidays.remove(h); } else { _favoriteHolidays.add(h); }
                }),
                vibeLevel: _vibeLevel,
                onVibeChanged: (v) => setState(() => _vibeLevel = v),
              ),
              const SizedBox(height: 16),
              _HoaGuardianCard(
                hoaCompliance: _hoaCompliance,
                onHoaChanged: (v) => setState(() => _hoaCompliance = v),
                quietStart: _quietStart,
                quietEnd: _quietEnd,
                onPickStart: () async {
                  final t = await showTimePicker(context: context, initialTime: _quietStart);
                  if (t != null) setState(() => _quietStart = t);
                },
                onPickEnd: () async {
                  final t = await showTimePicker(context: context, initialTime: _quietEnd);
                  if (t != null) setState(() => _quietEnd = t);
                },
                timeFormatter: _formatTimeOfDay,
                seasonalWindows: _seasonalWindows,
                onAddWindow: _showAddSeasonalWindowSheet,
                onRemoveWindow: (i) => setState(() => _seasonalWindows.removeAt(i)),
                windowFormatter: (w) => '${_monthName(w.startMonth)} ${w.startDay} - ${_monthName(w.endMonth)} ${w.endDay}',
              ),
              const SizedBox(height: 16),
              _PrivacyIntelligenceCard(
                autonomyLevel: _autonomyLevel,
                onAutonomyChanged: (v) => setState(() => _autonomyLevel = v),
                communityPatternSharing: _communityPatternSharing,
                onCommunityChanged: (v) => setState(() => _communityPatternSharing = v),
                allowPersonalization: _allowPersonalization,
                onAllowPersonalizationChanged: (v) => setState(() => _allowPersonalization = v),
              ),
              const SizedBox(height: 16),
              _AutopilotCard(
                enabled: _autopilotEnabled,
                onEnabledChanged: (v) => setState(() => _autopilotEnabled = v),
                changeToleranceLevel: _changeToleranceLevel,
                onToleranceChanged: (v) => setState(() => _changeToleranceLevel = v),
                preferredEffectStyles: _preferredEffectStyles,
                onEffectStylesChanged: (v) => setState(() => _preferredEffectStyles = v),
                customHolidays: _customHolidays,
                onAddHoliday: (h) => setState(() => _customHolidays = [..._customHolidays, h]),
                onRemoveHoliday: (id) => setState(() => _customHolidays = _customHolidays.where((h) => h.id != id).toList()),
                sportsTeams: _sportsTeams,
                sportsTeamPriority: _sportsTeamPriority,
                onTeamPriorityChanged: (v) => setState(() => _sportsTeamPriority = v),
                weeklyPreviewEnabled: _weeklySchedulePreviewEnabled,
                onWeeklyPreviewChanged: (v) => setState(() => _weeklySchedulePreviewEnabled = v),
              ),
            ],
          );
        },
        error: (e, st) => Center(child: Text('Auth error: $e')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _onSave,
        icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
        label: Text(_saving ? 'Saving…' : 'Update Profile'),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool initiallyExpanded;
  final String? subtitle;
  final Widget? leading;
  const _SectionCard({required this.title, required this.child, this.initiallyExpanded = true, this.subtitle, this.leading});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: leading,
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
        subtitle: subtitle == null ? null : Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [child],
      ),
    );
  }
}

class _IdentityCard extends ConsumerWidget {
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController addressCtrl;
  final void Function(String) onAddressChanged;
  final void Function(AddressSuggestion)? onAddressSelected;
  final String? sunInfo;
  const _IdentityCard({required this.nameCtrl, required this.emailCtrl, required this.phoneCtrl, required this.addressCtrl, required this.onAddressChanged, this.onAddressSelected, this.sunInfo});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SectionCard(
      title: 'Identity',
      child: Column(
        children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emailCtrl,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtrl,
            decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined)),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          AddressAutocomplete(
            controller: addressCtrl,
            labelText: 'Home Address',
            hintText: 'Start typing your address...',
            maxLines: 2,
            onChanged: onAddressChanged,
            onAddressSelected: onAddressSelected,
          ),
          if (sunInfo != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(sunInfo!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.secondary)),
            )
          ],
        ],
      ),
    );
  }
}

class _InterestsCard extends StatelessWidget {
  final TextEditingController teamInputCtrl;
  final List<String> teams;
  final void Function(String) onAddTeam;
  final void Function(String) onRemoveTeam;
  final Set<String> favoriteHolidays;
  final void Function(String) onToggleHoliday;
  final double vibeLevel;
  final ValueChanged<double> onVibeChanged;
  const _InterestsCard({super.key, required this.teamInputCtrl, required this.teams, required this.onAddTeam, required this.onRemoveTeam, required this.favoriteHolidays, required this.onToggleHoliday, required this.vibeLevel, required this.onVibeChanged});

  static const _holidays = <String>[
    'Christmas','Halloween','Hanukkah','July 4th','Valentine\'s','New Year\'s','Easter','Thanksgiving','Diwali'
  ];

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Interests & Fandom',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Which teams do you support?', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 4),
          Text(
            'Type to search NFL, NBA, MLB, NHL, MLS, and college teams',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: NexGenPalette.textMedium),
          ),
          const SizedBox(height: 12),
          TeamSelector(
            controller: teamInputCtrl,
            selectedTeams: teams,
            onAddTeam: onAddTeam,
            onRemoveTeam: onRemoveTeam,
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Which holidays do you celebrate?', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in _holidays)
                FilterChip(
                  label: Text(h),
                  selected: favoriteHolidays.contains(h),
                  onSelected: (_) => onToggleHoliday(h),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Preferred Lighting Style?', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Subtle/Classy', style: Theme.of(context).textTheme.labelSmall),
              Expanded(
                child: Slider(
                  value: vibeLevel,
                  onChanged: onVibeChanged,
                ),
              ),
              Text('Bold/Energetic', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _HoaGuardianCard extends StatelessWidget {
  final bool hoaCompliance;
  final ValueChanged<bool> onHoaChanged;
  final TimeOfDay quietStart;
  final TimeOfDay quietEnd;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final String Function(TimeOfDay) timeFormatter;
  // Seasonal color windows
  final List<SeasonalColorWindow> seasonalWindows;
  final VoidCallback onAddWindow;
  final void Function(int index) onRemoveWindow;
  final String Function(SeasonalColorWindow) windowFormatter;
  const _HoaGuardianCard({super.key, required this.hoaCompliance, required this.onHoaChanged, required this.quietStart, required this.quietEnd, required this.onPickStart, required this.onPickEnd, required this.timeFormatter, required this.seasonalWindows, required this.onAddWindow, required this.onRemoveWindow, required this.windowFormatter});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Neighborhood & Rules',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: hoaCompliance,
            onChanged: onHoaChanged,
            title: const Text('Enforce HOA Standards?'),
            subtitle: const Text('If enabled, Lumina will prioritize Architectural White on weeknights and limit colors to Holidays/Weekends.'),
          ),
          const SizedBox(height: 8),
          Text('Seasonal Color Windows', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Define dates when colored patterns are allowed. Lumina will restrict lighting to Architectural White outside these ranges.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (seasonalWindows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('Colors allowed year-round.', style: Theme.of(context).textTheme.bodyMedium),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < seasonalWindows.length; i++)
                  InputChip(
                    label: Text(windowFormatter(seasonalWindows[i])),
                    onDeleted: () => onRemoveWindow(i),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onAddWindow,
              icon: const Icon(Icons.add, color: Colors.blue),
              label: const Text('+ Add Date Range'),
            ),
          ),
          const SizedBox(height: 8),
          Text('Quiet Hours', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickStart,
                  icon: const Icon(Icons.nights_stay_outlined, color: Colors.blue),
                  label: Text('Start: ${timeFormatter(quietStart)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickEnd,
                  icon: const Icon(Icons.wb_twighlight, color: Colors.blue),
                  label: Text('End: ${timeFormatter(quietEnd)}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyIntelligenceCard extends StatelessWidget {
  const _PrivacyIntelligenceCard({super.key, required this.autonomyLevel, required this.onAutonomyChanged, required this.communityPatternSharing, required this.onCommunityChanged, required this.allowPersonalization, required this.onAllowPersonalizationChanged});
  final int autonomyLevel; // 0..2
  final ValueChanged<int> onAutonomyChanged;
  final bool communityPatternSharing;
  final ValueChanged<bool> onCommunityChanged;
  final bool allowPersonalization;
  final ValueChanged<bool> onAllowPersonalizationChanged;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Lumina Intelligence & Privacy',
      leading: const Icon(Icons.shield_outlined, color: Colors.grey),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lumina Autonomy', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Slider(
                value: autonomyLevel.toDouble(),
                min: 0,
                max: 2,
                divisions: 2,
                label: _labelFor(autonomyLevel),
                onChanged: (v) => onAutonomyChanged(v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Passive (Wait for me)'),
                  Text('Suggest (Ask first)'),
                  Text('Proactive (Just do it)'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: communityPatternSharing,
            onChanged: onCommunityChanged,
            title: const Text('Community Pattern Sharing'),
            subtitle: const Text('Allow Nex-Gen to recommend your custom designs to other users with the same Builder/Floor Plan. (Personal data is never shared).'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: allowPersonalization,
            onChanged: onAllowPersonalizationChanged,
            title: const Text('Allow Personalization'),
            subtitle: const Text('Allow Lumina to use your profile data (Teams, Holidays) to make proactive lighting suggestions.'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Nex-Gen respects your privacy. Your data is stored locally and securely.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  String _labelFor(int v) {
    switch (v) {
      case 0:
        return 'Passive';
      case 1:
        return 'Suggest';
      case 2:
        return 'Proactive';
      default:
        return '';
    }
  }
}

class _ArchitectureCard extends StatelessWidget {
  const _ArchitectureCard({super.key, required this.builderValue, required this.onBuilderChanged, required this.floorPlanValue, required this.onFloorPlanChanged, required this.buildYearValue, required this.onBuildYearChanged});
  final String? builderValue;
  final ValueChanged<String?> onBuilderChanged;
  final String? floorPlanValue;
  final ValueChanged<String?> onFloorPlanChanged;
  final int? buildYearValue;
  final ValueChanged<int?> onBuildYearChanged;

  static const List<String> _builders = ['Summit Homes','Lennar','Pulte','Custom Build'];

  List<String> _plansFor(String? builder) {
    switch (builder) {
      case 'Summit Homes':
        return const ['The Preston','Other'];
      case 'Lennar':
        return const ['Willow II','Other'];
      case 'Pulte':
        return const ['Oakwood Reverse','Other'];
      case 'Custom Build':
        return const ['Other'];
      default:
        return const ['The Preston','Willow II','Oakwood Reverse','Other'];
    }
  }

  List<int> _years() => [for (int y = 2025; y >= 1950; y--) y];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final plans = _plansFor(builderValue);
    final infoText = (builderValue != null && floorPlanValue != null)
        ? "Matches Found: We have 12 saved lighting designs for the '${builderValue!} - ${floorPlanValue!}' model. Lumina can auto-configure your zones."
        : 'Tip: Select your builder and floor plan to check for saved designs.';

    return _SectionCard(
      title: 'Property Architecture',
      subtitle: "Help Lumina optimize your system based on your home's blueprint.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: builderValue,
            items: _builders.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            onChanged: onBuilderChanged,
            decoration: const InputDecoration(labelText: 'Builder', prefixIcon: Icon(Icons.apartment_outlined)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: plans.contains(floorPlanValue) ? floorPlanValue : null,
            items: plans.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: onFloorPlanChanged,
            decoration: const InputDecoration(labelText: 'Floor Plan Model', prefixIcon: Icon(Icons.maps_home_work_outlined)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: buildYearValue,
            items: _years().map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
            onChanged: onBuildYearChanged,
            decoration: const InputDecoration(labelText: 'Year Built', prefixIcon: Icon(Icons.calendar_today_outlined)),
          ),
          const SizedBox(height: 12),
          // Pro Feature: Smart Match note with cyan/blue gradient border
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [NexGenPalette.cyan, NexGenPalette.blue]),
            ),
            padding: const EdgeInsets.all(1.2),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(11),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_circle_outlined, color: NexGenPalette.cyan),
                  const SizedBox(width: 12),
                  Expanded(child: Text(infoText, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// House photo card for AR preview feature
class _HousePhotoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Your Home Photo',
      subtitle: 'Upload a photo to preview lighting effects on your home.',
      leading: const Icon(Icons.home_work_outlined, color: NexGenPalette.cyan),
      child: const HousePhotoUploader(
        previewHeight: 220,
      ),
    );
  }
}

/// Lumina Autopilot card for automatic schedule generation
class _AutopilotCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final int changeToleranceLevel;
  final ValueChanged<int> onToleranceChanged;
  final List<String> preferredEffectStyles;
  final ValueChanged<List<String>> onEffectStylesChanged;
  final List<CustomHoliday> customHolidays;
  final void Function(CustomHoliday) onAddHoliday;
  final void Function(String id) onRemoveHoliday;
  final List<String> sportsTeams;
  final List<String> sportsTeamPriority;
  final ValueChanged<List<String>> onTeamPriorityChanged;
  final bool weeklyPreviewEnabled;
  final ValueChanged<bool> onWeeklyPreviewChanged;

  const _AutopilotCard({
    required this.enabled,
    required this.onEnabledChanged,
    required this.changeToleranceLevel,
    required this.onToleranceChanged,
    required this.preferredEffectStyles,
    required this.onEffectStylesChanged,
    required this.customHolidays,
    required this.onAddHoliday,
    required this.onRemoveHoliday,
    required this.sportsTeams,
    required this.sportsTeamPriority,
    required this.onTeamPriorityChanged,
    required this.weeklyPreviewEnabled,
    required this.onWeeklyPreviewChanged,
  });

  static const _effectStyles = ['static', 'animated', 'chase', 'twinkle', 'rainbow'];

  @override
  Widget build(BuildContext context) {
    final tolerance = ChangeToleranceLevel.fromValue(changeToleranceLevel);

    return _SectionCard(
      title: 'Lumina Autopilot',
      subtitle: 'Set it and forget it. Lumina manages your schedule automatically.',
      leading: const Icon(Icons.smart_toy_outlined, color: NexGenPalette.cyan),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enable/Disable toggle
          SwitchListTile(
            value: enabled,
            onChanged: onEnabledChanged,
            title: const Text('Enable Autopilot'),
            subtitle: const Text('Let Lumina automatically generate and maintain your lighting schedule based on your preferences.'),
            contentPadding: EdgeInsets.zero,
          ),

          // Show detailed settings only when enabled
          if (enabled) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Change Tolerance Slider
            Text('Change Frequency', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'How often should Lumina change your lighting patterns?',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: NexGenPalette.textMedium),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.slow_motion_video, size: 20, color: Colors.grey),
                Expanded(
                  child: Slider(
                    value: changeToleranceLevel.toDouble(),
                    min: 0,
                    max: 4,
                    divisions: 4,
                    label: tolerance.label,
                    onChanged: (v) => onToleranceChanged(v.round()),
                  ),
                ),
                const Icon(Icons.speed, size: 20, color: Colors.grey),
              ],
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: NexGenPalette.cyan.withOpacity(0.3)),
                ),
                child: Text(
                  '${tolerance.label}: ${tolerance.description}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: NexGenPalette.cyan),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Preferred Effect Styles
            Text('Preferred Effect Styles', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in _effectStyles)
                  FilterChip(
                    label: Text(_formatEffectStyle(style)),
                    selected: preferredEffectStyles.contains(style),
                    onSelected: (selected) {
                      if (selected) {
                        onEffectStylesChanged([...preferredEffectStyles, style]);
                      } else if (preferredEffectStyles.length > 1) {
                        onEffectStylesChanged(preferredEffectStyles.where((s) => s != style).toList());
                      }
                    },
                  ),
              ],
            ),

            const SizedBox(height: 20),

            // Custom Holidays Section
            Text('Custom Holidays', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Add personal holidays beyond the US Federal calendar (birthdays, anniversaries, etc.)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: NexGenPalette.textMedium),
            ),
            const SizedBox(height: 8),
            if (customHolidays.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No custom holidays added yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final holiday in customHolidays)
                    InputChip(
                      label: Text('${holiday.name} (${_monthName(holiday.month)} ${holiday.day})'),
                      onDeleted: () => onRemoveHoliday(holiday.id),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showAddHolidaySheet(context),
              icon: const Icon(Icons.add, color: NexGenPalette.cyan),
              label: const Text('+ Add Custom Holiday'),
            ),

            // Team Priority Section (only show if teams are selected)
            if (sportsTeams.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Team Priority', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Drag to reorder. When multiple teams play on the same day, the top team takes priority.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: NexGenPalette.textMedium),
              ),
              const SizedBox(height: 8),
              _TeamPriorityList(
                teams: sportsTeamPriority.isNotEmpty ? sportsTeamPriority : sportsTeams,
                onReorder: onTeamPriorityChanged,
              ),
            ],

            // Weekly Schedule Preview notification toggle
            const SizedBox(height: 20),
            Text('Weekly Schedule Preview', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            SwitchListTile(
              value: weeklyPreviewEnabled,
              onChanged: onWeeklyPreviewChanged,
              title: const Text('Send Weekly Preview'),
              subtitle: const Text('Receive a notification every Sunday evening with your upcoming schedule for the week. Only sent when there are special events (games, holidays).'),
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 16),

            // Info box about autopilot
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(colors: [NexGenPalette.cyan, NexGenPalette.blue]),
              ),
              padding: const EdgeInsets.all(1.2),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(11),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome, color: NexGenPalette.cyan),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Lumina will automatically schedule patterns for your favorite holidays, team game days, and seasonal events while respecting your HOA quiet hours and color restrictions.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatEffectStyle(String style) {
    switch (style) {
      case 'static':
        return 'Static';
      case 'animated':
        return 'Animated';
      case 'chase':
        return 'Chase';
      case 'twinkle':
        return 'Twinkle';
      case 'rainbow':
        return 'Rainbow';
      default:
        return style;
    }
  }

  String _monthName(int m) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    if (m < 1 || m > 12) return '?';
    return months[m - 1];
  }

  void _showAddHolidaySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _AddHolidaySheet(onAdd: onAddHoliday),
    );
  }
}

/// Bottom sheet for adding custom holidays
class _AddHolidaySheet extends StatefulWidget {
  final void Function(CustomHoliday) onAdd;
  const _AddHolidaySheet({required this.onAdd});

  @override
  State<_AddHolidaySheet> createState() => _AddHolidaySheetState();
}

class _AddHolidaySheetState extends State<_AddHolidaySheet> {
  final _nameCtrl = TextEditingController();
  int _month = DateTime.now().month;
  int _day = DateTime.now().day;
  bool _recurring = true;

  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];

  int _daysInMonth(int month) {
    switch (month) {
      case 2: return 29; // Allow leap day for recurring
      case 4: case 6: case 9: case 11: return 30;
      default: return 31;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = [for (int d = 1; d <= _daysInMonth(_month); d++) d];
    _day = _day.clamp(1, days.last);

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Custom Holiday', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Holiday Name',
              hintText: 'e.g., Birthday, Anniversary',
              prefixIcon: Icon(Icons.celebration_outlined),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _month,
                  items: [
                    for (int m = 1; m <= 12; m++)
                      DropdownMenuItem(value: m, child: Text(_months[m - 1]))
                  ],
                  onChanged: (v) => setState(() => _month = v ?? _month),
                  decoration: const InputDecoration(labelText: 'Month', prefixIcon: Icon(Icons.event_outlined)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _day,
                  items: [for (final d in days) DropdownMenuItem(value: d, child: Text(d.toString()))],
                  onChanged: (v) => setState(() => _day = v ?? _day),
                  decoration: const InputDecoration(labelText: 'Day'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _recurring,
            onChanged: (v) => setState(() => _recurring = v),
            title: const Text('Repeats every year'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    final name = _nameCtrl.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a holiday name')),
                      );
                      return;
                    }
                    final holiday = CustomHoliday(
                      id: '${name.toLowerCase().replaceAll(' ', '_')}_${_month}_$_day',
                      name: name,
                      month: _month,
                      day: _day,
                      recurring: _recurring,
                    );
                    widget.onAdd(holiday);
                    Navigator.of(context).pop();
                  },
                  label: const Text('Add Holiday'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reorderable list for team priority
class _TeamPriorityList extends StatelessWidget {
  final List<String> teams;
  final ValueChanged<List<String>> onReorder;

  const _TeamPriorityList({required this.teams, required this.onReorder});

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: teams.length,
      onReorder: (oldIndex, newIndex) {
        final reordered = List<String>.from(teams);
        if (newIndex > oldIndex) newIndex--;
        final item = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, item);
        onReorder(reordered);
      },
      itemBuilder: (context, index) {
        final team = teams[index];
        return ListTile(
          key: ValueKey(team),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_handle, color: Colors.grey),
              const SizedBox(width: 8),
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index == 0 ? NexGenPalette.cyan : Colors.grey.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: index == 0 ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          title: Text(team),
          trailing: index == 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Primary',
                    style: TextStyle(fontSize: 11, color: NexGenPalette.cyan),
                  ),
                )
              : null,
        );
      },
    );
  }
}
