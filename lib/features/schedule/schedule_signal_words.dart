// Keyword lists and scoring weights for schedule complexity classification.
//
// Separated from [ScheduleComplexityClassifier] so signal data is easy to tune
// without touching classifier logic. Mirrors the pattern from
// [classification_signals.dart] in the AI feature.

// ---------------------------------------------------------------------------
// Signal entry (reusable weighted keyword)
// ---------------------------------------------------------------------------

/// A weighted keyword or regex pattern that signals schedule complexity.
class ScheduleSignal {
  /// The keyword or phrase to match (case-insensitive).
  final String keyword;

  /// Score contribution when matched (higher = stronger signal).
  final double weight;

  /// If true, [keyword] is treated as a regex pattern rather than a
  /// literal substring.
  final bool isRegex;

  const ScheduleSignal(this.keyword, this.weight, {this.isRegex = false});
}

// ---------------------------------------------------------------------------
// Simple schedule signals
// ---------------------------------------------------------------------------

/// Signals indicating a SIMPLE, single-event schedule request with all
/// parameters clearly specified. These push complexity DOWN.
const List<ScheduleSignal> simpleScheduleSignals = [
  // --- Explicit single-action power commands ---
  ScheduleSignal('turn off', 0.90),
  ScheduleSignal('turn on', 0.85),
  ScheduleSignal('shut off', 0.85),
  ScheduleSignal('lights off', 0.85),
  ScheduleSignal('lights on', 0.80),
  ScheduleSignal('switch off', 0.80),
  ScheduleSignal('switch on', 0.80),
  ScheduleSignal('power off', 0.80),
  ScheduleSignal('power on', 0.75),

  // --- Clear single-time references ---
  ScheduleSignal(r'\bat\s+\d{1,2}\s*(am|pm)\b', 0.75, isRegex: true),
  ScheduleSignal(r'\bat\s+\d{1,2}:\d{2}\s*(am|pm)?\b', 0.75, isRegex: true),
  ScheduleSignal('at sunset', 0.80),
  ScheduleSignal('at sunrise', 0.80),
  ScheduleSignal('at dusk', 0.75),
  ScheduleSignal('at dawn', 0.75),

  // --- Clear recurrence ---
  ScheduleSignal('every night', 0.70),
  ScheduleSignal('every evening', 0.70),
  ScheduleSignal('every morning', 0.65),
  ScheduleSignal('every day', 0.65),
  ScheduleSignal('nightly', 0.70),
  ScheduleSignal('daily', 0.65),

  // --- One-time indicators ---
  ScheduleSignal('tonight', 0.75),
  ScheduleSignal('tomorrow', 0.70),
  ScheduleSignal('tomorrow night', 0.75),
  ScheduleSignal('this evening', 0.70),

  // --- Simple color/scene references ---
  ScheduleSignal('warm white', 0.65),
  ScheduleSignal('cool white', 0.65),
  ScheduleSignal('solid', 0.60),

  // --- Cancel/delete (simple modification) ---
  ScheduleSignal('cancel', 0.80),
  ScheduleSignal('delete', 0.75),
  ScheduleSignal('remove', 0.75),
  ScheduleSignal('disable', 0.70),
  ScheduleSignal('pause', 0.65),
  ScheduleSignal('stop', 0.65),
];

// ---------------------------------------------------------------------------
// Moderate schedule signals
// ---------------------------------------------------------------------------

