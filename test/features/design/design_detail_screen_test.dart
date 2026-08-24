// Phase A gate (audit/DESIGN_CARD_P2.md §A6). Covers the behaviours the
// My Designs audit identified as broken or missing:
//   • the design_{id} route renders DesignDetailScreen, NOT the old spinner,
//     and does not apply on open (audit/MY_DESIGNS_AUDIT.md §3.1, §8);
//   • both entry points resolve to the same screen for the same id (§2b);
//   • delete converges on one entry point (§3.3, §4.1);
//   • rename changes only `name` and preserves composedPattern (§6.2, §6.5);
//   • an edit save updates in place and never creates a doc (§6.1);
//   • catalog palette cards grow no overflow affordance (§2b.4).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_deletion.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/design_frame.dart';
import 'package:nexgen_command/features/design/screens/design_detail_screen.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_grid_widgets.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';

CustomDesign sampleDesign({
  String id = 'd1',
  String name = 'All Blue',
  Map<String, dynamic>? composedPattern,
  int groupCount = 1,
}) {
  return CustomDesign(
    id: id,
    name: name,
    description: 'a description',
    createdAt: DateTime(2026, 5, 29),
    updatedAt: DateTime(2026, 6, 1),
    ownerId: 'u',
    brightness: 180,
    tags: const ['warm', 'front'],
    channels: [
      ChannelDesign(
        channelId: 0,
        channelName: 'Front',
        included: true,
        effectId: 12,
        colorGroups: [
          for (var i = 0; i < groupCount; i++)
            LedColorGroup(
                startLed: i * 5, endLed: i * 5 + 4, color: const [0, 0, 255, 0]),
        ],
        ledCount: groupCount * 5,
      ),
    ],
    composedPattern: composedPattern,
  );
}

