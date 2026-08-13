// The floor of W1's surface: what the customer sees if the notification never
// arrived — denied permission, notifications off, killed before delivery.
//
// The notification announces the TRANSITION; this shows the STANDING state. It
// is the half that cannot fail, which is why the permission check gates
// immediacy and never legibility.

import 'package:flutter/material.dart';

import 'package:nexgen_command/app_colors.dart';
import 'services/sync_refusal_record.dart';

/// Shows the standing sync refusal, or nothing.
class SyncRefusalBanner extends StatefulWidget {
  /// Injectable for tests; defaults to the real device store.
  final SyncRefusalStore store;

  const SyncRefusalBanner({super.key, this.store = const SyncRefusalStore()});

  @override
  State<SyncRefusalBanner> createState() => _SyncRefusalBannerState();
}

class _SyncRefusalBannerState extends State<SyncRefusalBanner> {
  SyncRefusal? _refusal;

  @override
  void initState() {
    super.initState();
    widget.store.standing().then((r) {
      if (mounted) setState(() => _refusal = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _refusal;
    if (r == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.cyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 18, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.title,
                  style: const TextStyle(
                    color: NexGenPalette.cyan,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              InkWell(
                // Dismiss clears the STANDING record, not the announced-set:
                // dismissing must not make the same blocked night notify again.
                onTap: () async {
                  await widget.store.clearStanding();
                  if (mounted) setState(() => _refusal = null);
                },
                child: const Icon(Icons.close,
                    size: 16, color: NexGenPalette.textMedium),
              ),
            ],
          ),
          if (r.message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.message,
              style: const TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
