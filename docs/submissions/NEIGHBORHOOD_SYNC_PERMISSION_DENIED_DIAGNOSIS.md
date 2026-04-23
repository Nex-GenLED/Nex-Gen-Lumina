# Neighborhood Sync — "Permission denied" Diagnosis

**Date:** 2026-04-23
**Reporter:** Tyler
**Symptom:** Tapping "Create Group" (or similar) on the Neighborhood Sync landing page produces a generic "Permission denied" error. Pattern selection, sync code, and subsequent screens are never reached.

---

## TL;DR

The client code, model serialization, and `firestore.rules` file in the repo are **all correct**. The error Tyler is seeing is the raw `[cloud_firestore/permission-denied] Missing or insufficient permissions.` string being surfaced in a `SnackBar` by the dialog's `catch (e)` block.

The overwhelmingly most likely root cause is that **the `/neighborhoods` rules in `firestore.rules` have not been deployed to the live Firebase project** (project id `icrt6menwsv2d8all8oijs021b06s5`). Firestore defaults to `deny` when no rule matches. The rules were added to the repo on `2026-04-07` (commit `c75ca3e`) and last edited on `2026-04-16`, but nothing in the repo indicates an automated `firebase deploy --only firestore:rules` has run. There is no CI deploy step in `codemagic.yaml` for rules.

**Fix:** run `firebase deploy --only firestore:rules` against the active project, or open the Firebase Console and paste the current `firestore.rules` contents into the Rules tab. No code change needed.

---

## STEP 1 — Feature code layout

Primary directory: [lib/features/neighborhood/](lib/features/neighborhood/)

| Role | File |
| --- | --- |
| Main screen / landing page | [lib/features/neighborhood/neighborhood_sync_screen.dart](lib/features/neighborhood/neighborhood_sync_screen.dart) |
| Firestore service (CRUD) | [lib/features/neighborhood/neighborhood_service.dart](lib/features/neighborhood/neighborhood_service.dart) |
| Models (`NeighborhoodGroup`, `NeighborhoodMember`, `SyncCommand`, `SyncSchedule`) | [lib/features/neighborhood/neighborhood_models.dart](lib/features/neighborhood/neighborhood_models.dart) |
| Riverpod providers + `NeighborhoodNotifier` | [lib/features/neighborhood/neighborhood_providers.dart](lib/features/neighborhood/neighborhood_providers.dart) |
| Client-side pattern execution engine | [lib/features/neighborhood/neighborhood_sync_engine.dart](lib/features/neighborhood/neighborhood_sync_engine.dart) |
| Onboarding (4 page walkthrough shown to brand-new users) | [lib/features/neighborhood/widgets/neighborhood_onboarding.dart](lib/features/neighborhood/widgets/neighborhood_onboarding.dart) |
| Controls bottom sheet | [lib/features/neighborhood/widgets/sync_control_panel.dart](lib/features/neighborhood/widgets/sync_control_panel.dart) |
| Member roster reorder UI | [lib/features/neighborhood/widgets/member_position_list.dart](lib/features/neighborhood/widgets/member_position_list.dart) |
| Game Day autopilot setup | [lib/features/neighborhood/widgets/game_day_setup_screen.dart](lib/features/neighborhood/widgets/game_day_setup_screen.dart) |
| Schedules, sessions, handoff, celebration, notifications | [lib/features/neighborhood/services/](lib/features/neighborhood/services/) |

---

## STEP 2 — Landing page entry point

File: [lib/features/neighborhood/neighborhood_sync_screen.dart](lib/features/neighborhood/neighborhood_sync_screen.dart)
Widget: `NeighborhoodSyncScreen` (ConsumerStatefulWidget, line 24)

Reads performed on build (lines 33–61):

