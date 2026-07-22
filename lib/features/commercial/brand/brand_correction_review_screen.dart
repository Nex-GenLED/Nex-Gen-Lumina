import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/models/commercial/brand_color.dart';
import 'package:nexgen_command/models/commercial/brand_correction.dart';
import 'package:nexgen_command/services/commercial/brand_library_providers.dart';

/// Future-once admin-gate check. Reads /users/{uid}.user_role and
/// returns true iff it equals 'admin'. The Firestore rule on
/// /brand_library_corrections.update enforces the same predicate, so
/// this is a UX guard, not a security boundary.
final _isUserRoleAdminProvider = FutureProvider<bool>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!doc.exists) return false;
    final data = doc.data();
    return (data?['user_role'] as String?) == 'admin';
  } catch (_) {
    return false;
  }
});

/// Corporate admin moderation screen for /brand_library_corrections.
///
/// Shows pending corrections newest-first. Approve rewrites the
/// /brand_library entry's colors to the proposed values, marks the
/// correction `applied_to_library: true`, and increments
/// `correction_count` on the library entry. Reject just transitions
/// status to 'rejected' (with an optional reviewer note).
///
/// Both transitions stamp `reviewed_by` and `reviewed_at`.
class BrandCorrectionReviewScreen extends ConsumerWidget {
  const BrandCorrectionReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminCheck = ref.watch(_isUserRoleAdminProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: const Text('Brand Corrections'),
        iconTheme: const IconThemeData(color: NexGenPalette.textHigh),
      ),
      body: adminCheck.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
        error: (e, _) => _UnauthorizedView(
            message: 'Failed to verify admin role: $e'),
        data: (isAdmin) {
          if (!isAdmin) {
            return const _UnauthorizedView(
              message:
                  'This screen is restricted to corporate brand-library administrators.',
            );
          }
          return const _PendingCorrectionsList();
        },
      ),
    );
  }
}

// ─── Unauthorized view ─────────────────────────────────────────────────────

