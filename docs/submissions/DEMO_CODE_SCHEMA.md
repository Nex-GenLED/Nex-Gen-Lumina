# Demo Code Firestore Schema

**Purpose:** Tyler needs to manually create demo code documents in the Firebase Console (no admin UI exists). This document is the exact schema contract the validator enforces.

---

## 1. Validator behavior — [lib/services/demo_code_service.dart](lib/services/demo_code_service.dart)

### (a) Collection

**`dealer_demo_codes`** (top-level, snake_case with underscores). Confirmed at [demo_code_service.dart:26](lib/services/demo_code_service.dart#L26).

### (b) Field names (camelCase — not snake_case, unlike the rest of the app's user-facing schemas)

| Field | Type | Required | Semantics |
|---|---|---|---|
| `code` | `string` | ✅ | The code string the user types. Must match after input normalization (see Query section). |
| `dealerCode` | `string` | ✅ | Short dealer id (e.g. `'01'`). Used for attribution downstream. |
| `dealerName` | `string` | ✅ | Display name (e.g. `'Nex-Gen LED Kansas City'`). |
| `market` | `string` | ✅ | Market label (e.g. `'Kansas City'`). Also accepts capitalized `Market` as a fallback at [dealer_demo_code.dart:32](lib/models/dealer_demo_code.dart#L32) — defaults to empty string if both missing. |
| `isActive` | `bool` | ✅ (must be `true`) | Must equal `true` — the `.where('isActive', isEqualTo: true)` clause filters on this server-side. |
| `usageCount` | `int` | ✅ (default `0`) | Monotonically incremented every time the code validates successfully. |
| `maxUses` | `int` \| `null` | optional | If `null`, unlimited uses. If set, the validator rejects the code once `usageCount >= maxUses`. |
| `createdAt` | `Timestamp` | ✅ | When the code was created. Informational only — validator doesn't compare against it. Also accepts an ISO-8601 string per [dealer_demo_code.dart:38](lib/models/dealer_demo_code.dart#L38) but `Timestamp` is canonical. |
| `expiresAt` | `Timestamp` \| `null` | optional | If `null`, never expires. If set, code is rejected once `expiresAt < now`. |

### (c) How the query matches input

**Query type:** compound `.where()` on two fields, **not** `.doc(code).get()`. [demo_code_service.dart:25-30](lib/services/demo_code_service.dart#L25-L30):

```dart
await FirebaseFirestore.instance
    .collection('dealer_demo_codes')
    .where('code', isEqualTo: normalized)
    .where('isActive', isEqualTo: true)
    .limit(1)
    .get();
```

**Input normalization** at [demo_code_service.dart:23](lib/services/demo_code_service.dart#L23):
```dart
final normalized = code.trim().toUpperCase();
```

→ The `code` field value in Firestore **must be uppercase** (e.g. `KC2026`, not `kc2026`), and must have no surrounding whitespace. Otherwise the `.where('code', isEqualTo: ...)` will miss.

**Doc ID is arbitrary.** The validator doesn't read the document ID — it queries on the `code` field inside the doc. You can use any doc ID (auto-generated fine; or use the code itself as the ID for easier Console inspection, but not required).

**Composite index requirement:** Firestore needs a composite index on `(code ASC, isActive ASC)` for this query. Firebase console will surface a "create index" error the first time the query runs if the index is missing — follow the link. Or pre-create at Firebase Console → Firestore → Indexes.

### (d) Valid vs rejected

A code passes validation when **all four** of the following are true:
1. A doc exists where `code == normalized_input`
2. That doc has `isActive == true`
3. `expiresAt == null` **OR** `expiresAt > now` (server-local clock — see [demo_code_service.dart:40-43](lib/services/demo_code_service.dart#L40-L43))
4. `maxUses == null` **OR** `usageCount < maxUses` ([demo_code_service.dart:46-49](lib/services/demo_code_service.dart#L46-L49))

A code is rejected (returns `null` → user sees "Invalid code — ask your Nex-Gen specialist for a valid code" shake animation) when any of:
- No matching doc (`code` value doesn't match, or `isActive == false` — filtered at query time)
- Matching doc exists but `expiresAt` is past
- Matching doc exists but `usageCount >= maxUses`

**Side effect on successful validation:** [demo_code_service.dart:52-54](lib/services/demo_code_service.dart#L52-L54) — fire-and-forget `usageCount: FieldValue.increment(1)` on the matched doc. Not awaited — the user is allowed through before the increment commits, so rapid-fire logins could under-count. Acceptable for demo-gating purposes.

---

## 2. Write / read sites across the codebase

### Writes to `dealer_demo_codes`

**None.** No admin UI, no installer wizard, no script writes to this collection.

Grep results for `dealer_demo_codes` across `lib/` return only:
- [demo_code_service.dart:1, 20, 26](lib/services/demo_code_service.dart#L1) — the single reader (validator)

There is no dealer dashboard, admin panel, or CLI seeding tool in the codebase that creates these docs. **Tyler must create them manually in the Firebase Console** (or via a one-off Admin SDK script outside this repo).

### Reads from `dealer_demo_codes`

Single reader: `DemoCodeService.validateCode()`.

### `DealerDemoCode` model references (consumers of the validated result)

| File:line | Use |
|---|---|
| [lib/models/dealer_demo_code.dart](lib/models/dealer_demo_code.dart) | Model definition (fromJson, toJson, copyWith) |
| [lib/services/demo_code_service.dart:22, 37](lib/services/demo_code_service.dart#L22) | Validator |
| [lib/features/demo/demo_code_screen.dart:15, 62-63](lib/features/demo/demo_code_screen.dart#L15) | Entry screen + `validatedDemoCodeProvider` state holder passed downstream to demo flow |

### Fixture / seed / test data

**None.** Grep for `demo_codes`, `dealer_demo`, `demoCode` across `assets/` returned no matches. No JSON fixtures, no CSV, no test data file.

---

## Minimum viable doc to create in Firebase Console

Collection: **`dealer_demo_codes`** · Doc ID: any (suggest using the code itself, e.g. `KC2026`)

```javascript
{
  code: "KC2026",
  dealerCode: "01",
  dealerName: "Nex-Gen LED Kansas City",
  market: "Kansas City",
  isActive: true,
  usageCount: 0,
  createdAt: <Timestamp: now>
  // omit maxUses and expiresAt entirely (not the string "null" —
  // just don't add the fields) to get unlimited uses / no expiry
}
```

**Gotchas:**
- Field names are camelCase (`dealerCode`, `isActive`, `usageCount`) — **not** snake_case. Different convention from the user-profile schema which uses snake_case. Don't mix them up.
- `code` must be uppercase in the stored doc — user input is `.toUpperCase()`d before the query, so `kc2026` in Firestore won't match even if the user types exactly `kc2026`.
- `createdAt` must be a Timestamp value (use the Firebase Console's timestamp picker, not the text field).
- `isActive` must be `true` (boolean) — the string `"true"` won't match.

## If the composite index is missing

First-time validation will fail with a Firestore `failed-precondition` error and a link like `https://console.firebase.google.com/project/icrt6menwsv2d8all8oijs021b06s5/firestore/indexes?create_composite=...`. Click that link and let Firebase create the `(code ASC, isActive ASC)` composite index. Takes ~30 seconds to build on an empty collection.
