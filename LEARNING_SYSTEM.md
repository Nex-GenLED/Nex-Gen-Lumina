# Lumina Learning System - Implementation Guide

## Overview

The Lumina Learning System is an intelligent pattern recognition and suggestion engine that learns from user behavior to provide personalized recommendations and automate routine lighting control.

## Features Implemented

### 1. Usage Analytics & Tracking
- **Pattern usage logging** - Every pattern application is recorded in Firestore
- **Time-of-day tracking** - Detects when users typically use specific patterns
- **Frequency analysis** - Identifies most-used patterns and effects
- **Source tracking** - Records how patterns were triggered (manual, voice, schedule, Lumina AI, etc.)

### 2. Automatic Favorites
- **Auto-population** - Top 3-5 most-used patterns automatically added to favorites
- **Smart ranking** - Combines recency and frequency for intelligent sorting
- **Manual overrides** - Users can manually add/remove favorites
- **Auto-favorites badge** - Visually distinguishes auto-added vs manually-added favorites

### 3. Habit Detection
- **Time-of-day habits** - Detects patterns like "user turns on lights at 7am on weekdays"
- **Recurring patterns** - Identifies specific effects/colors used consistently
- **Confidence scoring** - Only surfaces habits with 60%+ confidence
- **Contextual awareness** - Considers day of week, time, and user actions

### 4. Smart Suggestions
- **Schedule suggestions** - Recommends creating automations based on detected habits
- **Contextual patterns** - Suggests patterns based on time (sunset, evening, morning)
- **Event reminders** - Notifies about upcoming game days, holidays with custom patterns
- **Favorites suggestions** - Prompts to add frequently-used patterns to favorites

### 5. Notifications
- **Smart suggestion notifications** - High-priority suggestions trigger notifications
- **Event reminders** - "Chiefs game tomorrow - your pattern is ready"
- **Habit alerts** - "Lumina noticed you usually turn off lights at 11pm"
- **Favorites updates** - Notifies when auto-favorites are updated

## Architecture

### Data Models
**Location**: `lib/models/usage_analytics_models.dart`

- `PatternUsageEvent` - Individual usage event
- `PatternUsageStats` - Aggregated statistics for ranking
- `DetectedHabit` - Behavioral pattern detected by the system
- `SmartSuggestion` - Actionable recommendation
- `FavoritePattern` - User's favorite patterns (manual + auto)

### Core Services

#### UserService Extensions
**Location**: `lib/services/user_service.dart`

New methods:
- `logPatternUsage()` - Enhanced with more tracking parameters
- `getRecentUsage()` - Fetch last N days of usage
- `getPatternFrequency()` - Get usage counts by pattern
- `getUsageByHour()` - Time-of-day distribution
- `addFavorite()` / `removeFavorite()` - Favorites management
- `saveSuggestion()` / `dismissSuggestion()` - Suggestions CRUD
- `saveDetectedHabit()` - Store detected behavioral patterns

#### HabitLearner
**Location**: `lib/features/autopilot/habit_learner.dart`

Main intelligence engine:
- `analyzeHabits()` - Runs ML-like heuristics on usage data
- `updateAutoFavorites()` - Refreshes top patterns
- `generateSuggestions()` - Creates contextual recommendations
- `_detectTimeOfDayHabits()` - Finds recurring time patterns
- `_detectPreferenceHabits()` - Identifies favorite effects/colors

#### SuggestionService
**Location**: `lib/services/suggestion_service.dart`

Background orchestration:
- `runDailySuggestionCheck()` - Daily cron-like task
- `checkContextualSuggestions()` - Real-time context checks
- `checkEventSuggestions()` - Event-based triggers
- `suggestAddingToFavorites()` - Favorites prompts

### Riverpod Providers
**Location**: `lib/features/autopilot/learning_providers.dart`

#### State Providers
- `favoritePatternsProvider` - Stream of user favorites
- `activeSuggestionsProvider` - Stream of active suggestions
- `detectedHabitsProvider` - List of detected habits
- `recentUsageProvider` - Recent usage events stream
- `patternFrequencyProvider` - Usage frequency map

#### Notifiers
- `FavoritesNotifier` - Manage favorites (add/remove/update usage)
- `SuggestionsNotifier` - Manage suggestions (dismiss/generate)
- `HabitAnalysisNotifier` - Trigger habit analysis
- `UsageLoggerNotifier` - Log usage events

### UI Components

#### FavoritesGrid
**Location**: `lib/widgets/favorites_grid.dart`

Displays user's favorite patterns in a grid:
- Shows pattern name, usage count, last used
- Auto-added badge for system-generated favorites
- Remove button with confirmation
- Empty state with "Refresh Favorites" button

#### SmartSuggestionsList
**Location**: `lib/widgets/smart_suggestions_list.dart`

