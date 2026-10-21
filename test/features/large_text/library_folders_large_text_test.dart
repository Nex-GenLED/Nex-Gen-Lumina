// +120 large-text slice, group 2: the Library folder cards. The two-column
// hero grid sized its cells by aspect ratio alone, which cut the name and
// the "Tap to explore" line at 320 pt even at 1.0x and by 37 px at 2.0x.
// The cell now grows to what its two text lines need at the current scale
// and keeps today's height wherever that already fits.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/wled/pattern_theme_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/large_text_matrix.dart';
import '../../helpers/recording_wled_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Library root folders: no overflow across the matrix',
      (tester) async {
    await expectNoOverflowAcrossLargeTextMatrix(
      tester,
      () => largeTextHost(
        overrides: [
          ...homeDashboardOverrides(repo: RecordingWledRepository()),
          designsStreamProvider
              .overrideWith((ref) => Stream.value(const <CustomDesign>[])),
          authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
        ],
        page: const LibraryBrowserScreen(nodeId: null),
        dock: 2,
      ),
      label: 'library/folders',
      frames: 6,
      settle: const Duration(milliseconds: 1800),
    );
  });
}
