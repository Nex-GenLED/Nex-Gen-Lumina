import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/design/apply_saved_design.dart';
import 'package:nexgen_command/features/design/design_deletion.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/design_frame.dart';
import 'package:nexgen_command/features/design/manual_editor/design_preview.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// How a design was authored. Derived, not stored — the writers all land in
/// one collection and the shape is what distinguishes them
/// (audit/MY_DESIGNS_AUDIT.md §2.5).
enum DesignKind {
  /// Authored in the AI Design Studio; carries the `composed_pattern` layer.
  aiComposed,

  /// Per-LED paint: multiple color groups on at least one channel.
  perPixel,

  /// A captured look: one color group per channel plus an effect id.
  effect,
}

extension DesignKindLabel on DesignKind {
  String get label {
    switch (this) {
      case DesignKind.aiComposed:
        return 'AI-composed';
      case DesignKind.perPixel:
        return 'Per-pixel';
      case DesignKind.effect:
        return 'Effect';
    }
  }

  IconData get icon {
    switch (this) {
      case DesignKind.aiComposed:
        return Icons.auto_awesome;
      case DesignKind.perPixel:
        return Icons.grid_on_rounded;
      case DesignKind.effect:
        return Icons.blur_on_rounded;
    }
  }
}

/// Classifies a stored design by its shape.
///
/// `composedPattern` wins because it is the only unambiguous provenance marker
/// on the doc. Note this READS the field's presence only — it does not decode
/// or interpret it (deliberately out of scope for this change).
DesignKind designKindOf(CustomDesign design) {
  if (design.composedPattern != null) return DesignKind.aiComposed;
  final included = design.channels.where((c) => c.included);
  final multiGroup = included.any((c) => c.colorGroups.length > 1);
  return multiGroup ? DesignKind.perPixel : DesignKind.effect;
}

/// Design detail for `/explore/library/design_{id}`.
///
/// Replaces the spinner + post-frame `applySavedDesign` + pop branch that used
/// to occupy this route (audit/MY_DESIGNS_AUDIT.md §3.1, §8): the route that
/// should host a detail card was consumed entirely by the apply side effect,
/// which is why the surface read as apply-only with no edit/rename/delete.
///
/// Apply still runs the SAME `applySavedDesign` the spinner called — this
/// screen adds affordances, it does not add a second apply path.
class DesignDetailScreen extends ConsumerWidget {
  const DesignDetailScreen({
    super.key,
    required this.designId,
    this.embedded = false,
  });

  final String designId;

  /// True when this screen is rendered INSIDE another Scaffold that already
  /// supplies the chrome — specifically `LibraryBrowserScreen`, which owns the
  /// route and renders its own `Scaffold` + `AppBar` + breadcrumb before
  /// handing the body to us (pattern_theme_selection.dart, the
  /// `isSavedDesign` branch).
  ///
  /// In that case our own `Scaffold` + [GlassAppBar] were a SECOND header,
  /// titled with the same design name as the parent's — two stacked bars plus
  /// a breadcrumb, ~142px of duplicate chrome that pushed the action buttons
  /// further toward the dock.
  ///
  /// Left false for the STANDALONE push, which has no parent chrome of its own:
  /// `_duplicate`'s `pushReplacement` onto the new doc (the only such call
  /// site — verified by grep, not assumed). A standalone instance must keep its
  /// Scaffold or it would render with no app bar and no way back.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(designByIdProvider(designId));
    final body = async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Message(
        icon: Icons.error_outline,
        title: 'Could not load this design',
        body: '$e',
      ),
      data: (design) {
        if (design == null) {
          return const _Message(
            icon: Icons.search_off_rounded,
            title: 'Design not found',
            body: 'It may have been deleted from another device. '
                'Go back to see your current designs.',
          );
        }
        return _DesignDetailBody(design: design);
      },
    );

    // Embedded: the parent's Scaffold supplies the background, the app bar and
    // the back affordance. Returning the bare body is what removes the second
    // header — nothing about the content changes.
    if (embedded) return body;

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: GlassAppBar(
        title: Text(async.valueOrNull?.name ?? 'Design'),
      ),
      body: body,
    );
  }
}

