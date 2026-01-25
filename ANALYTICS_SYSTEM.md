# Lumina Analytics System - Implementation Guide

## Overview

The Lumina Analytics System is a privacy-preserving platform for tracking pattern trends, user preferences, and community feedback across all Lumina users. This system helps identify popular patterns, discover gaps in the pattern library, and inform product development decisions.

## Key Features

### 1. Privacy-First Design
- **Hashed User IDs**: All user identifiers are SHA-256 hashed before storage
- **No PII Storage**: Only anonymized pattern usage data is stored
- **Opt-In by Default**: Users can disable analytics in Settings
- **Transparent**: Users are informed about data collection and usage

### 2. Global Analytics Collections
- **Pattern Statistics**: Track popularity, growth trends, and user adoption
- **Color Trends**: Identify popular colors and color combinations
- **Effect Popularity**: Understand which WLED effects are most used
- **Pattern Requests**: Community-driven pattern library expansion

### 3. Real-Time Insights
- **Trending Patterns**: View top 10 most-used patterns
- **Emerging Patterns**: Identify new patterns with high growth rates
- **Community Requests**: See and vote on requested patterns
- **Pattern Feedback**: User ratings and comments

---

## Architecture

### Data Models
**Location**: `lib/models/analytics_models.dart`

#### GlobalPatternStats
Aggregated statistics for each pattern across all users:
```dart
class GlobalPatternStats {
  final String patternId;
  final String patternName;
  final int totalApplications;
  final int uniqueUsers;
  final double avgWeeklyApplications;
  final double last30DaysGrowth;  // 0.0 - 1.0 (0% - 100%)
  final List<List<int>>? colorPalette;
  final int? effectId;

  // Calculated properties
  double get trendingScore;  // Higher = more trending
  bool get isTrending;       // > 20% growth
  bool get isNew;            // < 30 days old
}
```

#### PatternRequest
Community-submitted pattern requests:
```dart
class PatternRequest {
  final String requestedTheme;
  final String? description;
  final List<String>? suggestedColors;
  final String? suggestedCategory;
  final int voteCount;
  final bool fulfilled;
}
```

#### PatternFeedback
User feedback on patterns:
```dart
class PatternFeedback {
  final String patternName;
  final int rating;  // 1-5 stars
  final String? comment;
  final bool saved;  // Did user save to favorites?
  final String? source;  // 'pattern_library', 'lumina_ai', etc.
}
```

---

## Core Services

### AnalyticsAggregator
**Location**: `lib/services/analytics_aggregator.dart`

Main service for contributing anonymized analytics to global collections.

#### Key Methods:

```dart
// Contribute pattern usage to global stats
await aggregator.contributePatternUsage(PatternUsageEvent event);

// Submit pattern feedback
await aggregator.submitPatternFeedback(
  patternName: 'Halloween Spooky',
  rating: 5,
  comment: 'Perfect for my front yard!',
  saved: true,
);

// Request a new pattern
await aggregator.requestPattern(
  requestedTheme: 'Lakers Purple & Gold',
  description: 'Need Lakers team colors for game nights',
  suggestedCategory: 'Sports',
);

// Vote for an existing request
await aggregator.voteForPatternRequest(requestId);

// Query trending patterns
List<GlobalPatternStats> trending = await aggregator.getTrendingPatterns(limit: 10);

// Stream real-time trends
Stream<List<GlobalPatternStats>> stream = aggregator.streamTrendingPatterns(limit: 10);
```

---

## Riverpod Providers

**Location**: `lib/features/analytics/analytics_providers.dart`

### State Providers

```dart
// User's analytics opt-in preference
final analyticsOptInProvider = StateProvider<bool>((ref) => true);

// Current user's analytics aggregator
final currentUserAnalyticsProvider = Provider<AnalyticsAggregator?>((ref) {...});
```

### Stream Providers

```dart
// Real-time trending patterns (top 10)
final trendingPatternsProvider = StreamProvider.autoDispose<List<GlobalPatternStats>>(...);

// Most requested patterns from community
final mostRequestedPatternsProvider = StreamProvider.autoDispose<List<PatternRequest>>(...);
```