void main() {
  group('route branch — DesignDetailScreen replaces the spinner', () {
    // The old branch built `Center(child: CircularProgressIndicator())` and
    // ran applySavedDesign + pop from a post-frame callback. The screen must
    // now be a real detail surface that applies only when asked.
    testWidgets('renders detail content, not a bare spinner, and does not '
        'apply on open', (tester) async {
      final design = sampleDesign();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          designsStreamProvider.overrideWith((_) => Stream.value([design])),
          designByIdProvider(design.id).overrideWith((_) async => design),
          // wledRepositoryProvider is left at its default (null in a test
          // binding). That is what makes the no-apply-on-open assertion
          // OBSERVABLE rather than assumed: applySavedDesign's first act on a
          // null repository is to show a 'No device connected' SnackBar
          // (apply_saved_design.dart:44-52). The old spinner branch ran that
          // routine from a post-frame callback, so it would surface here.
        ],
        child: MaterialApp(
          home: DesignDetailScreen(designId: design.id),
        ),
      ));
      await tester.pumpAndSettle();

      // Detail content, not a spinner.
      expect(find.text('All Blue'), findsWidgets);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Colors'), findsOneWidget);
      expect(find.text('1 supplied'), findsOneWidget);
      // fx 12 comes off the stored ChannelDesign, not the live device.
      expect(find.textContaining('(fx 12)'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Nothing was applied on open, and nothing popped the route.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(DesignDetailScreen), findsOneWidget);

      // The actions exist — scroll them into view (the detail body is a
      // ListView; below-fold children are not built in the test viewport).
      final list = find.byType(Scrollable).first;
      for (final label in ['Apply to Lights', 'Rename', 'Duplicate', 'Delete']) {
        await tester.scrollUntilVisible(find.text(label), 120, scrollable: list);
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('missing id shows a clear message and a way back, '
        'never a blank screen', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          designsStreamProvider
              .overrideWith((_) => Stream.value(const <CustomDesign>[])),
          designByIdProvider('ghost').overrideWith((_) async => null),
        ],
        child: const MaterialApp(home: DesignDetailScreen(designId: 'ghost')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Design not found'), findsOneWidget);
      expect(find.text('Back to My Designs'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('both entry points → one screen for one id', () {
    // The home tile pushes the literal '/explore/library/my_designs' and the
    // Explore folder card pushes '/explore/library/${category.id}'. Both
    // produce the same nodeId, so the adapter must yield an identical node —
    // which is what makes the detail route identical for both (§2b.2).
    test('the design_{id} node is identical regardless of caller', () async {
      final design = sampleDesign(id: 'abc123');
      final c = ProviderContainer(overrides: [
        designsStreamProvider.overrideWith((_) => Stream.value([design])),
      ]);
      addTearDown(c.dispose);
      await c.read(designsStreamProvider.future);

      final children =
          await c.read(libraryChildNodesProvider(kMyDesignsCategoryId).future);
      expect(children, hasLength(1));
      final fromList = children.single;
      final fromRoute =
          await c.read(libraryNodeByIdProvider('design_abc123').future);

      expect(fromRoute, isNotNull);
      expect(fromList.id, 'design_abc123');
      expect(fromRoute!.id, fromList.id);
      expect(fromRoute.metadata?['sourceDesignId'],
          fromList.metadata?['sourceDesignId']);
      expect(fromRoute.metadata?['sourceDesignId'], 'abc123');
    });
  });

  group('rename', () {
    test('changes only the name and preserves every other field, '
        'including composedPattern', () {
      final original = sampleDesign(composedPattern: {
        'source_intent': {'zones': 2},
        'wled_payload': {
          'seg': [
            {
              'col': [
                [255, 0, 0, 0]
              ]
            }
          ]
        },
      });

      // renameDesignProvider does exactly this copyWith before handing the
      // design to DesignService.updateDesign.
      final renamed = original.copyWith(name: 'Renamed');

      expect(renamed.name, 'Renamed');
      expect(renamed.id, original.id);
      expect(renamed.description, original.description);
      expect(renamed.brightness, original.brightness);
      expect(renamed.tags, original.tags);
      expect(renamed.ownerId, original.ownerId);
      expect(renamed.createdAt, original.createdAt);
      expect(renamed.channels.length, original.channels.length);
      expect(renamed.composedPattern, isNotNull);
      expect(renamed.composedPattern, original.composedPattern);

      // And the field survives the Firestore round trip the write uses.
      final wire = renamed.toFirestore();
      expect(wire['name'], 'Renamed');
      expect(wire.containsKey('composed_pattern'), isTrue);
    });

    test('a design with no composedPattern omits the key, so .update() '
        'leaves any stored value untouched', () {
      final wire = sampleDesign().toFirestore();
      expect(wire.containsKey('composed_pattern'), isFalse);
    });
  });

  group('edit save — update in place, never create', () {
    // DesignService.saveDesign routes on id: empty → createDesign,
    // non-empty → updateDesign (design_service.dart:43-49). Carrying the
    // loaded design's id forward is therefore what guarantees an edit
    // cannot fork a second doc.
    test('an edited design keeps its id and its untouched fields', () {
      final original = sampleDesign(id: 'keep-me', composedPattern: {'a': 1});
      final editedChannels = [
        ChannelDesign(
          channelId: 0,
          channelName: 'Channel 1',
          included: true,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 4, color: const [0, 255, 0, 0]),
          ],
          ledCount: 5,
        ),
      ];
      final edited = original.copyWith(
        channels: editedChannels,
        updatedAt: DateTime(2026, 7, 1),
      );

      expect(edited.id, 'keep-me');
      expect(edited.id, isNotEmpty, reason: 'non-empty id → updateDesign');
      expect(edited.name, original.name, reason: 'an edit keeps the name');
      expect(edited.composedPattern, original.composedPattern);
      expect(edited.channels.single.colorGroups.single.color, [0, 255, 0, 0]);
    });
  });

  group('new-design naming', () {
    test('defaults to Custom Design N, N = matching count + 1', () {
      expect(nextCustomDesignName(const []), 'Custom Design 1');
      expect(
        nextCustomDesignName([sampleDesign(name: 'Custom Design')]),
        'Custom Design 2',
      );
      expect(
        nextCustomDesignName([
          sampleDesign(id: 'a', name: 'Custom Design'),
          sampleDesign(id: 'b', name: 'Custom Design 2'),
          sampleDesign(id: 'c', name: 'Front Porch Warm'),
        ]),
        'Custom Design 3',
        reason: 'unrelated names must not inflate N',
      );
    });
  });

  group('delete confirmation copy names the other surface', () {
    test('design-side warns the scene disappears', () {
      final body = deleteConfirmationBody(
          sampleDesign(), DesignDeleteOrigin.design);
      expect(body, contains('scene'));
    });

    test('scene-side warns it leaves My Designs', () {
      final body =
          deleteConfirmationBody(sampleDesign(), DesignDeleteOrigin.scene);
      expect(body, contains('My Designs'));
    });
  });

  group('catalog cards grow no overflow affordance', () {
    testWidgets('a palette node with no actions renders the chevron only',
        (tester) async {
      const node = LibraryNode(
        id: 'arch_k2700',
        name: 'Incandescent',
        nodeType: LibraryNodeType.palette,
        themeColors: [Colors.orange],
      );
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
                height: 44, child: LibraryNodeCard(node: node, index: 0)),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);
    });

    testWidgets('supplying actions swaps the chevron for the menu',
        (tester) async {
      const node = LibraryNode(
        id: 'design_d1',
        name: 'All Blue',
        nodeType: LibraryNodeType.palette,
        themeColors: [Colors.blue],
        metadata: {'isSavedDesign': true, 'sourceDesignId': 'd1'},
      );
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 44,
              child: LibraryNodeCard(
                node: node,
                index: 0,
                actions: [
                  LibraryNodeAction(
                      label: 'Apply',
                      icon: Icons.play_arrow_rounded,
                      onSelected: () {}),
                  LibraryNodeAction(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      isDestructive: true,
                      onSelected: () {}),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_ios), findsNothing);
    });
  });

  group('preview seam', () {
    test('frameFromCustomDesign yields channel-local colors and omits '
        'excluded channels', () {
      final design = CustomDesign(
        id: 'd',
        name: 'n',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        ownerId: 'u',
        channels: [
          ChannelDesign(
            channelId: 0,
            channelName: 'A',
            included: true,
            colorGroups: [
              LedColorGroup(startLed: 0, endLed: 1, color: const [255, 0, 0, 0]),
            ],
            ledCount: 4,
          ),
          const ChannelDesign(
              channelId: 1, channelName: 'B', included: false, ledCount: 4),
        ],
      );

      final frame = frameFromCustomDesign(design);
      expect(frame.keys, [0]);
      expect(frame[0], hasLength(4));
      // Painted range takes the group color; the rest falls to base.
      expect(frame[0]![0], isNot(Colors.black));
      expect(frame[0]![1], isNot(Colors.black));
      expect(frame[0]![3], Colors.black);
    });

    test('device channel lengths win over the stored ledCount', () {
      final design = sampleDesign();
      final frame =
          frameFromCustomDesign(design, channelLengths: const {0: 12});
      expect(frame[0], hasLength(12));
    });
  });
}
