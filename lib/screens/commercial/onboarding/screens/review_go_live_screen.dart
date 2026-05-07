import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/commercial/brand/brand_design_generator.dart';
import 'package:nexgen_command/models/commercial/brand_signature.dart';
import 'package:nexgen_command/models/commercial/business_hours.dart';
import 'package:nexgen_command/models/commercial/channel_role.dart';
import 'package:nexgen_command/models/commercial/commercial_brand_profile.dart';
import 'package:nexgen_command/screens/commercial/commercial_mode_providers.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';

class ReviewGoLiveScreen extends ConsumerStatefulWidget {
  const ReviewGoLiveScreen({super.key, required this.onGoToStep});
  final void Function(int step) onGoToStep;

  @override
  ConsumerState<ReviewGoLiveScreen> createState() => _ReviewGoLiveScreenState();
}

class _ReviewGoLiveScreenState extends ConsumerState<ReviewGoLiveScreen> {
  bool _weekPreviewExpanded = false;
  bool _isActivating = false;

  Future<void> _goLive() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to activate Commercial Mode'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isActivating = true);
    final draft = ref.read(commercialOnboardingProvider);

    try {
      final uid = user.uid;
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(uid);
      final firestore = FirebaseFirestore.instance;

      // Build a structured commercial_profile map from the wizard draft.
      // Stored on the user doc so the residential→commercial mode switcher
      // and commercialOrgProvider can read settings without re-fetching the
      // whole locations subcollection.
      final commercialProfile = <String, dynamic>{
        'business_type': draft.businessType,
        'business_name': draft.businessName,
        'primary_address': draft.primaryAddress,
        'brand_colors':
            draft.brandColors.map((c) => c.toJson()).toList(),
        // Library tie-back when the customer selected from /brand_library
        // in the enhanced BrandIdentityScreen (Path 1, Part 8). Null
        // when colors were entered manually.
        if (draft.brandLibraryId != null)
          'brand_library_id': draft.brandLibraryId,
        'apply_brand_to_defaults': draft.applyBrandToDefaults,
        'weekly_schedule': draft.weeklySchedule
            .map((day, sched) => MapEntry(day.name, sched.toJson())),
        'pre_open_buffer_minutes': draft.preOpenBufferMinutes,
        'post_close_wind_down_minutes':
            draft.postCloseWindDownMinutes,
        'hours_vary': draft.hoursVary,
        'observe_standard_holidays': draft.observeStandardHolidays,
        'observed_holidays': draft.observedHolidays,
        'channel_configs':
            draft.channelConfigs.map((c) => c.toJson()).toList(),
        'teams': draft.teams.map((t) => t.toJson()).toList(),
        'use_brand_colors_for_alerts': draft.useBrandColorsForAlerts,
        'day_parts': draft.dayParts.map((d) => d.toJson()).toList(),
        'default_ambient_design_id': draft.defaultAmbientDesignId,
        'org_name': draft.orgName,
        'has_multiple_locations': draft.hasMultipleLocations,
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Primary commercial_location doc — minimum required for the route
      // guard to recognise the user as a configured commercial customer.
      final locationDoc = <String, dynamic>{
        'location_id': 'primary',
        'org_id': '',
        'location_name': draft.businessName.isEmpty
            ? 'Primary Location'
            : draft.businessName,
        'address': draft.primaryAddress,
        'lat': 0.0,
        'lng': 0.0,
        'controller_id': '',
        'business_hours_id': '',
        'schedule_id': '',
        'teams_config_id': '',
        'is_using_org_template': false,
        'channel_configs':
            draft.channelConfigs.map((c) => c.toJson()).toList(),
        'managers': [
          {
            'user_id': uid,
            'role': 'corporateAdmin',
            'assigned_at': DateTime.now().toIso8601String(),
          }
        ],
        'created_at': FieldValue.serverTimestamp(),
        'active': true,
      };

      final batch = firestore.batch();
      batch.set(userRef, {
        'profile_type': 'commercial',
        'commercial_mode_enabled': true,
        'commercial_mode_override': true,
        'commercial_profile': commercialProfile,
      }, SetOptions(merge: true));
      batch.set(
        userRef.collection('commercial_locations').doc('primary'),
        locationDoc,
      );
      await batch.commit();

      // Persist the rich brand profile + auto-generate the five canonical
      // brand designs. Done after the batch commit so the user-doc and
      // location-doc writes are atomic; the brand-profile / favorites
      // writes are best-effort — a failure here doesn't undo Commercial
      // Mode activation, the customer can re-run from the Brand tab.
      if (draft.brandColors.isNotEmpty) {
        try {
          final brandProfile = CommercialBrandProfile(
            companyName: draft.businessName.isEmpty
                ? 'Brand'
                : draft.businessName,
            brandLibraryId: draft.brandLibraryId,
            colors: draft.brandColors,
            customized: false,
            signature: const BrandSignature(),
            generatedDesigns: const [],
            createdAt: DateTime.now(),
          );

          final brandJson = brandProfile.toJson();
          // Server-stamp the timestamp on the create.
          brandJson['created_at'] = FieldValue.serverTimestamp();

          await userRef
              .collection('brand_profile')
              .doc('brand')
              .set(brandJson, SetOptions(merge: true));

          // Auto-generate five favorites + write the names list back to
          // the brand_profile doc.
          final gen = ref.read(brandDesignGeneratorProvider);
          await gen.generateBrandDesigns(
              userId: uid, brand: brandProfile);
        } catch (e) {
          debugPrint('ReviewGoLive: brand profile/design persist failed '
              '(non-blocking): $e');
        }
      }

      // Mirror to local prefs so the next app launch reads commercial mode
      // even before Firestore has refreshed.
      await setCommercialModeOverride(true);

      if (!mounted) return;
      setState(() => _isActivating = false);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _SuccessDialog(),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss success dialog
      if (!mounted) return;
      // Phase 3a: route to residential home, consistent with the
      // route-guard change that landed customers on /dashboard. The
      // CommercialOnboardingWizard itself is unreachable from in-app
      // navigation (Item #28) and slated for replacement with a short
      // conversion flow in residential Settings; this update prevents
      // dead code from pointing at the (eventually) retired /commercial
      // shell if/when the wizard is rewired.
      context.go(AppRoutes.dashboard);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActivating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Setup failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(commercialOnboardingProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('Review & Go Live',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: NexGenPalette.textHigh)),
        const SizedBox(height: 16),

        // ── Business Profile ────────────────────────────────────────────
        _SummaryCard(
          title: 'Business Profile',
          onEdit: () => widget.onGoToStep(0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow('Type', draft.businessType.replaceAll('_', ' ')),
              _InfoRow('Name', draft.businessName),
              if (draft.primaryAddress.isNotEmpty)
                _InfoRow('Address', draft.primaryAddress),
            ],
          ),
        ),

        // ── Brand Colors ────────────────────────────────────────────────
        _SummaryCard(
          title: 'Brand Colors',
          onEdit: () => widget.onGoToStep(1),
          child: draft.brandColors.isEmpty
              ? const Text('None set',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13))
              : Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: draft.brandColors.map((c) {
                    final color = _parseHex(c.hexCode);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 16, height: 16,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: NexGenPalette.line),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(c.colorName.isEmpty ? '#${c.hexCode}' : c.colorName,
                            style: const TextStyle(
                                color: NexGenPalette.textHigh, fontSize: 12)),
                        const SizedBox(width: 8),
                      ],
                    );
                  }).toList(),
                ),
        ),

        // ── Hours ───────────────────────────────────────────────────────
        _SummaryCard(
          title: 'Hours',
          onEdit: () => widget.onGoToStep(2),
          child: draft.hoursVary
              ? const Text('Flexible hours',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13))
              : _WeekGlanceMini(schedule: draft.weeklySchedule),
        ),

        // ── Channels ────────────────────────────────────────────────────
        _SummaryCard(
          title: 'Channels',
          onEdit: () => widget.onGoToStep(3),
          child: draft.channelConfigs.isEmpty
              ? const Text('Not configured',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13))
              : Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: draft.channelConfigs.map((c) {
                    return Chip(
                      label: Text(
                        '${c.friendlyName} — ${c.role.displayName}',
                        style: const TextStyle(fontSize: 11, color: NexGenPalette.textHigh),
                      ),
                      backgroundColor: NexGenPalette.gunmetal,
                      side: const BorderSide(color: NexGenPalette.line),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
        ),

        // ── Your Teams ──────────────────────────────────────────────────
        _SummaryCard(
          title: 'Your Teams',
          onEdit: () => widget.onGoToStep(4),
          child: draft.teams.isEmpty
              ? const Text('None',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13))
              : Column(
                  children: draft.teams.map((t) {
                    final primary = _parseHex(t.primaryColor);
                    final secondary = _parseHex(t.secondaryColor);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 2),
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(color: secondary, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(t.teamName,
                              style: const TextStyle(
                                  color: NexGenPalette.textHigh, fontSize: 13)),
                          const Spacer(),
                          Text('#${t.priorityRank}',
                              style: const TextStyle(
                                  color: NexGenPalette.textMedium, fontSize: 12)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),

        // ── Day-Parts ───────────────────────────────────────────────────
        _SummaryCard(
          title: 'Day-Parts',
          onEdit: () => widget.onGoToStep(5),
          child: draft.dayParts.isEmpty
              ? const Text('None',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13))
              : SizedBox(
                  height: 32,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: draft.dayParts.length,
                    itemBuilder: (_, i) {
                      final colors = [
                        const Color(0xFF2196F3),
                        const Color(0xFF4CAF50),
                        const Color(0xFFFFC107),
                        const Color(0xFFFF5722),
                        const Color(0xFF9C27B0),
                        const Color(0xFF00BCD4),
                        const Color(0xFFE91E63),
                        const Color(0xFF607D8B),
                      ];
                      return Container(
                        margin: const EdgeInsets.only(right: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors[i % colors.length].withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: colors[i % colors.length].withValues(alpha: 0.3)),
                        ),
                        child: Center(
                          child: Text(draft.dayParts[i].name,
                              style: const TextStyle(
                                  color: NexGenPalette.textHigh, fontSize: 10)),
                        ),
                      );
                    },
                  ),
                ),
        ),

        // ── Preview Your Week ───────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _weekPreviewExpanded = !_weekPreviewExpanded),
          child: Container(
            margin: const EdgeInsets.only(top: 4, bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_view_week,
                    size: 18, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Preview Your Week',
                      style: TextStyle(color: NexGenPalette.textHigh, fontSize: 14)),
                ),
                Icon(
                  _weekPreviewExpanded ? Icons.expand_less : Icons.expand_more,
                  color: NexGenPalette.textMedium,
                ),
              ],
            ),
          ),
        ),
        if (_weekPreviewExpanded)
          _WeekPreview(draft: draft),

        const SizedBox(height: 8),

        // ── Pro Tier Banner ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: NexGenPalette.cyan, width: 3)),
          ),
          child: Text(
            'Multi-location management and advanced commercial features are '
            'currently included in Lumina at no additional cost. A Lumina '
            'Commercial subscription is coming \u2014 users who set up now '
            'will be grandfathered.',
            style: TextStyle(color: NexGenPalette.textHigh.withValues(alpha: 0.85), fontSize: 13),
          ),
        ),

        const SizedBox(height: 24),

        // ── Go Live button ──────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isActivating ? null : _goLive,
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              disabledBackgroundColor: NexGenPalette.cyan.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isActivating
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Activate Commercial Mode',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card wrapper
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.onEdit, required this.child});
  final String title;
  final VoidCallback onEdit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: NexGenPalette.textHigh,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ),
              GestureDetector(
                onTap: onEdit,
                child: const Text('Edit',
                    style: TextStyle(color: NexGenPalette.cyan, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info row
// ---------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Week-at-a-glance mini strip
// ---------------------------------------------------------------------------

class _WeekGlanceMini extends StatelessWidget {
  const _WeekGlanceMini({required this.schedule});
  final Map<DayOfWeek, DaySchedule> schedule;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: DayOfWeek.values.map((d) {
        final open = schedule[d]?.isOpen ?? false;
        return Column(
          children: [
            Container(
              width: 30, height: 5,
              decoration: BoxDecoration(
                color: open ? NexGenPalette.cyan : NexGenPalette.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 3),
            Text(d.shortName,
                style: TextStyle(
                    color: open ? NexGenPalette.textHigh : NexGenPalette.textMedium,
                    fontSize: 10)),
          ],
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Week preview
// ---------------------------------------------------------------------------

class _WeekPreview extends StatelessWidget {
  const _WeekPreview({required this.draft});
  final CommercialOnboardingDraft draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: DayOfWeek.values.map((day) {
          final sched = draft.weeklySchedule[day];
          final open = sched?.isOpen ?? false;
          final dayParts = draft.dayParts.where((p) {
            if (p.daysOfWeek.isEmpty) return true;
            return p.daysOfWeek.contains(day);
          }).toList();

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(day.shortName,
                      style: TextStyle(
                          color: open ? NexGenPalette.textHigh : NexGenPalette.textMedium,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                if (!open)
                  const Text('Closed',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11))
                else
                  Expanded(
                    child: SizedBox(
                      height: 18,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: dayParts.length,
                        itemBuilder: (_, i) {
                          final colors = [
                            const Color(0xFF2196F3), const Color(0xFF4CAF50),
                            const Color(0xFFFFC107), const Color(0xFFFF5722),
                            const Color(0xFF9C27B0), const Color(0xFF00BCD4),
                          ];
                          return Container(
                            margin: const EdgeInsets.only(right: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: colors[i % colors.length].withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Center(
                              child: Text(dayParts[i].name,
                                  style: const TextStyle(
                                      color: NexGenPalette.textHigh, fontSize: 9)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Success dialog
// ---------------------------------------------------------------------------

class _SuccessDialog extends StatelessWidget {
  const _SuccessDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NexGenPalette.gunmetal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NexGenPalette.cyan.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.check_circle, size: 48, color: NexGenPalette.cyan),
            ),
            const SizedBox(height: 20),
            const Text(
              'Commercial Mode Active!',
              style: TextStyle(
                color: NexGenPalette.textHigh,
                fontSize: 20,
                fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your schedule is now running on autopilot.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Color _parseHex(String hex) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length == 6) {
    final v = int.tryParse('FF$cleaned', radix: 16);
    if (v != null) return Color(v);
  }
  return Colors.grey;
}
