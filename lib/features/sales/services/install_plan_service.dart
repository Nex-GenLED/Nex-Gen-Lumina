import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// InstallTask
// ─────────────────────────────────────────────────────────────────────────────

class InstallTask {
  final String id;
  final String category;
  final String description;
  final bool requiresPhoto;
  final int day;
  final bool completed;
  final String? completionPhotoUrl;

  const InstallTask({
    required this.id,
    required this.category,
    required this.description,
    this.requiresPhoto = false,
    required this.day,
    this.completed = false,
    this.completionPhotoUrl,
  });

  InstallTask copyWith({bool? completed, String? completionPhotoUrl}) =>
      InstallTask(
        id: id,
        category: category,
        description: description,
        requiresPhoto: requiresPhoto,
        day: day,
        completed: completed ?? this.completed,
        completionPhotoUrl: completionPhotoUrl ?? this.completionPhotoUrl,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'description': description,
    'requiresPhoto': requiresPhoto,
    'day': day,
    'completed': completed,
    'completionPhotoUrl': completionPhotoUrl,
  };

  factory InstallTask.fromJson(Map<String, dynamic> j) => InstallTask(
    id: j['id'] ?? '',
    category: j['category'] ?? '',
    description: j['description'] ?? '',
    requiresPhoto: j['requiresPhoto'] ?? false,
    day: j['day'] ?? 1,
    completed: j['completed'] ?? false,
    completionPhotoUrl: j['completionPhotoUrl'],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// InstallPlanService
// ─────────────────────────────────────────────────────────────────────────────

class InstallPlanService {

  /// Build the ordered Day 1 (pre-wire & electrical) task list.
  List<InstallTask> buildDay1Tasks(SalesJob job) {
    final tasks = <InstallTask>[];

    // Find the controller mount across all zones
    PowerMount? controllerMount;
    for (final zone in job.zones) {
      for (final mount in zone.mounts) {
        if (mount.isController) {
          controllerMount = mount;
          break;
        }
      }
      if (controllerMount != null) break;
    }

    // ── Step 1: New outlet tasks ──
    for (final zone in job.zones) {
      for (final mount in zone.mounts) {
        if (mount.outletType == OutletType.newRequired) {
          tasks.add(InstallTask(
            id: 'outlet_${mount.id}',
            category: 'Electrician',
            description: 'Install new dedicated outlet — '
                '${mount.outletNote.isNotEmpty ? mount.outletNote : 'location TBD'}',
            requiresPhoto: true,
            day: 1,
          ));
        }
      }
    }

    // ── Step 2: Mount tasks ──
    for (final zone in job.zones) {
      for (final mount in zone.mounts) {
        final label = mount.isController
            ? 'controller'
            : '${mount.supplySize} supply';
        final outletRef = mount.outletNote.isNotEmpty
            ? mount.outletNote
            : 'marked location';
        tasks.add(InstallTask(
          id: 'mount_${mount.id}',
          category: mount.isController ? 'Mount' : 'Add\'l supply',
          description: 'Mount $label at ${mount.positionFt}ft — '
              'connect to ${mount.outletType.label}: $outletRef',
          requiresPhoto: true,
          day: 1,
        ));
      }
    }

    // ── Step 3: Ground wire tasks ──
    for (final zone in job.zones) {
      for (final mount in zone.mounts) {
        if (!mount.isController && controllerMount != null) {
          final dist = (mount.positionFt - controllerMount.positionFt).abs();
          final buffered = (dist * 1.1).ceil();
          tasks.add(InstallTask(
            id: 'ground_${mount.id}',
            category: 'Ground',
            description: 'Run 10AWG common ground: supply at '
                '${mount.positionFt}ft → controller at '
                '${controllerMount.positionFt}ft — ${buffered}ft',
            day: 1,
          ));
        }
      }
    }

    // ── Step 4: Drill and wire run tasks ──
    int injIndex = 1;
    for (final zone in job.zones) {
      for (final injection in zone.injections) {
        final mountPos = injection.servedByController
            ? (controllerMount?.positionFt ?? 0)
            : _findAdditionalMountPos(zone, injection);
        final servedByLabel = injection.servedByController
            ? 'controller'
            : 'additional supply';

        tasks.add(InstallTask(
          id: 'drill_${injection.id}',
          category: 'Drill',
          description: 'Drill injection hole at ${injection.positionFt}ft — '
              '${zone.name} — mark location before drilling',
          requiresPhoto: true,
          day: 1,
        ));
        tasks.add(InstallTask(
          id: 'wire_${injection.id}',
          category: injection.wireGauge.label,
          description: 'Run ${injection.wireGauge.label} from $servedByLabel '
              'at ${mountPos}ft to injection #$injIndex at '
              '${injection.positionFt}ft — ${injection.wireRunFt.ceil()}ft — '
              'label "INJ-$injIndex" and cap',
          day: 1,
        ));
        injIndex++;
      }
    }

    // ── Step 5: Always-last tasks ──
    tasks.add(const InstallTask(
      id: 'ground_check',
      category: 'Ground check',
      description: 'Verify 10AWG common ground continuity — '
          'controller to all additional supplies',
      day: 1,
    ));
    tasks.add(const InstallTask(
      id: 'sign_off',
      category: 'Sign off',
      description: 'Final check — all connections secure, all wires '
          'labeled and capped, no exposed conductors',
      day: 1,
    ));

    return tasks;
  }

  /// Build the ordered Day 2 (install) task list.
  List<InstallTask> buildDay2Tasks(SalesJob job) {
    final tasks = <InstallTask>[];
    int injIndex = 1;

    for (final zone in job.zones) {
      tasks.add(InstallTask(
        id: 'rails_${zone.id}',
        category: 'Rails',
        description: 'Install rails — ${zone.name}, '
            '${zone.runLengthFt}ft total run',
        day: 2,
      ));
      tasks.add(InstallTask(
        id: 'lights_${zone.id}',
        category: 'Lights',
        description: 'Mount lights along rails — ${zone.name}',
        day: 2,
      ));
      for (final inj in zone.injections) {
        tasks.add(InstallTask(
          id: 'connect_${inj.id}',
          category: 'Connect INJ-$injIndex',
          description: 'Connect pre-labeled wire "INJ-$injIndex" at '
              '${inj.positionFt}ft to strip injection point — '
              'wire is labeled and capped from Day 1',
          day: 2,
        ));
        injIndex++;
      }
    }

    tasks.addAll([
      const InstallTask(
        id: 'test',
        category: 'Test',
        description: 'Power on — verify all zones, confirm colors '
            'and pixel response',
        day: 2,
      ),
      const InstallTask(
        id: 'handoff',
        category: 'Handoff',
        description: 'Walk customer through Lumina app — scenes, '
            'scheduling, referral link',
        day: 2,
      ),
      const InstallTask(
        id: 'final_photos',
        category: 'Final photos',
        description: 'Photograph completed install — attach to job record',
        requiresPhoto: true,
        day: 2,
      ),
    ]);

    return tasks;
  }

  /// Find the position of the additional supply mount serving this injection.
  double _findAdditionalMountPos(InstallZone zone, InjectionPoint inj) {
    for (final mount in zone.mounts) {
      if (!mount.isController && mount.servesInjectionIds.contains(inj.id)) {
        return mount.positionFt;
      }
    }
    return 0.0;
  }
}

final installPlanServiceProvider = Provider<InstallPlanService>(
  (ref) => InstallPlanService(),
);
