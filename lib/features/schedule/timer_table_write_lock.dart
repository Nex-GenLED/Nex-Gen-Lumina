// Build 133 — one lock for every read-modify-write of the controller's timer
// table.
//
// The lease manager reads the table back, swaps its own rows and writes the
// result; the schedule sync reads the table back too (to keep rows it could
// not rebuild) and writes a whole new one. Each is correct alone. Interleaved,
// the second writer sends a table built from a read taken BEFORE the first
// writer's write — so a sweep could put back the rows a schedule sync had just
// replaced, or a sync could put back a lease row a sweep had just cleared.
//
// Both now take this lock: the lease manager as its `_wledWriteLock`, the
// schedule sync around `syncAll`. It is not re-entrant, so nothing that runs
// while holding it may wait on the other holder (see the call sites).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/utils/async_lock.dart';

final timerTableWriteLockProvider = Provider<AsyncLock>((ref) => AsyncLock());
