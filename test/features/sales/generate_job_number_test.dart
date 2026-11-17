import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';

/// generateJobNumber's count must be scoped to the session's dealer.
///
/// The sales_jobs read rule admits a sales or installer PIN session only
/// through `hasStaffClaim(resource.data.dealerCode)` (isJobStakeholder in
/// firestore.rules). For a list or count query Firestore can prove that arm
/// only when the query itself carries `dealerCode == <the claim>`. The old
/// count filtered on createdAt alone, so it was denied for every sales and
/// installer PIN, `_ensureDraftJob` threw before the draft was written, and
/// "New Visit" failed.
///
/// The fake does not enforce rules, so these tests pin the query SHAPE the
/// rule needs: the dealer filter (by behaviour: another dealer's jobs must
/// not be counted) and the createdAt-descending order that matches the
/// deployed composite index (dealerCode ASC, createdAt DESC).
void main() {
  // A fixed local "now" so the day window is deterministic.
  final now = DateTime(2026, 11, 17, 14, 30);

  Future<void> seedJob(
    FakeFirebaseFirestore db,
    String id, {
    required String dealerCode,
    required DateTime createdAt,
  }) =>
      db.collection('sales_jobs').doc(id).set({
        'id': id,
        'dealerCode': dealerCode,
        'status': 'draft',
        'createdAt': Timestamp.fromDate(createdAt),
      });

  test('counts only the session dealer\'s jobs created today', () async {
    final db = FakeFirebaseFirestore();
    await seedJob(db, 'a1', dealerCode: '01', createdAt: DateTime(2026, 11, 17, 9));
    await seedJob(db, 'a2', dealerCode: '01', createdAt: DateTime(2026, 11, 17, 13));
    // Another dealer, same day: must not advance dealer 01's sequence.
    await seedJob(db, 'b1', dealerCode: '02', createdAt: DateTime(2026, 11, 17, 10));
    await seedJob(db, 'b2', dealerCode: '02', createdAt: DateTime(2026, 11, 17, 11));
    // Same dealer, yesterday: outside the day window.
    await seedJob(db, 'a0', dealerCode: '01', createdAt: DateTime(2026, 11, 16, 23, 59));

    final n01 = await generateJobNumber(dealerCode: '01', firestore: db, now: now);
    final n02 = await generateJobNumber(dealerCode: '02', firestore: db, now: now);
    final n03 = await generateJobNumber(dealerCode: '03', firestore: db, now: now);

    expect(n01, 'NXG-20261117-003');
    expect(n02, 'NXG-20261117-003');
    expect(n03, 'NXG-20261117-001');
  });

  test('the count query carries the dealer filter and the index order', () async {
    final db = FakeFirebaseFirestore();
    await seedJob(db, 'b1', dealerCode: '02', createdAt: DateTime(2026, 11, 17, 10));

    final q = jobNumberCountQuery(db, dealerCode: '01', now: now);

    // Dealer filter, by behaviour: dealer 02's job is invisible to it.
    expect((await q.get()).docs, isEmpty);
    expect((await q.count().get()).count, 0);

    // Order: createdAt descending, so the query is served by the deployed
    // (dealerCode ASC, createdAt DESC) composite index.
    expect(q.parameters['orderedBy'], ['createdAt']);
    expect(q.parameters['orderedByDirection'], [true]);
  });
}
