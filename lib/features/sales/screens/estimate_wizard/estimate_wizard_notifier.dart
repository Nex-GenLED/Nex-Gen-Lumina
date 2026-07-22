import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/features/sales/services/sales_job_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EstimateWizardNotifier
//
// Holds the in-progress SalesJob through all 5 wizard steps. Reads the
// initial job from activeJobProvider on first build, then keeps an
// in-memory edited copy that each step screen mutates via its
// `update...` methods.
//
// Persistence is opt-in: callers invoke `saveAndExit()` to flush the
// current state to Firestore via SalesJobService.updateJob and clear the
// activeJobProvider, or `saveProgress()` to flush without exiting.
//
// Note: this state is scoped to the lifetime of the wizard. The provider
// is autoDispose so re-entering the wizard always reads fresh from
// activeJobProvider.
// ─────────────────────────────────────────────────────────────────────────────

class EstimateWizardNotifier extends StateNotifier<SalesJob> {
  final Ref _ref;

  EstimateWizardNotifier(this._ref, SalesJob initial) : super(initial);

  // ── Step 1: home photo ──────────────────────────────────────────────────

  void updateHomePhotoPath(String? path) {
    state = state.copyWith(homePhotoPath: path);
  }

  // ── Step 2: controller mount ────────────────────────────────────────────

  void updateControllerMount(ControllerMount? mount) {
    state = state.copyWith(controllerMount: mount);
  }

  // ── Step 3: channel runs ────────────────────────────────────────────────

  void addChannelRun(ChannelRun run) {
    state = state.copyWith(channelRuns: [...state.channelRuns, run]);
  }

  void updateChannelRun(ChannelRun updated) {
    final next = state.channelRuns
        .map((r) => r.id == updated.id ? updated : r)
        .toList();
    state = state.copyWith(channelRuns: next);
  }

  void removeChannelRun(String id) {
    final next = state.channelRuns.where((r) => r.id != id).toList();
    // Cascade: remove any injection points referencing this run.
    final nextInjections = state.powerInjectionPoints
        .where((p) => p.channelRunId != id)
        .toList();
    state = state.copyWith(
      channelRuns: next,
      powerInjectionPoints: nextInjections,
    );
  }

  /// Returns the next 1-based channel number to assign.
  int get nextChannelNumber {
    if (state.channelRuns.isEmpty) return 1;
    final used = state.channelRuns.map((r) => r.channelNumber);
    return used.reduce((a, b) => a > b ? a : b) + 1;
  }

  // ── Step 4: power injection points ──────────────────────────────────────

  void addPowerInjectionPoint(PowerInjectionPoint point) {
    state = state.copyWith(
      powerInjectionPoints: [...state.powerInjectionPoints, point],
    );
  }

  void updatePowerInjectionPoint(PowerInjectionPoint updated) {
    final next = state.powerInjectionPoints
        .map((p) => p.id == updated.id ? updated : p)
        .toList();
    state = state.copyWith(powerInjectionPoints: next);
  }

  void removePowerInjectionPoint(String id) {
    final next =
        state.powerInjectionPoints.where((p) => p.id != id).toList();
    state = state.copyWith(powerInjectionPoints: next);
  }

  /// Returns all injection points belonging to a given channel run.
  List<PowerInjectionPoint> injectionsForRun(String channelRunId) =>
      state.powerInjectionPoints
          .where((p) => p.channelRunId == channelRunId)
          .toList();

  // ── Validation helpers used by Step 5 ───────────────────────────────────

  /// Channel runs over 100ft that have no injection point. Used by the
  /// summary screen warning chip and (in Prompt 3) by
  /// MaterialCalculationService.
  List<ChannelRun> get runsNeedingInjection {
    return state.channelRuns.where((run) {
      if (run.linearFeet <= 100) return false;
      return injectionsForRun(run.id).isEmpty;
    }).toList();
  }

  bool get hasHomePhoto =>
      state.homePhotoPath != null && state.homePhotoPath!.isNotEmpty;

  bool get hasControllerMount => state.controllerMount != null;

  bool get hasChannelRuns => state.channelRuns.isNotEmpty;

  // ── Persistence ─────────────────────────────────────────────────────────

  /// Persist current wizard state to Firestore via SalesJobService and
  /// also push the latest copy into [activeJobProvider] so the rest of
  /// the sales feature stays in sync.
  Future<void> saveProgress() async {
    final service = _ref.read(salesJobServiceProvider);
    await service.updateJob(state);
    _ref.read(activeJobProvider.notifier).state = state;
  }
}

/// Family-scoped autoDispose provider keyed on the jobId. Each wizard
/// session reads its initial job from [activeJobProvider]; if no active
/// job exists with the given id, an empty placeholder is constructed
/// (this should not happen in practice — callers should ensure a draft
/// job is in place before navigating into the wizard).
final estimateWizardProvider = StateNotifierProvider.autoDispose
    .family<EstimateWizardNotifier, SalesJob, String>((ref, jobId) {
  final active = ref.read(activeJobProvider);
  final initial = (active != null && active.id == jobId)
      ? active
      : SalesJob(
          id: jobId,
          jobNumber: '',
          dealerCode: '',
          salespersonUid: '',
          prospect: SalesProspect(
            id: jobId,
            firstName: '',
            lastName: '',
            email: '',
            phone: '',
            address: '',
            city: '',
            state: '',
            zipCode: '',
            createdAt: DateTime.now(),
          ),
          zones: const [],
          status: SalesJobStatus.draft,
          totalPriceUsd: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
  return EstimateWizardNotifier(ref, initial);
});