Displays actionable suggestions:
- Dismissible cards (swipe to dismiss)
- Priority badges for high-importance suggestions
- Action buttons (Create, Apply, Add to Favorites, etc.)
- Type-specific icons and colors
- Automatic filtering of expired/dismissed suggestions

### Usage Tracking Extension
**Location**: `lib/features/wled/usage_tracking_extension.dart`

Convenience methods for tracking:
```dart
// Track a GradientPattern
ref.trackPatternUsage(
  pattern: myPattern,
  source: 'lumina_ai',
);

// Track a WLED payload
ref.trackWledPayload(
  payload: wledJson,
  patternName: 'Custom Pattern',
  source: 'voice',
);

// Track power toggle
ref.trackPowerToggle(
  isOn: true,
  source: 'geofence',
);
```

## Integration Guide

### Step 1: Add Usage Tracking to Existing Code

Wherever patterns are applied, add tracking:

**Example: Pattern Library**
```dart
// In pattern_library_pages.dart or similar
Future<void> _applyPattern(GradientPattern pattern) async {
  // Apply the pattern
  final payload = pattern.toWledPayload();
  await ref.read(wledRepositoryProvider)?.setState(payload);

  // Track usage
  ref.trackPatternUsage(
    pattern: pattern,
    source: 'pattern_library',
  );
}
```

**Example: Voice Commands**
```dart
// In voice_providers.dart
Future<void> _executeVoiceCommand(String command) async {
  final pattern = _parsePattern(command);
  await _applyPattern(pattern);

  // Track voice usage
  ref.trackPatternUsage(
    pattern: pattern,
    source: 'voice',
  );
}
```

**Example: Lumina AI**
```dart
// In lumina_brain.dart
Future<void> _applyAiSuggestion(GradientPattern pattern) async {
  await _applyToDevice(pattern);

  // Track AI usage
  ref.trackPatternUsage(
    pattern: pattern,
    source: 'lumina_ai',
  );
}
```

### Step 2: Display Favorites in Dashboard

Add to your dashboard or Explore screen:

```dart
import 'package:nexgen_command/widgets/favorites_grid.dart';

// In your build method
Column(
  children: [
    // ... other widgets

    FavoritesGrid(
      onPatternTap: (favorite) async {
        // Apply the favorite pattern
        final payload = favorite.patternData;
        await ref.read(wledRepositoryProvider)?.setState(payload);

        // Record usage
        await ref.read(favoritesNotifierProvider.notifier)
          .recordFavoriteUsage(favorite.id);
      },
    ),
  ],
)
```

### Step 3: Display Suggestions

Add to dashboard or a dedicated suggestions screen:

```dart
import 'package:nexgen_command/widgets/smart_suggestions_list.dart';

// In your build method
SmartSuggestionsList(
  maxSuggestions: 3,
  onSuggestionAction: (suggestion) async {
    // Handle suggestion action based on type
    switch (suggestion.type) {
      case SuggestionType.applyPattern:
        await _applyPatternFromSuggestion(suggestion);
        break;
      case SuggestionType.createSchedule:
        await _createScheduleFromSuggestion(suggestion);
        break;
      case SuggestionType.favorite:
        await _addToFavorites(suggestion);
        break;
      // ... handle other types
    }

    // Dismiss after action
    await ref.read(suggestionsNotifierProvider.notifier)
      .dismissSuggestion(suggestion.id);
  },
)
```

### Step 4: Run Daily Analysis (Background Task)

Implement a background task or app startup routine:

```dart
// In main.dart or a background service
Future<void> runDailyMaintenance() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userService = UserService();
  final suggestionService = SuggestionService(
    userService: userService,
    userId: user.uid,
  );

  // Run daily checks
  await suggestionService.runDailySuggestionCheck();
}

// Call once per day (use WorkManager, flutter_background_service, etc.)
```

### Step 5: Trigger Contextual Suggestions

Add contextual checks at key moments:

```dart
// On app resume/startup
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);

  if (state == AppLifecycleState.resumed) {
    _checkContextualSuggestions();
  }
}

Future<void> _checkContextualSuggestions() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userService = UserService();
  final suggestionService = SuggestionService(
    userService: userService,
    userId: user.uid,
  );

  await suggestionService.checkContextualSuggestions();
}
```

## Firestore Schema

### Collections

#### `/users/{uid}/pattern_usage`
Stores individual usage events:
```json
{
  "created_at": Timestamp,
  "source": "lumina_ai | manual | voice | schedule | geofence",
  "pattern_name": "Warm White Glow",
  "colors": ["warm_white", "amber"],
  "effect_id": 0,
  "effect_name": "Solid",
  "brightness": 200,
  "speed": 128,
  "intensity": 128,
  "wled": { /* full WLED payload */ }
}
```

