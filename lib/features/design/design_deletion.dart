import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Where a delete was initiated from. Only affects the confirmation copy —
/// both origins destroy the SAME `/users/{uid}/designs/{id}` document, so the
/// user is told about the side the request did NOT come from.
///
/// Background (audit/MY_DESIGNS_AUDIT.md §5.1): `allScenesProvider` merges
/// `designsStreamProvider` into the scene list via `Scene.fromDesign`, so every
/// saved design is ALSO a `SceneType.custom` scene. Deleting either removes
/// the one underlying doc.
enum DesignDeleteOrigin {
  /// Initiated from My Designs (detail screen or row action).
  design,

  /// Initiated from a scene surface (`deleteSceneProvider`).
  scene,
}

/// THE delete entry point for a [CustomDesign].
///
/// This is the only place in the app that reaches
/// `DesignService.deleteDesign`. `deleteDesignProvider` delegates here, and
/// `deleteSceneProvider`'s `SceneType.custom` branch delegates to
/// `deleteDesignProvider` — so all three surfaces converge on one call.
/// Replaces the previous split where `MySavedDesignsSection` owned an
/// independent confirm-then-delete flow (audit §3.3, §4.1).
///
/// Returns the deleted design on success (the caller needs it to offer undo),
/// or null on failure.
final deleteDesignEntryPointProvider =
    Provider<Future<CustomDesign?> Function(CustomDesign)>((ref) {
  return (design) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return null;
    final service = ref.read(designServiceProvider);
    try {
      await service.deleteDesign(user.uid, design.id);
      return design;
    } catch (e) {
      debugPrint('deleteDesignEntryPoint: delete failed — $e');
      return null;
    }
  };
});

/// Re-creates a deleted design AT ITS ORIGINAL ID.
///
/// Undo restores the same doc id — `DesignService.restoreDesign` writes with
/// `.doc(id).set(...)` rather than `.add(...)`, so every by-id reference
/// (including the `design_{id}` detail route) keeps resolving after an undo.
final restoreDesignProvider =
    Provider<Future<bool> Function(CustomDesign)>((ref) {
  return (design) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return false;
    try {
      await ref.read(designServiceProvider).restoreDesign(user.uid, design);
      return true;
    } catch (e) {
      debugPrint('restoreDesign: failed — $e');
      return false;
    }
  };
});

/// Confirmation copy for a delete originating on [origin].
///
/// Each origin names the OTHER surface's consequence, because that is the one
/// the user cannot see from where they are standing.
@visibleForTesting
String deleteConfirmationBody(CustomDesign design, DesignDeleteOrigin origin) {
  switch (origin) {
    case DesignDeleteOrigin.design:
      return 'Delete "${design.name}"?\n\n'
          'The matching scene will disappear too — saved designs and custom '
          'scenes are the same item, so it will stop being available to voice '
          'and Lumina commands.';
    case DesignDeleteOrigin.scene:
      return 'Delete "${design.name}"?\n\n'
          'This design will be removed from My Designs — custom scenes and '
          'saved designs are the same item.';
  }
}

/// Confirm → delete → offer undo. The one UI flow for removing a design.
///
/// Extracted from `MySavedDesignsSection._confirmRemoveDesign`
/// (deleted in this change; see audit/DESIGN_CARD_P2.md §4).
///
/// Returns true when the design was deleted AND the user did not undo by the
/// time this future completes. Callers that navigate on success (the detail
/// screen pops to the list) should treat true as "it is gone".
Future<bool> confirmAndDeleteDesign(
  BuildContext context,
  WidgetRef ref,
  CustomDesign design, {
  DesignDeleteOrigin origin = DesignDeleteOrigin.design,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Design?'),
      content: Text(deleteConfirmationBody(design, origin)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  final deleted = await ref.read(deleteDesignEntryPointProvider)(design);
  if (!context.mounted) return deleted != null;

  if (deleted == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to delete design')),
    );
    return false;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Deleted "${deleted.name}"'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Undo',
        textColor: NexGenPalette.cyan,
        onPressed: () async {
          final restored = await ref.read(restoreDesignProvider)(deleted);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(restored
                  ? 'Restored "${deleted.name}"'
                  : 'Could not restore "${deleted.name}"'),
            ),
          );
        },
      ),
    ),
  );
  return true;
}