- `ref.watch(syncEngineControllerProvider)` — activates the listener; does **no** Firestore reads by itself.
- `ref.watch(userNeighborhoodsProvider)` — a `StreamProvider` that calls [neighborhood_service.dart:403 `watchUserGroups()`](lib/features/neighborhood/neighborhood_service.dart#L403). The stream runs:
  ```dart
  _firestore.collection('neighborhoods')
      .where('memberUids', arrayContains: uid)
      .snapshots()
  ```
- `ref.watch(neighborhoodSyncOnboardingCompleteProvider)` — `SharedPreferences` only; no Firestore.

If `groupsAsync.hasError`, a dismissible banner "Couldn't load your crews. Tap to retry." is rendered (line 97). The banner is an info hint — it is **not** the "Permission denied" text Tyler is seeing.

"Create Group" entry points, all of which call `_showCreateGroupDialog()` at line 174:
- [:74](lib/features/neighborhood/neighborhood_sync_screen.dart#L74) — `onCreateGroup` callback on `_NeighborhoodGroupListView` (returning-user path).
- [:87–90](lib/features/neighborhood/neighborhood_sync_screen.dart#L87) — `NeighborhoodOnboarding`'s "Create" CTA (new-user path).
- [:168](lib/features/neighborhood/neighborhood_sync_screen.dart#L168) — "Create Crew" button inside the `_GroupControlsSheet` bottom sheet.
- [:1086](lib/features/neighborhood/neighborhood_sync_screen.dart#L1086), [:1174](lib/features/neighborhood/neighborhood_sync_screen.dart#L1174), [:1652](lib/features/neighborhood/neighborhood_sync_screen.dart#L1652), [:1654](lib/features/neighborhood/neighborhood_sync_screen.dart#L1654) — extra call sites for the list-view / empty-state / group-list bottom buttons, all calling `widget.onCreateGroup` which resolves back to `_showCreateGroupDialog`.

`_showCreateGroupDialog` (line 174) opens `_CreateGroupDialog`, whose `_createGroup()` at [:2179](lib/features/neighborhood/neighborhood_sync_screen.dart#L2179) runs the actual Firestore writes.

---

## STEP 3 — "Create Group" handler → Firestore writes

Chain: button → `_CreateGroupDialog._createGroup()` ([neighborhood_sync_screen.dart:2179](lib/features/neighborhood/neighborhood_sync_screen.dart#L2179)) → `NeighborhoodNotifier.createGroup()` ([neighborhood_providers.dart:113](lib/features/neighborhood/neighborhood_providers.dart#L113)) → `NeighborhoodService.createGroup()` ([neighborhood_service.dart:33](lib/features/neighborhood/neighborhood_service.dart#L33)).

The service performs **two writes** in sequence:

### Write 1 — group document
- **Path:** `/neighborhoods/{autoId}`
- **Method:** `DocumentReference.set(payload)`
- **Fields written** (from `NeighborhoodGroup.toFirestore()` at [neighborhood_models.dart:183](lib/features/neighborhood/neighborhood_models.dart#L183), then passed through `UserService.sanitizeForFirestore` which strips top-level nulls):
  - `name` — string
  - `inviteCode` — string (6-char `_generateInviteCode`)
  - `creatorUid` — string (`FirebaseAuth.instance.currentUser!.uid`)
  - `createdAt` — `Timestamp`
  - `memberUids` — `[uid]` (list with one element, always the creator)
  - `isPublic` — bool (dialog default `false`)
  - `isActive` — bool (`false` on create)
  - `activeSyncType` — string (serialized enum, default `sequentialFlow`)
  - Optional and may be stripped by `sanitizeForFirestore` when null: `description`, `streetName`, `city`, `latitude`, `longitude`, `activePatternId`, `activePatternName`.

### Write 2 — creator's member subdoc
- **Path:** `/neighborhoods/{groupId}/members/{uid}`
- **Method:** `CollectionReference.doc(uid).set(payload)`
- **Fields written** (from `NeighborhoodMember.toFirestore()`):
  - `displayName` — `displayName` arg or `'My Home'`
  - `positionIndex` — `0`
  - `lastSeen` — `Timestamp`
  - `isOnline` — `true`
  - plus defaults for `ledCount`, `participationStatus`, etc.

If Write 2 throws, Write 1 is **rolled back** via `docRef.delete()` ([neighborhood_service.dart:103–106](lib/features/neighborhood/neighborhood_service.dart#L103)).

Neither write touches `/users/{uid}`, `/installations/…`, or any other collection. There is no third "register me as a group member" doc under the user's own tree — the feature is entirely scoped to `/neighborhoods/…`.

---

## STEP 4 — Error handling path (where "Permission denied" surfaces)

Three nested try/catch layers. In order:

### Layer 1 — `NeighborhoodService.createGroup` ([neighborhood_service.dart:79–107](lib/features/neighborhood/neighborhood_service.dart#L79))
Each write is wrapped individually. Every `catch (e, st)` **logs the full error + stack via `debugPrint`** with the prefix `🏘️ [NeighborhoodService]`, then **rethrows**:
```dart
debugPrint('🏘️ [NeighborhoodService] Group doc write FAILED: $e');
debugPrint('🏘️ [NeighborhoodService] Stack: $st');
rethrow;
```
Exception type is dynamic (`catch (e, st)`), which for a rules rejection will be `FirebaseException` with `code == 'permission-denied'`.

### Layer 2 — `NeighborhoodNotifier.createGroup` ([neighborhood_providers.dart:125–147](lib/features/neighborhood/neighborhood_providers.dart#L125))
```dart
} catch (e, st) {
  debugPrint('🏘️ [NeighborhoodNotifier] createGroup FAILED: $e');
  debugPrint('🏘️ [NeighborhoodNotifier] Stack: $st');
  state = AsyncValue.error(e, st);
  return null;
}
```
The notifier **stores the full error and stack in its AsyncValue state** and returns `null`.

### Layer 3 — `_CreateGroupDialog._createGroup` ([neighborhood_sync_screen.dart:2251–2295](lib/features/neighborhood/neighborhood_sync_screen.dart#L2251))
Two branches both surface the error:
- When the notifier returns `null`:
  ```dart
  final errorMsg = notifierState.hasError
      ? 'Could not create your crew: ${notifierState.error}'
      : 'Could not create your crew. Please try again.';
  ```
- When an exception bubbles past the notifier (rethrow path):
  ```dart
  } catch (e, stack) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not create your crew: $e'),
        ...
      ),
    );
  }
  ```

**Conclusion:** the exception is **not swallowed**. `debugPrint` logs the full error at every layer (visible in `flutter logs` or `adb logcat -s flutter`). The `SnackBar` shows the toString of the `FirebaseException`, which for the rules rejection looks like:
> `Could not create your crew: [cloud_firestore/permission-denied] The caller does not have permission to execute the specified operation.`

Tyler is seeing "Permission denied" because **that is literally the Firestore error** — not a generic shim. The full error.code and a stack trace are already in the debug console; have Tyler run `adb logcat -s flutter | grep 🏘️` or `flutter logs` while reproducing to capture the raw logs.

---

## STEP 5 — Firestore security rules (from the repo)

File: [firestore.rules](firestore.rules). Deployed via `firebase deploy --only firestore:rules` per `firebase.json` (`"firestore": {"rules": "firestore.rules", …}`).

### Rules for `/neighborhoods/{groupId}` ([firestore.rules:662–754](firestore.rules#L662))
```
function isGroupMember() {
  return request.auth != null &&
         resource != null &&
         request.auth.uid in resource.data.memberUids;
}

function isGroupCreator() {
  return request.auth != null &&
         resource != null &&
         resource.data.creatorUid == request.auth.uid;
}

allow read:   if request.auth != null;
allow create: if request.auth != null &&
                 request.resource.data.creatorUid == request.auth.uid &&
                 request.auth.uid in request.resource.data.memberUids;
allow update: if request.auth != null && (
                 isGroupCreator() ||
                 isGroupMember() ||
                 request.auth.uid in request.resource.data.memberUids
               );
allow delete: if isGroupCreator();
```

### Rules for `/neighborhoods/{groupId}/members/{memberUid}` ([firestore.rules:707–723](firestore.rules#L707))
```
allow read: if request.auth != null;
allow create, update: if request.auth != null && (
  request.auth.uid == memberUid ||
  get(/databases/$(database)/documents/neighborhoods/$(groupId)).data.creatorUid == request.auth.uid
);
allow delete: if ...same condition...;
```

### Rules for `/users/{uid}` ([firestore.rules:85–105](firestore.rules#L85))
Landing page does not read `/users/{uid}`, so these are not relevant to this bug.

### Other neighborhood subcollections ([firestore.rules:725–753](firestore.rules#L725))
`commands`, `schedules`, `syncEvents`, `syncSessions`, `game_day_autopilot` all use:
```
allow read: if request.auth != null;
allow create, update, delete: if request.auth != null;
```
These are not written during the create flow, so they don't affect the initial failure.

**Every rule on the create path is in place and correctly worded against what the client sends.**

---

## STEP 6 — Rules vs. queries, operation-by-operation

Assume a signed-in user (`request.auth.uid` set, no pre-existing membership anywhere).

| # | Operation | Rule path | Expected result against repo rules |
| -- | --------- | --------- | ---------------------------------- |
| 1 | Landing page stream `where('memberUids', arrayContains: uid).snapshots()` | `match /neighborhoods/{groupId} → allow read` (`request.auth != null`) | ✅ pass |
| 2 | `docRef.set(groupPayload)` at `/neighborhoods/{autoId}` | `match /neighborhoods/{groupId} → allow create` — requires `request.resource.data.creatorUid == request.auth.uid` (client sends `uid`) and `request.auth.uid in request.resource.data.memberUids` (client sends `[uid]`) | ✅ pass |
| 3 | `docRef.collection('members').doc(uid).set(...)` at `/neighborhoods/{groupId}/members/{uid}` | `match /members/{memberUid} → allow create` — requires `request.auth.uid == memberUid` (they match, both are `uid`) | ✅ pass |

Every operation passes under the rules as written in the repo.

If Tyler is hitting a permission-denied error against a signed-in account, then **the rules being evaluated by Firestore are not the rules in this repo.** The first operation to fail under "no rule matches → deny" would be **Operation 2 (group create)** — which matches the reported UX: the landing page renders (stream read permitted even without the specific rule, as long as the pre-rules state is more open, but that's speculative), the user taps Create, the create is rejected, the SnackBar shows "Permission denied".

---

## STEP 7 — Root cause hypothesis

**Best assessment: category (d), with a specific twist.**

> *(d) Rule is overly strict (e.g., deny all writes, rule was never written for the create path)* — specifically, **the rules as written in this repo have not been deployed to the live Firebase project.**

Evidence:

1. **Repo rules are correct.** Every condition (`creatorUid == auth.uid`, `uid in memberUids`, member-doc-matching-creator) matches exactly what the client sends.
2. **The rules were only recently committed.** Commit `c75ca3e` on `2026-04-07` added them with the message *"add missing Firestore rules for /neighborhoods (Block Party silent write failure)"*. Before that commit, the `/neighborhoods` collection had **zero** rules and all writes were denied by default. The same commit added the verbose `debugPrint` logging and bumped the SnackBar duration to 8 seconds — which is why Tyler now sees a visible "Permission denied" message where previously the failure was silent.
3. **No automated deploy.** `codemagic.yaml` does not run `firebase deploy`. `firebase.json` only declares the rules file; it does not push it. Rules deployment requires a manual `firebase deploy --only firestore:rules` against project `icrt6menwsv2d8all8oijs021b06s5`, or pasting the file into the Firebase Console.
4. **No build-time rule bundling** that would cause client ↔ server drift.
5. **Pattern precedent.** The repo history shows the same silent-write bug was fixed for `/game_day_autopilot` (commit `7e5f0e6`), `/app_config` (`8ce73ab`), `/properties` (`098a7c1`), `/controllers` (`294c870`, `a8ce314`), and `/commands` (`bc7eec8`) — each required both a code change **and** a rules deploy. This is clearly a recurring rough edge.

### Secondary hypothesis (lower likelihood)

If a `firebase deploy --only firestore:rules` has in fact been run since `2026-04-16` and the error still happens, the next-most-likely candidate is **category (c): the `sanitizeForFirestore` helper in [lib/services/user_service.dart](lib/services/user_service.dart#L83) is stripping a field the rule depends on.** Inspection of the helper shows it only strips `null` top-level entries, and neither `creatorUid` nor `memberUids` can be null at the point of the write (both are populated from a non-null `uid` one line earlier). This would still be worth re-checking as a sanity pass if the deploy theory is ruled out.

---

## Recommended remediation path (no code change required)

1. Verify the currently deployed rules against the repo:
   ```bash
   firebase firestore:rules:get --project icrt6menwsv2d8all8oijs021b06s5
   ```
   Compare the output to [firestore.rules](firestore.rules). If the `/neighborhoods` block is missing or differs, proceed.
2. Deploy:
   ```bash
   firebase deploy --only firestore:rules --project icrt6menwsv2d8all8oijs021b06s5
   ```
3. Reproduce in-app. While the dialog is open, tail logs with `flutter logs` or `adb logcat -s flutter` and grep for `🏘️` — if writes now succeed, the prefixed success lines appear in sequence and the "Couldn't create your crew" SnackBar never fires.
4. If permission-denied persists after a confirmed deploy, dump the actual payload by adding one more line in [neighborhood_service.dart:75](lib/features/neighborhood/neighborhood_service.dart#L75) — `debugPrint('full payload: $groupPayload')` — and compare each key/value to what the rule requires. At that point, the failure mode shifts from "rule never deployed" (category d) to "payload field mismatch" (category c).