### Notifiers

```dart
// Submit pattern feedback
final patternFeedbackNotifierProvider = AutoDisposeAsyncNotifierProvider<PatternFeedbackNotifier, void>(...);

// Request or vote on patterns
final patternRequestNotifierProvider = AutoDisposeAsyncNotifierProvider<PatternRequestNotifier, void>(...);
```

---

## Integration Guide

### Step 1: Analytics Already Integrated in Usage Logging

The analytics system is **already integrated** into the existing usage tracking. When you call:

```dart
ref.read(usageLoggerNotifierProvider.notifier).logUsage(
  source: 'pattern_library',
  patternName: 'Chiefs Game Day',
  effectId: 0,
  // ... other params
);
```

The system **automatically**:
1. Logs to user's personal usage history (existing behavior)
2. Contributes anonymized data to global analytics (NEW)

No additional code needed for basic analytics tracking!

### Step 2: Add Pattern Feedback UI

Show the feedback dialog after a user applies a pattern:

```dart
import 'package:nexgen_command/widgets/pattern_feedback_dialog.dart';

// After applying a pattern
await repo.applyJson(patternPayload);

// Optionally ask for feedback (don't show every time, maybe 10% of the time)
if (Random().nextDouble() < 0.1) {
  await PatternFeedbackDialog.show(
    context,
    patternName: 'Chiefs Game Day',
    source: 'pattern_library',
  );
}
```

### Step 3: Add "Request Pattern" Button

In your pattern library or explore screen:

```dart
import 'package:nexgen_command/widgets/pattern_request_dialog.dart';

// Add a button
TextButton.icon(
  onPressed: () => PatternRequestDialog.show(context),
  icon: Icon(Icons.add),
  label: Text('Can\'t find what you need? Request it!'),
)
```

### Step 4: Display Trending Patterns

Navigate to the trending patterns screen:

```dart
import 'package:go_router/go_router.dart';

// Add route in lib/nav.dart
GoRoute(
  path: '/trending',
  builder: (context, state) => const TrendingPatternsScreen(),
)

// Navigate from explore screen
IconButton(
  onPressed: () => context.push('/trending'),
  icon: Icon(Icons.trending_up),
  tooltip: 'Trending Patterns',
)
```

### Step 5: User Opt-In/Opt-Out

Users can control analytics in their profile:

1. Navigate to `/settings/profile`
2. Toggle "Contribute to Pattern Trends"
3. Setting is saved to `UserModel.analyticsEnabled`

**The analytics system automatically respects this setting** - if a user opts out, no analytics data is contributed.

---

## Firestore Schema

### Global Analytics Collections

#### `/analytics/global_pattern_stats/patterns/{patternId}`
```json
{
  "pattern_name": "chiefs_game_day",
  "total_applications": 1523,
  "effect_id": 0,
  "effect_name": "Solid",
  "last_updated": Timestamp
}
```

**Subcollection**: `/analytics/global_pattern_stats/patterns/{patternId}/users/{hashedUserId}`
```json
{
  "last_seen": Timestamp
}
```
*This tracks unique users without storing PII*

#### `/analytics/pattern_feedback/patterns/{patternId}`
```json
{
  "pattern_name": "chiefs_game_day",
  "total_ratings": 45,
  "total_stars": 198,  // Sum of all ratings
  "save_count": 32,
  "rating_distribution": {
    "stars_1": 1,
    "stars_2": 2,
    "stars_3": 5,
    "stars_4": 12,
    "stars_5": 25
  }
}
```

**Subcollection**: `/analytics/pattern_feedback/patterns/{patternId}/raters/{hashedUserId}`
```json
{
  "last_rated": Timestamp
}
```

#### `/analytics/pattern_requests/requests/{requestId}`
```json
{
  "requested_theme": "lakers_purple_gold",
  "description": "Need Lakers team colors for game nights",
  "suggested_category": "Sports",
  "created_at": Timestamp,
  "vote_count": 47,
  "fulfilled": false
}
```

**Subcollection**: `/analytics/pattern_requests/requests/{requestId}/voters/{hashedUserId}`
```json
{
  "voted_at": Timestamp
}
```