/// Signals indicating a MODERATE request — recurring with a theme or has
/// one ambiguity that needs a smart default. These push complexity to mid.
const List<ScheduleSignal> moderateScheduleSignals = [
  // --- Themed recurring schedules ---
  ScheduleSignal('every game day', 0.85),
  ScheduleSignal('game day', 0.75),
  ScheduleSignal('game night', 0.70),
  ScheduleSignal('holiday mode', 0.80),
  ScheduleSignal('party mode', 0.70),
  ScheduleSignal('date night', 0.65),

  // --- Schedule modification with ambiguity ---
  ScheduleSignal('change my', 0.70),
  ScheduleSignal('update my', 0.70),
  ScheduleSignal('modify my', 0.70),
  ScheduleSignal('adjust my', 0.65),
  ScheduleSignal('something different', 0.75),
  ScheduleSignal('something new', 0.70),
  ScheduleSignal('switch it up', 0.70),
  ScheduleSignal('change it up', 0.70),

  // --- References to existing schedule ---
  ScheduleSignal('my schedule', 0.60),
  ScheduleSignal('my evening schedule', 0.65),
  ScheduleSignal('my morning schedule', 0.65),
  ScheduleSignal('my current schedule', 0.70),
  ScheduleSignal('the schedule', 0.55),
  ScheduleSignal('existing schedule', 0.65),

  // --- Starting from a date ---
  ScheduleSignal('starting', 0.55),
  ScheduleSignal('starting next', 0.65),
  ScheduleSignal('beginning', 0.55),
  ScheduleSignal('from now on', 0.60),
  ScheduleSignal('going forward', 0.55),

  // --- Partial recurrence (specific days) ---
  ScheduleSignal('on weekdays', 0.60),
  ScheduleSignal('on weekends', 0.60),
  ScheduleSignal('weeknights', 0.60),
  ScheduleSignal(r'\bon\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?\b',
      0.55, isRegex: true),
];

// ---------------------------------------------------------------------------
// Complex schedule signals
// ---------------------------------------------------------------------------

/// Signals indicating a COMPLEX, multi-part, creative, or conflict-prone
/// schedule request. These push complexity to the highest level.
const List<ScheduleSignal> complexScheduleSignals = [
  // --- Multi-day variation ---
  ScheduleSignal('different each', 0.95),
  ScheduleSignal('different every', 0.95),
  ScheduleSignal('a different', 0.80),
  ScheduleSignal('new design each', 0.90),
  ScheduleSignal('new pattern each', 0.90),
  ScheduleSignal('new look each', 0.85),
  ScheduleSignal('change it up each', 0.85),
  ScheduleSignal('vary', 0.70),
  ScheduleSignal('variety', 0.75),
  ScheduleSignal('mix it up', 0.85),
  ScheduleSignal('rotate', 0.70),
  ScheduleSignal('rotation', 0.75),
  ScheduleSignal('alternate', 0.70),
  ScheduleSignal('alternating', 0.75),
  ScheduleSignal('cycle through', 0.80),

  // --- Long duration spans ---
  ScheduleSignal('all month', 0.80),
  ScheduleSignal('all season', 0.80),
  ScheduleSignal('for a month', 0.75),
  ScheduleSignal('for the month', 0.75),
  ScheduleSignal('for a week', 0.65),
  ScheduleSignal('for the week', 0.65),
  ScheduleSignal('through december', 0.80),
  ScheduleSignal('through january', 0.80),
  ScheduleSignal(r'through\s+(january|february|march|april|may|june|july|august|september|october|november|december)',
      0.80, isRegex: true),
  ScheduleSignal(r'until\s+(january|february|march|april|may|june|july|august|september|october|november|december)',
      0.75, isRegex: true),
  ScheduleSignal('rest of the season', 0.80),
  ScheduleSignal('rest of the month', 0.75),

  // --- Multi-zone ---
  ScheduleSignal('front of house', 0.70),
  ScheduleSignal('back of house', 0.70),
  ScheduleSignal('front yard', 0.65),
  ScheduleSignal('backyard', 0.65),
  ScheduleSignal('back yard', 0.65),
  ScheduleSignal('garage', 0.60),
  ScheduleSignal('driveway', 0.60),
  ScheduleSignal('patio', 0.60),
  ScheduleSignal('roofline', 0.55),

  // --- Conditional logic ---
  ScheduleSignal('only on', 0.65),
  ScheduleSignal('except', 0.70),
  ScheduleSignal('unless', 0.75),
  ScheduleSignal('but not on', 0.75),
  ScheduleSignal('except on', 0.75),
  ScheduleSignal('except holidays', 0.80),
  ScheduleSignal('only when', 0.75),
  ScheduleSignal('only if', 0.75),
  ScheduleSignal('when it', 0.55),
  ScheduleSignal('if it', 0.50),

  // --- Creative / generative element ---
  ScheduleSignal('surprise me', 0.80),
  ScheduleSignal('get creative', 0.85),
  ScheduleSignal('pick something', 0.70),
  ScheduleSignal('choose something', 0.70),
  ScheduleSignal('random', 0.65),
  ScheduleSignal('randomize', 0.70),

  // --- Explicit multi-event language ---
  ScheduleSignal('multiple', 0.65),
  ScheduleSignal('several', 0.60),
  ScheduleSignal('a bunch', 0.60),
  ScheduleSignal('series', 0.70),
  ScheduleSignal('playlist', 0.75),
  ScheduleSignal('lineup', 0.70),
];