#### `/users/{uid}/favorites`
User's favorite patterns:
```json
{
  "id": "auto_generated_id",
  "pattern_name": "Chiefs Game Day",
  "pattern_data": { /* WLED payload */ },
  "added_at": Timestamp,
  "last_used": Timestamp,
  "usage_count": 15,
  "auto_added": true
}
```

#### `/users/{uid}/suggestions`
Active suggestions:
```json
{
  "id": "sunset_23",
  "type": "applyPattern",
  "title": "Turn on Warm White for Evening",
  "description": "It's almost sunset - create a cozy ambiance?",
  "created_at": Timestamp,
  "expires_at": Timestamp,
  "dismissed": false,
  "priority": 0.8,
  "action_data": { /* data needed to execute */ }
}
```

#### `/users/{uid}/detected_habits`
Detected behavioral patterns:
```json
{
  "id": "time_22_...",
  "type": "timeOfDay",
  "description": "You usually turn off lights around 10:00 PM (75% of days)",
  "confidence": 0.75,
  "detected_at": Timestamp,
  "metadata": {
    "hour": 22,
    "occurrences": 23,
    "days_analyzed": 30,
    "pattern": "Power Off"
  }
}
```

## Testing & Validation

### Manual Testing Steps

1. **Test Usage Tracking**
   - Apply several patterns via different sources
   - Check Firestore: `users/{uid}/pattern_usage` should have new documents
   - Verify all fields are populated correctly

2. **Test Auto-Favorites**
   - Apply the same pattern 5+ times over a few days
   - Call `ref.read(favoritesNotifierProvider.notifier).refreshAutoFavorites()`
   - Check that pattern appears in `FavoritesGrid` with auto-added badge

3. **Test Habit Detection**
   - Use patterns at consistent times (e.g., 7am every weekday)
   - Call `ref.read(habitAnalysisNotifierProvider.notifier).analyzeHabits()`
   - Check Firestore: `users/{uid}/detected_habits` should have new habits

4. **Test Suggestions**
   - Trigger contextual checks (open app in evening)
   - Verify suggestions appear in `SmartSuggestionsList`
   - Test dismissing and acting on suggestions

5. **Test Notifications**
   - Wait for high-priority suggestions
   - Verify notifications appear on device
   - Test notification channels and permissions

## Performance Considerations

- **Usage logging is async** - Won't block UI
- **Auto-favorites refresh** - Run max once per day
- **Habit analysis** - Run during low-usage times (background)
- **Firestore queries** - All queries use indexes and limits
- **Suggestion expiration** - Suggestions auto-expire after set time

## Future Enhancements

1. **Machine Learning Integration**
   - Replace heuristics with Firebase ML Kit or TensorFlow Lite
   - Train on user patterns for better predictions

2. **Community Patterns**
   - Share anonymized usage data with similar users
   - "Users with your house style also like..."

3. **Advanced Context**
   - Weather integration (cloudy day = brighter lights?)
   - Calendar integration (party tonight = party mode suggestion)
   - Location-aware suggestions (on vacation = vacation mode)

4. **Voice Integration**
   - "Lumina, what do I usually use on Friday nights?"
   - "Add this pattern to my favorites"

5. **Analytics Dashboard**
   - Visual charts of usage patterns
   - Favorite colors/effects over time
   - Energy usage insights

## Troubleshooting

### Problem: Usage not being tracked
- Verify `trackPatternUsage()` is called after applying patterns
- Check Firestore rules allow writes to `pattern_usage` subcollection
- Ensure user is authenticated

### Problem: Auto-favorites not updating
- Call `refreshAutoFavorites()` manually to test
- Check usage events exist in Firestore
- Verify at least 5+ uses of a pattern

### Problem: No suggestions appearing
- Run `generateSuggestions()` manually
- Check habits are being detected
- Verify suggestion expiration dates
- Check notification permissions

### Problem: Suggestions not dismissed
- Verify `dismissSuggestion()` is called
- Check Firestore update succeeds
- Ensure suggestion ID is correct

## Summary

The Lumina Learning System transforms Lumina from a manual control app into an intelligent assistant that learns and adapts to user behavior. By tracking usage, detecting habits, and generating contextual suggestions, it creates a personalized, proactive lighting experience.

**Key Integration Points:**
1. Add `ref.trackPatternUsage()` wherever patterns are applied
2. Display `FavoritesGrid` in dashboard/explore
3. Show `SmartSuggestionsList` prominently
4. Run daily analysis via background task
5. Check contextual suggestions on app resume

**User Value:**
- Zero-config favorites based on actual usage
- Smart automation suggestions reduce manual scheduling
- Contextual pattern recommendations (sunset, events, etc.)
- Proactive notifications for recurring actions
- Learn from habits without explicit training