#### `/analytics/color_trends/weekly/{weekId}`
```json
{
  "week_of": Timestamp,
  "colors": {
    "red": 234,
    "gold": 189,
    "warm_white": 567,
    // ...
  }
}
```

#### `/analytics/effect_popularity/effects/effect_{effectId}`
```json
{
  "effect_id": 0,
  "effect_name": "Solid",
  "usage_count": 3421,
  "total_speed": 438720,  // Sum for calculating average
  "total_intensity": 438720,
  "last_updated": Timestamp
}
```

### User Personal Collections

#### `/users/{userId}/pattern_feedback/{feedbackId}`
```json
{
  "pattern_name": "chiefs_game_day",
  "rating": 5,
  "comment": "Perfect for my front yard!",
  "saved": true,
  "created_at": Timestamp,
  "source": "pattern_library"
}
```

*This is stored separately for the user's own records*

---

## Security Rules

**Location**: `firestore.rules`

Key security principles:

1. **Read Access**: All authenticated users can read global analytics (public data)
2. **Write Access**: Users can contribute stats via increment operations
3. **No PII Exposure**: User tracking uses hashed IDs in subcollections
4. **Rate Limiting**: Firestore's built-in rate limiting prevents abuse
5. **Validation**: All writes validate required fields

Example rule:
```javascript
match /analytics/global_pattern_stats/patterns/{patternId} {
  // Anyone can read trending patterns (public data)
  allow read: if request.auth != null;

  // Authenticated users can contribute stats (increment counters)
  allow create, update: if request.auth != null &&
    request.resource.data.keys().hasAll(['pattern_name', 'total_applications']);

  // No deletes (only Cloud Functions can clean up)
  allow delete: if false;
}
```

---

## UI Components

### PatternFeedbackDialog
**Location**: `lib/widgets/pattern_feedback_dialog.dart`

**Features**:
- 5-star rating system
- Optional text comment
- "Saved to favorites" checkbox
- Privacy notice
- Loading state handling

**Usage**:
```dart
await PatternFeedbackDialog.show(
  context,
  patternName: 'Halloween Spooky',
  source: 'lumina_ai',
);
```

### PatternRequestDialog
**Location**: `lib/widgets/pattern_request_dialog.dart`

**Features**:
- Theme/pattern name input
- Category selector (Holiday, Sports, etc.)
- Optional description
- Community voting notice

**Usage**:
```dart
await PatternRequestDialog.show(context);
```

### TrendingPatternsScreen
**Location**: `lib/features/analytics/trending_patterns_screen.dart`

**Tabs**:
1. **Trending**: Shows top 10 most-used patterns with growth indicators
2. **Requested**: Shows community pattern requests sorted by vote count

**Features**:
- Real-time updates via StreamProvider
- Rank badges (gold for top 3)
- Growth percentage indicators
- Vote buttons for pattern requests
- FAB to request new patterns

---

## Business Intelligence Queries

### Query 1: Top 10 Trending Patterns (This Week)

```dart
final patterns = await FirebaseFirestore.instance
  .collection('analytics')
  .doc('global_pattern_stats')
  .collection('patterns')
  .orderBy('total_applications', descending: true)
  .limit(10)
  .get();

for (var doc in patterns.docs) {
  final stats = GlobalPatternStats.fromFirestore(doc);
  print('${stats.patternName}: ${stats.totalApplications} uses, ${stats.uniqueUsers} users');
}
```

### Query 2: Fastest Growing Patterns (30 Days)

```dart
final patterns = await FirebaseFirestore.instance
  .collection('analytics')
  .doc('global_pattern_stats')
  .collection('patterns')
  .where('last_30_days_growth', isGreaterThan: 0.2)  // > 20% growth
  .orderBy('last_30_days_growth', descending: true)
  .limit(20)
  .get();
```

### Query 3: Most Requested Patterns

```dart
final requests = await FirebaseFirestore.instance
  .collection('analytics')
  .doc('pattern_requests')
  .collection('requests')
  .where('fulfilled', isEqualTo: false)
  .orderBy('vote_count', descending: true)
  .limit(20)
  .get();

for (var doc in requests.docs) {
  final request = PatternRequest.fromFirestore(doc);
  print('${request.requestedTheme}: ${request.voteCount} votes');
}
```