/// Loading / not-found / error state with a way back — never a blank screen.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: NexGenPalette.textMedium),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: NexGenPalette.textSecondary)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back to My Designs'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesignDetailBody extends ConsumerWidget {
  const _DesignDetailBody({required this.design});
  final CustomDesign design;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = designKindOf(design);
    final included =
        design.channels.where((c) => c.included).toList(growable: false);
    final colorCount =
        included.fold<int>(0, (n, c) => n + c.colorGroups.length);
    final effectId = included.isEmpty ? null : included.first.effectId;

    // Device channel lengths when connected; the frame producer falls back to
    // each ChannelDesign's stored ledCount when this is empty.
    final channels = ref.watch(deviceChannelsProvider);
    final lengths = <int, int>{
      for (final c in channels) c.id: (c.stop - c.start).clamp(0, 100000),
    };

    return ListView(
      // The glass dock is a Stack OVERLAY, not a bottomNavigationBar:
      // MainScaffold renders it `Positioned(bottom: 0)` over a
      // `Positioned.fill` branch host with `extendBody: true`
      // (main_scaffold.dart:190-215). Content therefore extends UNDER it, and
      // a scrollable must reserve its height itself.
      //
      // This screen shipped with a flat `32` here, so the last ~100px + the
      // home-indicator inset rendered beneath the dock — putting the
      // Duplicate/Delete row under it on a short device, where the dock (being
      // above in z-order) takes the taps. `navBarTotalHeight` is the
      // established helper for exactly this and already folds in
      // `MediaQuery.padding.bottom`; the convention is documented at
      // main_scaffold.dart:235-244 and used by 50+ scrollables.
      padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context) + 16),
      children: [
        // The ONE preview seam. Its internals (a truthful effect renderer)
        // are replaced later without touching this call site.
        DesignPreview(
          frame: frameFromCustomDesign(design, channelLengths: lengths),
          height: 200,
        ),
        const SizedBox(height: 20),
        Text(design.name,
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        if (design.description != null && design.description!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(design.description!,
              style: TextStyle(color: NexGenPalette.textSecondary)),
        ],
        const SizedBox(height: 16),
        _MetaRow(icon: kind.icon, label: 'Type', value: kind.label),
        _MetaRow(
          icon: Icons.auto_fix_high_outlined,
          label: 'Effect',
          value: effectId == null
              ? '—'
              : '${WledEffectsCatalog.getName(effectId)}  (fx $effectId)',
        ),
        _MetaRow(
          icon: Icons.palette_outlined,
          label: 'Colors',
          value: '$colorCount supplied',
        ),
        _MetaRow(
          icon: Icons.cable_rounded,
          label: 'Channels',
          value: included.isEmpty
              ? 'None'
              : included
                  .map((c) =>
                      c.channelName.isEmpty ? 'Ch ${c.channelId}' : c.channelName)
                  .join(', '),
        ),
        _MetaRow(
          icon: Icons.brightness_6_outlined,
          label: 'Brightness',
          value: '${design.brightness}',
        ),
        _MetaRow(
          icon: Icons.event_outlined,
          label: 'Created',
          value: _stamp(design.createdAt),
        ),
        _MetaRow(
          icon: Icons.update_rounded,
          label: 'Updated',
          value: _stamp(design.updatedAt),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => applySavedDesign(context, ref, design),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Apply to Lights'),
          style: FilledButton.styleFrom(
            backgroundColor: NexGenPalette.cyan,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              // Per-pixel → the paint editor. Effect → the colourway tuner in
              // design-edit mode (Phase C). AI-composed stays disabled: its
              // editor has no open-existing path and `composedPattern` has no
              // reader (audit/DESIGN_CARD_P4.md §4).
              onPressed: kind == DesignKind.aiComposed
                  ? null
                  : () => _openEditor(context, ref, kind),
              icon: const Icon(Icons.brush_outlined, size: 18),
              label: const Text('Edit'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _rename(context, ref),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Rename'),
            ),
          ),
        ]),
        if (kind == DesignKind.aiComposed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Editing an AI-composed design reopens it in the Design '
              'Studio — not wired yet.',
              style: TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _duplicate(context, ref),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Duplicate'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _delete(context, ref),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
            ),
          ),
        ]),
      ],
    );
  }

  static String _stamp(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  Future<void> _openEditor(
      BuildContext context, WidgetRef ref, DesignKind kind) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        appBar: GlassAppBar(title: Text('Edit ${design.name}')),
        body: kind == DesignKind.perPixel
            ? ManualDesignEditor(initialDesign: design)
            : ColorwayEffectSelectorPage.forDesign(design: design),
      ),
    ));
    ref.invalidate(designByIdProvider(design.id));
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: design.name);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Design'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (next == null || !context.mounted) return;
    final ok = await ref.read(renameDesignProvider)(design, next);
    if (!context.mounted) return;
    ref.invalidate(designByIdProvider(design.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Renamed' : 'Rename failed')),
    );
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
    final newId =
        await ref.read(duplicateDesignProvider)(design, '${design.name} copy');
    if (!context.mounted) return;
    if (newId == null || newId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Duplicate failed')),
      );
      return;
    }
    // Land on the NEW doc's detail screen — replace so Back returns to the
    // list rather than the original's detail.
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => DesignDetailScreen(designId: newId),
    ));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final gone = await confirmAndDeleteDesign(context, ref, design);
    if (gone && context.mounted) Navigator.of(context).maybePop();
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: NexGenPalette.textMedium),
        const SizedBox(width: 10),
        SizedBox(
          width: 88,
          child: Text(label,
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      ]),
    );
  }
}
