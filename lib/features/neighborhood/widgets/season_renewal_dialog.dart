import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../../sports_alerts/models/sport_type.dart';
import '../models/sync_event.dart';
import '../providers/sync_event_providers.dart';
import '../services/season_boundary_service.dart';
import 'season_schedule_picker.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SEASON RENEWAL DIALOG
// ═════════════════════════════════════════════════════════════════════════════
//
// Shown when a season schedule sync event's season has ended or is ending.
// Allows the user to renew for the next season with a preview of upcoming
// games and per-game deselection.
// ═════════════════════════════════════════════════════════════════════════════

/// Shows the season renewal dialog.
/// Returns true if the user renewed, false if dismissed.
Future<bool> showSeasonRenewalDialog(
  BuildContext context, {
  required SyncEvent event,
  required SeasonBoundaryInfo boundaryInfo,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NexGenPalette.gunmetal,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _SeasonRenewalSheet(
      event: event,
      boundaryInfo: boundaryInfo,
    ),
  );
  return result ?? false;
}

class _SeasonRenewalSheet extends ConsumerStatefulWidget {
  final SyncEvent event;
  final SeasonBoundaryInfo boundaryInfo;

  const _SeasonRenewalSheet({
    required this.event,
    required this.boundaryInfo,
  });

  @override
  ConsumerState<_SeasonRenewalSheet> createState() =>
      _SeasonRenewalSheetState();
}

class _SeasonRenewalSheetState extends ConsumerState<_SeasonRenewalSheet> {
  Set<String> _excludedGameIds = {};
  bool _isRenewing = false;

  int get _nextSeason =>
      widget.boundaryInfo.nextSeason ?? (widget.boundaryInfo.currentSeason + 1);

  SportType get _sport => widget.boundaryInfo.sport;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Icon(
                    widget.boundaryInfo.status == SeasonStatus.ended
                        ? Icons.flag
                        : Icons.update,
                    color: NexGenPalette.cyan,
                    size: 36,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.boundaryInfo.status == SeasonStatus.ended
                        ? 'Season Complete'
                        : 'Season Ending Soon',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  // Renewal banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NexGenPalette.cyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: NexGenPalette.cyan.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.autorenew,
                            color: NexGenPalette.cyan, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Renew for $_seasonLabel season',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Season schedule preview
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: widget.event.espnTeamId != null
                    ? SeasonSchedulePicker(
                        espnTeamId: widget.event.espnTeamId!,
                        teamName: widget.event.name,
                        sport: _sport,
                        teamColor: NexGenPalette.cyan,
                        excludedGameIds: _excludedGameIds,
                        onExcludedChanged: (excluded) {
                          setState(() => _excludedGameIds = excluded);
                        },
                      )
                    : const Text(
                        'No team configured',
                        style: TextStyle(color: Colors.white38),
                      ),
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isRenewing ? null : _renew,
                      icon: _isRenewing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.autorenew),
                      label: Text(
                        _isRenewing
                            ? 'Renewing...'
                            : 'Renew for $_seasonLabel',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: NexGenPalette.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      'Maybe Later',
                      style: TextStyle(color: Colors.white38),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String get _statusMessage {
    if (widget.boundaryInfo.status == SeasonStatus.ended) {
      return 'All home games for the ${widget.boundaryInfo.currentSeason} season are complete. '
          'Renew to keep syncing for next season.';
    }
    return '${widget.boundaryInfo.remainingGames} game(s) remaining this season. '
        'Get ready for $_seasonLabel!';
  }

  String get _seasonLabel {
    switch (_sport) {
      case SportType.nfl:
      case SportType.nhl:
      case SportType.nba:
      case SportType.ncaaFB:
      case SportType.ncaaMB:
        return '$_nextSeason-${(_nextSeason + 1) % 100}';
      case SportType.mlb:
      case SportType.mls:
      case SportType.nwsl:
      case SportType.wnba:
      case SportType.fifa:
      case SportType.championsLeague:
        return '$_nextSeason';
    }
  }

  Future<void> _renew() async {
    setState(() => _isRenewing = true);

    try {
      final renewed = renewForNextSeason(
        currentEvent: widget.event,
        nextSeason: _nextSeason,
        excludedGameIds: _excludedGameIds.toList(),
      );

      final newId = await ref.read(syncEventNotifierProvider.notifier).createSyncEvent(renewed);

      if (newId != null && mounted) {
        // Optionally disable the old event
        await ref.read(syncEventNotifierProvider.notifier).updateSyncEvent(
          widget.event.copyWith(isEnabled: false),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('[SeasonRenewal] Error renewing: $e');
    } finally {
      if (mounted) setState(() => _isRenewing = false);
    }
  }
}
