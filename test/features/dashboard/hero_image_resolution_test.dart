// #80 — THE PINNED TEST. Three states, three outcomes, no collapse.
//
// The bug was that two of the three collapsed into one: a Riverpod
// loading-with-previous-value state and an affirmative "this user has no
// photo" both arrived at the assignment as `null`, so a momentary refresh
// committed the STOCK house over the customer's own home photo.
//
// These assert the DISCRIMINATOR, which is the layer the defect lived at.
// `hasValue` is deliberately exercised as a trap: the loading-with-value case
// below has `hasValue == true`, and that is exactly the predicate the old
// guard used to admit the rebuild.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/dashboard/hero_image_resolution.dart';
import 'package:nexgen_command/models/user_model.dart';

UserModel _user({String? photo, Map<String, dynamic>? mask}) => UserModel(
      id: 'u1',
      email: 'a@b.c',
      displayName: 'Tyler',
      ownerId: 'u1',
      createdAt: DateTime.utc(2026, 8, 17),
      updatedAt: DateTime.utc(2026, 8, 17),
      housePhotoUrl: photo,
      rooflineMask: mask,
    );

void main() {
  group('#80 — resolveHeroImage never renders "unknown" as "absent"', () {
    test('STATE 1 — loading WITH a previous value → HOLD (provider untouched)',
        () {
      // The #80 state exactly. `activeUserProfileProvider` watches
      // viewAsCustomerIdProvider + authStateProvider, so a Game Day enable /
      // auth change / view-as change RE-CREATES the stream. Riverpod models
      // that as a RELOAD — copyWithPrevious(..., isRefresh: false) — which
      // keeps `hasValue` true while the runtime state is AsyncLoading.
      const loading = AsyncValue<UserModel?>.loading();
      final reloading = loading.copyWithPrevious(
        AsyncValue.data(_user(photo: 'https://cdn/tyler-house.jpg')),
        isRefresh: false,
      );

      // THE TRAP: the old guard read this as "loaded"…
      expect(reloading.hasValue, isTrue,
          reason: 'hasValue is true here — this is why the old guard admitted '
              'the rebuild');
      expect(reloading.isLoading, isTrue);
      // …while the value read it as "no photo". That disagreement IS #80.
      expect(reloading.maybeWhen(data: (u) => u?.housePhotoUrl, orElse: () => null),
          isNull,
          reason: 'the old read returned null on a state that HAS a photo');

      expect(resolveHeroImage(reloading), isA<HeroHold>(),
          reason: 'a reload must hold last-known-good, never assign stock');
    });

    test(
        'STATE 1b — a REFRESH that retains the value keeps rendering the '
        'photo (never stock)', () {
      // The other Riverpod flavour: copyWithPrevious(isRefresh: true) stays
      // AsyncData with isLoading true. The invariant is the same one that
      // matters — a user WITH a photo never resolves to stock mid-flight.
      final refreshing = const AsyncValue<UserModel?>.loading().copyWithPrevious(
        AsyncValue.data(_user(photo: 'https://cdn/tyler-house.jpg')),
      );
      expect(refreshing.isLoading, isTrue);
      final intent = resolveHeroImage(refreshing);
      expect(intent, isA<HeroPhoto>());
      expect(intent, isNot(isA<HeroStock>()));
    });

    test(
        'THE INVARIANT — a user WITH a photo NEVER resolves to stock, in any '
        'unresolved state', () {
      final data = AsyncValue.data(_user(photo: 'https://cdn/tyler-house.jpg'));
      final states = <AsyncValue<UserModel?>>[
        const AsyncValue<UserModel?>.loading(),
        const AsyncValue<UserModel?>.loading()
            .copyWithPrevious(data, isRefresh: false),
        const AsyncValue<UserModel?>.loading().copyWithPrevious(data),
        AsyncValue<UserModel?>.error(StateError('x'), StackTrace.empty),
        AsyncValue<UserModel?>.error(StateError('x'), StackTrace.empty)
            .copyWithPrevious(data, isRefresh: false),
        data,
      ];
      for (final s in states) {
        expect(resolveHeroImage(s), isNot(isA<HeroStock>()),
            reason: 'stock over a real photo is the whole defect — state $s');
      }
    });

    test('STATE 2 — loaded profile AFFIRMATIVELY reports no photo → STOCK', () {
      expect(resolveHeroImage(AsyncValue.data(_user(photo: null))),
          isA<HeroStock>());
      expect(resolveHeroImage(AsyncValue.data(_user(photo: ''))),
          isA<HeroStock>(),
          reason: 'empty string is absence, same as null');
      expect(
          resolveHeroImage(const AsyncValue<UserModel?>.data(null)),
          isA<HeroStock>(),
          reason: 'a resolved null profile is a resolved absence');
    });

    test('STATE 3 — genuine data WITH a photo → PHOTO (url + mask identity)',
        () {
      final intent = resolveHeroImage(AsyncValue.data(
        _user(photo: 'https://cdn/tyler-house.jpg', mask: const {'v': 2}),
      ));
      expect(intent, isA<HeroPhoto>());
      expect((intent as HeroPhoto).url, 'https://cdn/tyler-house.jpg');
      expect(intent.maskVersion, isNotNull,
          reason: 'mask version rides the cache identity so a re-trace '
              're-resolves the image');
    });

    test('a cold first load (loading, NO previous value) → HOLD, not stock',
        () {
      // Nothing resolved yet: the matte-black interim is correct. Painting
      // stock here is the same lie, just before the customer has a photo.
      expect(resolveHeroImage(const AsyncValue<UserModel?>.loading()),
          isA<HeroHold>());
    });

    test('an errored profile stream → HOLD (an error is not "no photo")', () {
      final errored =
          AsyncValue<UserModel?>.error(StateError('stream died'), StackTrace.empty);
      expect(resolveHeroImage(errored), isA<HeroHold>());

      // And with a previous value, it must still hold that value's render.
      final erroredWithPrev = errored.copyWithPrevious(
        AsyncValue.data(_user(photo: 'https://cdn/tyler-house.jpg')),
      );
      expect(resolveHeroImage(erroredWithPrev), isA<HeroHold>());
    });

    test(
        'THE COLLAPSE, restated: the refresh state and the no-photo state must '
        'NOT produce the same intent', () {
      final reloading = const AsyncValue<UserModel?>.loading().copyWithPrevious(
        AsyncValue.data(_user(photo: 'https://cdn/tyler-house.jpg')),
        isRefresh: false,
      );
      final affirmativelyNoPhoto = AsyncValue.data(_user(photo: null));

      final a = resolveHeroImage(reloading);
      final b = resolveHeroImage(affirmativelyNoPhoto);

      expect(a.runtimeType, isNot(b.runtimeType),
          reason: 'these two used to be indistinguishable — both arrived as a '
              'null url and both rendered the stock house');
      expect(a, isA<HeroHold>());
      expect(b, isA<HeroStock>());
    });
  });
}