// ---------------------------------------------------------------------------
// Time reference patterns
// ---------------------------------------------------------------------------

/// Patterns that identify time references in schedule requests.
const List<ScheduleSignal> timeReferenceSignals = [
  // --- Absolute clock times ---
  ScheduleSignal(r'\b\d{1,2}\s*(am|pm)\b', 0.90, isRegex: true),
  ScheduleSignal(r'\b\d{1,2}:\d{2}\s*(am|pm)?\b', 0.90, isRegex: true),
  ScheduleSignal(r'\b(noon|midnight)\b', 0.85, isRegex: true),

  // --- Solar references ---
  ScheduleSignal('sunset', 0.90),
  ScheduleSignal('sunrise', 0.90),
  ScheduleSignal('dusk', 0.85),
  ScheduleSignal('dawn', 0.85),
  ScheduleSignal('sundown', 0.85),
  ScheduleSignal('sunup', 0.80),

  // --- Relative time-of-day ---
  ScheduleSignal('evening', 0.70),
  ScheduleSignal('morning', 0.70),
  ScheduleSignal('night', 0.65),
  ScheduleSignal('afternoon', 0.65),
  ScheduleSignal('late night', 0.70),
  ScheduleSignal('after dark', 0.75),
  ScheduleSignal('before bed', 0.65),
  ScheduleSignal('bedtime', 0.65),
];

// ---------------------------------------------------------------------------
// Multi-day / duration indicators
// ---------------------------------------------------------------------------

/// Patterns that indicate the request spans multiple days.
const List<ScheduleSignal> multiDaySignals = [
  ScheduleSignal('every night', 0.80),
  ScheduleSignal('every evening', 0.80),
  ScheduleSignal('every day', 0.75),
  ScheduleSignal('every morning', 0.75),
  ScheduleSignal('each night', 0.80),
  ScheduleSignal('each day', 0.80),
  ScheduleSignal('each evening', 0.80),
  ScheduleSignal('nightly', 0.75),
  ScheduleSignal('daily', 0.70),
  ScheduleSignal('weekly', 0.85),
  ScheduleSignal('for a week', 0.80),
  ScheduleSignal('for the week', 0.80),
  ScheduleSignal('for a month', 0.90),
  ScheduleSignal('all month', 0.90),
  ScheduleSignal('all season', 0.90),
  ScheduleSignal('all week', 0.85),
  ScheduleSignal(r'\b\d+\s+(days?|nights?|weeks?|months?)\b', 0.85, isRegex: true),
];

// ---------------------------------------------------------------------------
// Creative / generative indicators
// ---------------------------------------------------------------------------