### Query 4: Highest Rated Patterns

```dart
final feedback = await FirebaseFirestore.instance
  .collection('analytics')
  .doc('pattern_feedback')
  .collection('patterns')
  .get();

// Calculate average rating
List<Map<String, dynamic>> ratingsData = [];
for (var doc in feedback.docs) {
  final data = doc.data();
  final avgRating = (data['total_stars'] as num) / (data['total_ratings'] as num);
  ratingsData.add({
    'pattern': data['pattern_name'],
    'avgRating': avgRating,
    'totalRatings': data['total_ratings'],
  });
}

ratingsData.sort((a, b) => (b['avgRating'] as double).compareTo(a['avgRating'] as double));
```

---

## Privacy & Compliance

### GDPR Compliance

1. **Consent**: Users opt-in via Settings (default: enabled, can be disabled)
2. **Transparency**: Clear messaging about what data is collected
3. **Anonymization**: All user IDs are hashed (SHA-256)
4. **Right to Access**: Users can see their own feedback in `/users/{uid}/pattern_feedback`
5. **Right to Delete**: Users can disable analytics anytime

### Data Retention

- **Usage Events**: 90 days (automatically cleaned up)
- **Global Stats**: Indefinite (aggregated, anonymized)
- **Pattern Requests**: Indefinite until fulfilled
- **Feedback**: Indefinite (aggregated, anonymized)

### What We Store

**✅ Stored**:
- Pattern names
- Effect IDs
- Color names
- Timestamps
- Hashed user IDs (for uniqueness)
- Rating scores
- Vote counts

**❌ NOT Stored**:
- Real user IDs (in global analytics)
- IP addresses
- Device information
- Location data
- Email addresses
- Names

---

## Performance Considerations

### Optimization Strategies

1. **Fire-and-Forget Analytics**: Analytics contribution doesn't block UI
   ```dart
   aggregator.contributePatternUsage(event).catchError((e) {
     // Silently fail - analytics should never block user experience
   });
   ```

2. **Batch Writes**: Use `FieldValue.increment()` to avoid read-modify-write cycles

3. **Indexes**: Required Firestore indexes:
   - `/analytics/global_pattern_stats/patterns` ordered by `total_applications`
   - `/analytics/pattern_requests/requests` composite: `fulfilled` + `vote_count`

4. **Caching**: StreamProviders automatically cache data in Riverpod

5. **Rate Limiting**: Client-side rate limiting prevents spam:
   - Max 1 feedback per pattern per user
   - Max 1 vote per request per user

---

## Testing

### Manual Testing

1. **Test Analytics Contribution**:
   ```dart
   // Apply a pattern
   await repo.applyJson(payload);

   // Wait 5 seconds
   await Future.delayed(Duration(seconds: 5));

   // Check Firestore Console
   // Navigate to: /analytics/global_pattern_stats/patterns/{patternId}
   // Verify: total_applications incremented
   ```

2. **Test Opt-Out**:
   - Go to Settings > My Profile
   - Disable "Contribute to Pattern Trends"
   - Apply a pattern
   - Verify: No new analytics data in Firestore

3. **Test Pattern Request**:
   - Open Trending screen
   - Tap "Request Pattern"
   - Submit request
   - Check: `/analytics/pattern_requests/requests/` has new entry

### Automated Testing (Future)

```dart
// Unit test example
test('AnalyticsAggregator hashes user IDs', () {
  final aggregator = AnalyticsAggregator(userId: 'test_user_123');
  final hashed = aggregator._hashUserId('test_user_123');

  expect(hashed.length, equals(64));  // SHA-256 hash length
  expect(hashed, isNot(contains('test_user_123')));  // Original ID not present
});
```

---

## Troubleshooting

### Problem: Analytics not being contributed

**Diagnosis**:
- Check if user has opted out in Settings > My Profile
- Verify `analyticsOptInProvider` returns `true`
- Check Firebase Console for errors