class _UnauthorizedView extends StatelessWidget {
  const _UnauthorizedView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 56, color: NexGenPalette.amber),
            const SizedBox(height: 16),
            Text('Not authorized',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pending list ──────────────────────────────────────────────────────────

class _PendingCorrectionsList extends ConsumerWidget {
  const _PendingCorrectionsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingBrandCorrectionsProvider);

    return pending.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      error: (e, _) => Center(
        child: Text('Failed to load corrections: $e',
            style: Theme.of(context).textTheme.bodyMedium),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 56, color: NexGenPalette.cyan),
                  const SizedBox(height: 16),
                  Text('All caught up',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'No pending brand corrections to review.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                color: NexGenPalette.gunmetal90,
                border: Border(bottom: BorderSide(color: NexGenPalette.line)),
              ),
              child: Text(
                '${list.length} pending correction${list.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) =>
                    _CorrectionCard(correction: list[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Single correction card ────────────────────────────────────────────────

class _CorrectionCard extends ConsumerStatefulWidget {
  const _CorrectionCard({required this.correction});
  final BrandCorrection correction;

  @override
  ConsumerState<_CorrectionCard> createState() => _CorrectionCardState();
}

class _CorrectionCardState extends ConsumerState<_CorrectionCard> {
  bool _isWorking = false;

  Future<void> _approve() async {
    final confirm = await _confirm(
      title: 'Approve correction?',
      body: 'This will replace the colors on the brand-library '
          'entry with the proposed values for every Lumina customer.',
      confirmLabel: 'Approve & Apply',
      confirmColor: NexGenPalette.cyan,
    );
    if (confirm != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isWorking = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final correctionRef = firestore
          .collection('brand_library_corrections')
          .doc(widget.correction.correctionId);
      final libraryRef = firestore
          .collection('brand_library')
          .doc(widget.correction.brandId);

      // 1. Replace colors on the brand-library entry, increment counter,
      //    and stamp last_verified. The Part-1 rules require user_role
      //    admin for this write — same predicate as the correction
      //    update so a single batch is fine.
      // 2. Mark the correction approved + applied + reviewer-stamped.
      final batch = firestore.batch();
      batch.set(
        libraryRef,
        {
          'colors': widget.correction.proposedColors
              .map((c) => c.toJson())
              .toList(),
          'correction_count': FieldValue.increment(1),
          'last_verified': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      batch.update(correctionRef, {
        'status': 'approved',
        'reviewed_by': user.uid,
        'reviewed_at': FieldValue.serverTimestamp(),
        'applied_to_library': true,
      });
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Approved — ${widget.correction.companyName} updated.'),
          backgroundColor: NexGenPalette.cyan,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approve failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _reject() async {
    final note = await _promptReason();
    if (note == null) return; // cancelled

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isWorking = true);
    try {
      await FirebaseFirestore.instance
          .collection('brand_library_corrections')
          .doc(widget.correction.correctionId)
          .update({
        'status': 'rejected',
        'reviewed_by': user.uid,
        'reviewed_at': FieldValue.serverTimestamp(),
        if (note.isNotEmpty) 'reviewer_note': note,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Correction rejected.'),
          backgroundColor: NexGenPalette.amber,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reject failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: Text(title,
            style: const TextStyle(color: NexGenPalette.textHigh)),
        content: Text(body,
            style: const TextStyle(color: NexGenPalette.textMedium)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.black),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptReason() async {
    final ctrl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Reject correction',
            style: TextStyle(color: NexGenPalette.textHigh)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Optional note for the audit trail.',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              maxLength: 280,
              style: const TextStyle(color: NexGenPalette.textHigh),
              decoration: InputDecoration(
                hintText: 'e.g. Hex codes don\'t match official guide',
                hintStyle: const TextStyle(color: NexGenPalette.textMedium),
                filled: true,
                fillColor: NexGenPalette.gunmetal,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: NexGenPalette.line),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.black),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.correction;

    return Container(
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
                child: Text(c.companyName,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Text(_formatDate(c.submittedAt),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Submitted by ${_shortUid(c.submittedBy)}'
            '${c.dealerCode.isNotEmpty ? ' • Dealer ${c.dealerCode}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (c.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NexGenPalette.matteBlack,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Text(c.reason,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NexGenPalette.textHigh,
                      fontStyle: FontStyle.italic)),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ColorColumn(
                  title: 'Current',
                  titleColor: NexGenPalette.textMedium,
                  colors: c.originalColors,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ColorColumn(
                  title: 'Proposed',
                  titleColor: NexGenPalette.cyan,
                  colors: c.proposedColors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isWorking ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isWorking ? null : _approve,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isWorking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('Approve & Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortUid(String uid) {
    if (uid.length <= 8) return uid;
    return '${uid.substring(0, 6)}…';
  }

  /// Manual short date formatter — avoids pulling in intl just to print
  /// "Apr 28, 2026 · 2:14 PM" on a moderation card.
  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hr12 = dt.hour == 0
        ? 12
        : dt.hour > 12
            ? dt.hour - 12
            : dt.hour;
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hr12:$mm $ampm';
  }
}

// ─── Color column ──────────────────────────────────────────────────────────

class _ColorColumn extends StatelessWidget {
  const _ColorColumn({
    required this.title,
    required this.titleColor,
    required this.colors,
  });

  final String title;
  final Color titleColor;
  final List<BrandColor> colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: titleColor)),
        const SizedBox(height: 6),
        if (colors.isEmpty)
          Text('—',
              style: Theme.of(context).textTheme.bodySmall),
        for (final c in colors) _colorRow(context, c),
      ],
    );
  }

  Widget _colorRow(BuildContext context, BrandColor c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: c.toColor(),
              shape: BoxShape.circle,
              border: Border.all(color: NexGenPalette.line),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${c.colorName.isEmpty ? c.roleTag : c.colorName}  '
              '#${c.hexCode.toUpperCase()}',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