/// Patterns indicating the request needs creative generation or variation.
const List<ScheduleSignal> creativeSignals = [
  // --- Team / brand references (trigger creative color lookup) ---
  ScheduleSignal(r'\b(chiefs?|royals?|sporting\s*kc)\b', 0.90, isRegex: true),
  ScheduleSignal(r'\b(lakers?|celtics?|warriors?|bulls?|heat|nets?|knicks?)\b', 0.80, isRegex: true),
  ScheduleSignal(r'\b(packers?|cowboys?|steelers?|eagles?|bears?|niners?|49ers?)\b', 0.80, isRegex: true),
  ScheduleSignal(r'\b(yankees?|dodgers?|red\s*sox|cubs?|cardinals?|braves?)\b', 0.80, isRegex: true),

  // --- Holiday references ---
  ScheduleSignal('christmas', 0.75),
  ScheduleSignal('halloween', 0.75),
  ScheduleSignal('valentine', 0.70),
  ScheduleSignal("st patrick", 0.70),
  ScheduleSignal('fourth of july', 0.70),
  ScheduleSignal('4th of july', 0.70),
  ScheduleSignal('independence day', 0.70),
  ScheduleSignal('easter', 0.65),
  ScheduleSignal('hanukkah', 0.70),
  ScheduleSignal('thanksgiving', 0.65),
  ScheduleSignal('new year', 0.65),
  ScheduleSignal('mardi gras', 0.70),
  ScheduleSignal('festive', 0.55),
  ScheduleSignal('holiday', 0.50),

  // --- Mood / theme words that require generation ---
  ScheduleSignal('cozy', 0.55),
  ScheduleSignal('romantic', 0.55),
  ScheduleSignal('spooky', 0.60),
  ScheduleSignal('patriotic', 0.60),
  ScheduleSignal('elegant', 0.50),
  ScheduleSignal('festive', 0.55),

  // --- Explicit variation / creativity ---
  ScheduleSignal('different', 0.65),
  ScheduleSignal('variety', 0.70),
  ScheduleSignal('creative', 0.75),
  ScheduleSignal('mix it up', 0.80),
  ScheduleSignal('surprise me', 0.80),
  ScheduleSignal('random', 0.60),
  ScheduleSignal('unique', 0.60),
];

// ---------------------------------------------------------------------------
// Known sports teams (for entity extraction)
// ---------------------------------------------------------------------------

/// Map of team name keywords → structured team info for entity extraction.
const Map<String, TeamReference> knownTeams = {
  'chiefs': TeamReference('Kansas City Chiefs', 'NFL', 'KC Chiefs'),
  'kc chiefs': TeamReference('Kansas City Chiefs', 'NFL', 'KC Chiefs'),
  'kansas city chiefs': TeamReference('Kansas City Chiefs', 'NFL', 'KC Chiefs'),
  'royals': TeamReference('Kansas City Royals', 'MLB', 'KC Royals'),
  'kc royals': TeamReference('Kansas City Royals', 'MLB', 'KC Royals'),
  'kansas city royals': TeamReference('Kansas City Royals', 'MLB', 'KC Royals'),
  'sporting kc': TeamReference('Sporting Kansas City', 'MLS', 'Sporting KC'),
  'sporting': TeamReference('Sporting Kansas City', 'MLS', 'Sporting KC'),
  'lakers': TeamReference('Los Angeles Lakers', 'NBA', 'Lakers'),
  'celtics': TeamReference('Boston Celtics', 'NBA', 'Celtics'),
  'warriors': TeamReference('Golden State Warriors', 'NBA', 'Warriors'),
  'bulls': TeamReference('Chicago Bulls', 'NBA', 'Bulls'),
  'heat': TeamReference('Miami Heat', 'NBA', 'Heat'),
  'nets': TeamReference('Brooklyn Nets', 'NBA', 'Nets'),
  'knicks': TeamReference('New York Knicks', 'NBA', 'Knicks'),
  'packers': TeamReference('Green Bay Packers', 'NFL', 'Packers'),
  'cowboys': TeamReference('Dallas Cowboys', 'NFL', 'Cowboys'),
  'steelers': TeamReference('Pittsburgh Steelers', 'NFL', 'Steelers'),
  'eagles': TeamReference('Philadelphia Eagles', 'NFL', 'Eagles'),
  'bears': TeamReference('Chicago Bears', 'NFL', 'Bears'),
  'niners': TeamReference('San Francisco 49ers', 'NFL', '49ers'),
  '49ers': TeamReference('San Francisco 49ers', 'NFL', '49ers'),
  'yankees': TeamReference('New York Yankees', 'MLB', 'Yankees'),
  'dodgers': TeamReference('Los Angeles Dodgers', 'MLB', 'Dodgers'),
  'red sox': TeamReference('Boston Red Sox', 'MLB', 'Red Sox'),
  'cubs': TeamReference('Chicago Cubs', 'MLB', 'Cubs'),
  'cardinals': TeamReference('St. Louis Cardinals', 'MLB', 'Cardinals'),
  'braves': TeamReference('Atlanta Braves', 'MLB', 'Braves'),
};