**Solution**:
```dart
// Debug log
final aggregator = ref.read(currentUserAnalyticsProvider);
print('Analytics enabled: ${aggregator != null}');
```

### Problem: Trending patterns not showing

**Diagnosis**:
- Check if Firestore rules allow read access
- Verify index exists for `total_applications`
- Check network connectivity

**Solution**:
- Rebuild Firestore indexes
- Check error in `trendingPatternsProvider`

### Problem: Vote button not working

**Diagnosis**:
- User may have already voted
- Check Firestore security rules
- Verify request ID is valid

**Solution**:
- Check subcollection: `/voters/{hashedUserId}`
- Verify `voteForPatternRequest` doesn't throw error

---

## Future Enhancements

### Phase 1: Advanced Analytics (Q2 2026)
- Geographic segmentation (city/region trends)
- Seasonal pattern analysis (Christmas patterns in December)
- Time-of-day preferences (evening vs morning patterns)
- Weather integration (cloudy day → brighter lights?)

### Phase 2: Machine Learning (Q3 2026)
- Pattern recommendation engine (users with your house style also like...)
- Anomaly detection (unusual pattern popularity spikes)
- Predictive trends (what will be popular next month?)
- Automatic pattern generation based on trends

### Phase 3: Community Features (Q4 2026)
- User-submitted patterns (with moderation)
- Pattern sharing between similar properties
- Leaderboards (top pattern creators)
- Social features (like/comment on patterns)

### Phase 4: Business Intelligence Dashboard (2027)
- Admin web dashboard for viewing trends
- Export reports (CSV, PDF)
- A/B testing framework
- Revenue attribution (which patterns drive premium upgrades?)

---

## Summary

The Lumina Analytics System provides a **privacy-first, community-driven platform** for understanding pattern trends and user preferences. By aggregating anonymized usage data, we can:

1. **Identify Popular Patterns**: Know which patterns resonate with users
2. **Discover Gaps**: Find missing patterns users are requesting
3. **Inform Product Development**: Prioritize new pattern creation
4. **Improve Recommendations**: Personalize suggestions based on trends
5. **Build Community**: Let users vote on and request patterns

### Key Benefits

**For Users**:
- Discover trending patterns
- Request missing patterns
- Vote on community requests
- See personalized recommendations

**For Product Team**:
- Data-driven pattern creation
- Priority roadmap based on requests
- Marketing insights (which patterns to promote)
- User retention metrics (popular patterns → engaged users)

**For Business**:
- Competitive advantage (know what users want)
- Community engagement (user participation)
- Premium features (exclusive patterns based on trends)
- Partnership opportunities (sports teams, holidays)

---

## Quick Reference

### Import Statements
```dart
import 'package:nexgen_command/features/analytics/analytics_providers.dart';
import 'package:nexgen_command/services/analytics_aggregator.dart';
import 'package:nexgen_command/models/analytics_models.dart';
import 'package:nexgen_command/widgets/pattern_feedback_dialog.dart';
import 'package:nexgen_command/widgets/pattern_request_dialog.dart';
import 'package:nexgen_command/features/analytics/trending_patterns_screen.dart';
```

### Common Operations

**Submit Feedback**:
```dart
await PatternFeedbackDialog.show(context, patternName: 'Pattern Name', source: 'source');
```

**Request Pattern**:
```dart
await PatternRequestDialog.show(context);
```

**View Trending**:
```dart
context.push('/trending');
```

**Check Opt-In Status**:
```dart
final optedIn = ref.watch(analyticsOptInProvider);
```

### Firestore Paths

- Global Stats: `/analytics/global_pattern_stats/patterns/{patternId}`
- Pattern Requests: `/analytics/pattern_requests/requests/{requestId}`
- Pattern Feedback: `/analytics/pattern_feedback/patterns/{patternId}`
- User Feedback: `/users/{userId}/pattern_feedback/{feedbackId}`
- Color Trends: `/analytics/color_trends/weekly/{weekId}`
- Effect Popularity: `/analytics/effect_popularity/effects/effect_{effectId}`

---

**Documentation Version**: 1.0
**Last Updated**: January 23, 2026
**Author**: Claude Sonnet 4.5 (AI Assistant)