/// Structured team reference for entity extraction.
class TeamReference {
  final String fullName;
  final String league;
  final String shortName;

  const TeamReference(this.fullName, this.league, this.shortName);

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'league': league,
        'shortName': shortName,
      };
}

// ---------------------------------------------------------------------------
// Known holidays (for entity extraction)
// ---------------------------------------------------------------------------

/// Map of holiday keywords → canonical holiday name.
const Map<String, String> knownHolidays = {
  'christmas': 'Christmas',
  'xmas': 'Christmas',
  'halloween': 'Halloween',
  'valentine': "Valentine's Day",
  'valentines': "Valentine's Day",
  "valentine's": "Valentine's Day",
  'st patrick': "St. Patrick's Day",
  'st patricks': "St. Patrick's Day",
  "st patrick's": "St. Patrick's Day",
  'fourth of july': 'Independence Day',
  '4th of july': 'Independence Day',
  'independence day': 'Independence Day',
  'easter': 'Easter',
  'hanukkah': 'Hanukkah',
  'chanukah': 'Hanukkah',
  'thanksgiving': 'Thanksgiving',
  'new year': "New Year's",
  "new year's": "New Year's",
  'new years': "New Year's",
  'mardi gras': 'Mardi Gras',
  'diwali': 'Diwali',
  'pride': 'Pride',
  'memorial day': 'Memorial Day',
  'labor day': 'Labor Day',
  'veterans day': 'Veterans Day',
};

// ---------------------------------------------------------------------------
// Zone references (for entity extraction)
// ---------------------------------------------------------------------------

/// Map of zone keywords → canonical zone identifier.
const Map<String, String> knownZones = {
  'front': 'front',
  'front of house': 'front',
  'front yard': 'front',
  'front porch': 'front',
  'back': 'back',
  'back of house': 'back',
  'backyard': 'back',
  'back yard': 'back',
  'rear': 'back',
  'garage': 'garage',
  'driveway': 'driveway',
  'patio': 'patio',
  'deck': 'patio',
  'roofline': 'roofline',
  'roof': 'roofline',
  'eaves': 'roofline',
  'soffit': 'roofline',
  'side': 'side',
  'left side': 'left',
  'right side': 'right',
  'all': 'all',
  'everywhere': 'all',
  'whole house': 'all',
  'entire house': 'all',
};

// ---------------------------------------------------------------------------
// Scoring thresholds
// ---------------------------------------------------------------------------

/// Minimum simple score to classify as SIMPLE when no complex signals fire.
const double kSimpleThreshold = 0.60;

/// Minimum moderate score to classify as MODERATE.
const double kModerateThreshold = 0.50;

/// Score above which complex signals dominate regardless of simple score.
const double kComplexOverrideThreshold = 0.80;

/// If complex score exceeds simple score by this margin, classify as COMPLEX.
const double kComplexMargin = 0.30;

/// Bonus when multiple zones are referenced (pushes toward COMPLEX).
const double kMultiZoneBonus = 0.40;

/// Bonus when variation + multi-day both fire (pushes toward COMPLEX).
const double kVariationMultiDayBonus = 0.35;

/// Penalty applied to complex score when the request is a clear
/// cancellation or simple toggle.
const double kCancelPenalty = 0.50;
