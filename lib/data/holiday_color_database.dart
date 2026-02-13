import 'package:nexgen_command/features/patterns/canonical_palettes.dart';
import 'package:nexgen_command/data/us_federal_holidays.dart';
import 'package:nexgen_command/data/team_color_database.dart' show TeamColor;

// ---------------------------------------------------------------------------
// HolidayType
// ---------------------------------------------------------------------------

/// Classification of a holiday/event entry.
enum HolidayType {
  /// US federal holiday (New Year's Day, MLK Day, etc.)
  federal,

  /// Popular, widely-celebrated holiday (Valentine's, Halloween, etc.)
  popular,

  /// Cultural, religious, or awareness event (Diwali, Kwanzaa, Pride, etc.)
  cultural,

  /// Season of the year
  season,
}

// ---------------------------------------------------------------------------
// HolidayColorEntry
// ---------------------------------------------------------------------------

/// A unified holiday / seasonal / cultural event entry with color data,
/// suggested WLED effects, and matching metadata.
class HolidayColorEntry {
  /// Unique identifier (lowercase, underscores).
  final String id;

  /// Human-readable display name.
  final String name;

  /// Alternate names / search terms for fuzzy matching.
  final List<String> aliases;

  /// Classification.
  final HolidayType type;

  /// Official / traditional colors for this event.
  final List<TeamColor> colors;

  /// Suggested WLED effect IDs (first is default).
  final List<int> suggestedEffects;

  /// Default speed (0-255).
  final int defaultSpeed;

  /// Default intensity (0-255).
  final int defaultIntensity;

  /// Whether this event traditionally uses colorful / festive lighting.
  /// `false` for solemn or respectful observances.
  final bool isColorful;

  /// Calendar month (1-12) for approximate date matching.
  /// Null for floating or multi-month events.
  final int? month;

  /// Calendar day (1-31) for fixed-date events.
  /// Null for floating holidays.
  final int? day;

  const HolidayColorEntry({
    required this.id,
    required this.name,
    this.aliases = const [],
    required this.type,
    required this.colors,
    this.suggestedEffects = const [0],
    this.defaultSpeed = 128,
    this.defaultIntensity = 128,
    this.isColorful = true,
    this.month,
    this.day,
  });

  /// Produce a structured JSON-compatible map for this entry.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'aliases': aliases,
        'type': type.name,
        'colors': colors.map((c) => c.toJson()).toList(),
        'suggestedEffects': suggestedEffects,
        'defaultSpeed': defaultSpeed,
        'defaultIntensity': defaultIntensity,
        'isColorful': isColorful,
        if (month != null) 'month': month,
        if (day != null) 'day': day,
      };

  @override
  String toString() => 'HolidayColorEntry($id, $name)';
}

// ---------------------------------------------------------------------------
// HolidayResolverResult
// ---------------------------------------------------------------------------

/// Result returned by [HolidayColorDatabase.resolve].
class HolidayResolverResult {
  /// Whether a match was found.
  final bool resolved;

  /// Best-matching entry (non-null when [resolved] is true).
  final HolidayColorEntry? holiday;

  /// Confidence score from 0.0 (no match) to 1.0 (perfect match).
  final double confidence;

  /// Other plausible matches, ordered by descending confidence.
  final List<HolidayColorEntry> alternatives;

  const HolidayResolverResult({
    required this.resolved,
    this.holiday,
    this.confidence = 0.0,
    this.alternatives = const [],
  });

  /// Convenience factory for "no match".
  const HolidayResolverResult.empty()
      : resolved = false,
        holiday = null,
        confidence = 0.0,
        alternatives = const [];
}

// ---------------------------------------------------------------------------
// HolidayColorDatabase
// ---------------------------------------------------------------------------

/// Unified facade over canonical palettes, US federal holidays,
/// and new cultural / awareness events.
///
/// All data is lazily computed and cached.
class HolidayColorDatabase {
  HolidayColorDatabase._();

  // -----------------------------------------------------------------------
  // Lazy cache
  // -----------------------------------------------------------------------
  static List<HolidayColorEntry>? _cache;

  /// Every known holiday, season, and cultural event in one flat list.
  static List<HolidayColorEntry> get allEntries {
    if (_cache != null) return _cache!;
    _cache = [
      ..._fromCanonicalPalettes(),
      ..._fromFederalHolidays(),
      ..._culturalEvents,
    ];
    return _cache!;
  }

  /// Merge overlay entries received from Firestore into the cached list.
  ///
  /// Called by [ColorDatabaseManagerNotifier] after syncing or loading cache.
  /// Duplicate IDs are replaced so corrections take effect.
  static void addOverlayEntries(List<HolidayColorEntry> overlay) {
    if (overlay.isEmpty) return;

    // Ensure the cache is populated first
    final current = allEntries;
    final existingIds = current.map((e) => e.id).toSet();

    for (final entry in overlay) {
      if (existingIds.contains(entry.id)) {
        // Replace existing entry (correction)
        final idx = current.indexWhere((e) => e.id == entry.id);
        if (idx >= 0) current[idx] = entry;
      } else {
        // New addition
        current.add(entry);
        existingIds.add(entry.id);
      }
    }
  }

  // -----------------------------------------------------------------------
  // 1. Entries derived from CanonicalPalettes
  // -----------------------------------------------------------------------

  /// Known keys in [CanonicalPalettes._themes] that are holidays or seasons.
  static const _canonicalHolidayKeys = [
    '4th of july',
    'christmas',
    'halloween',
    'valentines',
    'st patricks',
    'easter',
    'thanksgiving',
  ];

  static const _canonicalSeasonKeys = [
    'spring',
    'summer',
    'autumn',
    'winter',
  ];

  /// Month / day hints for the canonical holidays so we can populate
  /// the [month] and [day] fields without duplicating USFederalHolidays logic.
  static const _canonicalDateHints = <String, List<int?>>{
    '4th of july': [7, 4],
    'christmas': [12, 25],
    'halloween': [10, 31],
    'valentines': [2, 14],
    'st patricks': [3, 17],
    'easter': [null, null], // floating
    'thanksgiving': [11, null], // floating within November
  };

  static const _seasonMonthHints = <String, List<int?>>{
    'spring': [3, null],
    'summer': [6, null],
    'autumn': [9, null],
    'winter': [12, null],
  };

  static List<HolidayColorEntry> _fromCanonicalPalettes() {
    final entries = <HolidayColorEntry>[];

    for (final key in _canonicalHolidayKeys) {
      final theme = CanonicalPalettes.findTheme(key);
      if (theme == null) continue;

      final dateHint = _canonicalDateHints[key] ?? [null, null];

      entries.add(HolidayColorEntry(
        id: theme.id,
        name: theme.displayName,
        aliases: [key, ...theme.aliases],
        type: HolidayType.popular,
        colors: theme.canonicalColors
            .map((tc) => TeamColor(
                  tc.name,
                  (tc.color.r * 255.0).round().clamp(0, 255),
                  (tc.color.g * 255.0).round().clamp(0, 255),
                  (tc.color.b * 255.0).round().clamp(0, 255),
                ))
            .toList(),
        suggestedEffects: theme.suggestedEffects,
        defaultSpeed: theme.defaultSpeed,
        defaultIntensity: theme.defaultIntensity,
        isColorful: true,
        month: dateHint[0],
        day: dateHint[1],
      ));
    }

    for (final key in _canonicalSeasonKeys) {
      final theme = CanonicalPalettes.findTheme(key);
      if (theme == null) continue;

      final dateHint = _seasonMonthHints[key] ?? [null, null];

      entries.add(HolidayColorEntry(
        id: theme.id,
        name: theme.displayName,
        aliases: [key, ...theme.aliases],
        type: HolidayType.season,
        colors: theme.canonicalColors
            .map((tc) => TeamColor(
                  tc.name,
                  (tc.color.r * 255.0).round().clamp(0, 255),
                  (tc.color.g * 255.0).round().clamp(0, 255),
                  (tc.color.b * 255.0).round().clamp(0, 255),
                ))
            .toList(),
        suggestedEffects: theme.suggestedEffects,
        defaultSpeed: theme.defaultSpeed,
        defaultIntensity: theme.defaultIntensity,
        isColorful: true,
        month: dateHint[0],
        day: dateHint[1],
      ));
    }

    return entries;
  }

  // -----------------------------------------------------------------------
  // 2. Entries from USFederalHolidays NOT already in CanonicalPalettes
  // -----------------------------------------------------------------------

  /// IDs (lowercased) that are already covered by canonical entries.
  static final _canonicalCoveredNames = {
    'independence day', // covered by 4th of july
    'christmas',
    'halloween',
    "valentine's day",
    "st. patrick's day",
    'easter',
    'thanksgiving',
    "new year's eve", // will be added as a cultural event
    'diwali', // will be added as a cultural event
    'hanukkah', // will be added as a cultural event
    'cinco de mayo', // will be added as a cultural event
  };

  static List<HolidayColorEntry> _fromFederalHolidays() {
    final entries = <HolidayColorEntry>[];
    // Use a reference year to extract holiday metadata.
    final referenceYear = DateTime.now().year;
    final allFederal = USFederalHolidays.getHolidaysForYear(referenceYear);

    for (final h in allFederal) {
      if (_canonicalCoveredNames.contains(h.name.toLowerCase())) continue;

      entries.add(HolidayColorEntry(
        id: _slugify(h.name),
        name: h.name,
        aliases: _aliasesForFederal(h.name),
        type: HolidayType.federal,
        colors: h.suggestedColors
            .map((c) {
              final r = (c.r * 255.0).round().clamp(0, 255);
              final g = (c.g * 255.0).round().clamp(0, 255);
              final b = (c.b * 255.0).round().clamp(0, 255);
              return TeamColor(_colorName(r, g, b), r, g, b);
            })
            .toList(),
        suggestedEffects: [h.suggestedEffectId],
        defaultSpeed: 128,
        defaultIntensity: 128,
        isColorful: h.isColorful,
        month: h.date.month,
        day: h.date.day <= 28 ? h.date.day : null, // null for floating
      ));
    }

    return entries;
  }

  static String _slugify(String name) =>
      name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '_').replaceAll(RegExp(r'_+$'), '');

  static List<String> _aliasesForFederal(String name) {
    final lower = name.toLowerCase();
    final aliases = <String>[lower];
    if (lower.contains('martin luther king')) {
      aliases.addAll(['mlk', 'mlk day', 'martin luther king']);
    }
    if (lower.contains("presidents")) {
      aliases.addAll(["presidents day", "president's day", 'washington birthday']);
    }
    if (lower.contains('juneteenth')) {
      aliases.addAll(['juneteenth', 'freedom day']);
    }
    if (lower.contains('columbus')) {
      aliases.addAll(['columbus day', 'indigenous peoples day', 'indigenous peoples']);
    }
    if (lower.contains('veterans')) {
      aliases.addAll(['veterans day', 'veteran']);
    }
    if (lower.contains('labor')) {
      aliases.addAll(['labor day']);
    }
    return aliases;
  }

  /// Derive a rough human-readable name from RGB.
  static String _colorName(int r, int g, int b) {
    if (r > 240 && g > 240 && b > 240) return 'White';
    if (r < 15 && g < 15 && b < 15) return 'Black';
    if (r > 200 && g < 80 && b < 80) return 'Red';
    if (r < 80 && g > 200 && b < 80) return 'Green';
    if (r < 80 && g < 80 && b > 200) return 'Blue';
    if (r > 200 && g > 180 && b < 80) return 'Gold';
    if (r > 200 && g > 100 && b < 60) return 'Orange';
    if (r > 150 && g < 80 && b > 150) return 'Purple';
    if (r > 150 && g > 150 && b > 150) return 'Silver';
    if (r > 200 && g > 100 && b > 150) return 'Pink';
    if (r < 80 && g > 150 && b > 150) return 'Teal';
    return 'Color($r,$g,$b)';
  }

  // -----------------------------------------------------------------------
  // 3. New cultural / awareness events
  // -----------------------------------------------------------------------

  static const _culturalEvents = <HolidayColorEntry>[
    // -- Diwali --
    HolidayColorEntry(
      id: 'diwali',
      name: 'Diwali',
      aliases: ['diwali', 'deepavali', 'festival of lights'],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Diya Orange', 0xFFFF8C00),
        TeamColor.hex('Gold', 0xFFFFD700),
        TeamColor.hex('Red', 0xFFFF0000),
      ],
      suggestedEffects: [63, 43, 2, 0], // Candle, Twinkle, Breathe, Solid
      defaultSpeed: 70,
      defaultIntensity: 180,
      month: 10, // typically October-November
    ),

    // -- Lunar New Year / Chinese New Year --
    HolidayColorEntry(
      id: 'lunar_new_year',
      name: 'Lunar New Year',
      aliases: [
        'lunar new year',
        'chinese new year',
        'spring festival',
        'cny',
      ],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Lucky Red', 0xFFFF0000),
        TeamColor.hex('Imperial Gold', 0xFFFFD700),
        TeamColor.hex('Mandarin Orange', 0xFFFF8C00),
      ],
      suggestedEffects: [52, 12, 43, 0], // Fireworks, Theater Chase, Twinkle, Solid
      defaultSpeed: 80,
      defaultIntensity: 180,
      month: 1, // typically January-February
    ),

    // -- Hanukkah --
    HolidayColorEntry(
      id: 'hanukkah',
      name: 'Hanukkah',
      aliases: [
        'hanukkah',
        'chanukah',
        'festival of lights jewish',
      ],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Hanukkah Blue', 0xFF0000FF),
        TeamColor.hex('White', 0xFFFFFFFF),
        TeamColor.hex('Silver', 0xFFC0C0C0),
      ],
      suggestedEffects: [63, 43, 2, 0], // Candle, Twinkle, Breathe, Solid
      defaultSpeed: 60,
      defaultIntensity: 150,
      month: 12, // typically November-December
    ),

    // -- Kwanzaa --
    HolidayColorEntry(
      id: 'kwanzaa',
      name: 'Kwanzaa',
      aliases: ['kwanzaa'],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Red', 0xFFFF0000),
        TeamColor.hex('Black', 0xFF000000),
        TeamColor.hex('Green', 0xFF00FF00),
      ],
      suggestedEffects: [63, 2, 0], // Candle, Breathe, Solid
      defaultSpeed: 60,
      defaultIntensity: 140,
      month: 12,
      day: 26,
    ),

    // -- Cinco de Mayo --
    HolidayColorEntry(
      id: 'cinco_de_mayo',
      name: 'Cinco de Mayo',
      aliases: ['cinco de mayo', 'cinco'],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Mexican Green', 0xFF00FF00),
        TeamColor.hex('White', 0xFFFFFFFF),
        TeamColor.hex('Mexican Red', 0xFFFF0000),
      ],
      suggestedEffects: [12, 41, 52, 0], // Theater Chase, Running, Fireworks, Solid
      defaultSpeed: 100,
      defaultIntensity: 180,
      month: 5,
      day: 5,
    ),

    // -- Mardi Gras --
    HolidayColorEntry(
      id: 'mardi_gras',
      name: 'Mardi Gras',
      aliases: ['mardi gras', 'fat tuesday', 'carnival'],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Justice Purple', 0xFF800080),
        TeamColor.hex('Faith Gold', 0xFFFFD700),
        TeamColor.hex('Power Green', 0xFF00FF00),
      ],
      suggestedEffects: [12, 41, 43, 52], // Theater Chase, Running, Twinkle, Fireworks
      defaultSpeed: 100,
      defaultIntensity: 200,
      month: 2, // typically February-March
    ),

    // -- Day of the Dead --
    HolidayColorEntry(
      id: 'day_of_the_dead',
      name: 'Day of the Dead',
      aliases: [
        'day of the dead',
        'dia de los muertos',
        'dia de muertos',
      ],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Marigold Orange', 0xFFFF8C00),
        TeamColor.hex('Purple', 0xFF800080),
        TeamColor.hex('Yellow', 0xFFFFFF00),
        TeamColor.hex('Black', 0xFF000000),
      ],
      suggestedEffects: [63, 43, 2, 0], // Candle, Twinkle, Breathe, Solid
      defaultSpeed: 70,
      defaultIntensity: 150,
      month: 11,
      day: 1,
    ),

    // -- Pride Month --
    HolidayColorEntry(
      id: 'pride',
      name: 'Pride Month',
      aliases: ['pride', 'pride month', 'lgbtq', 'rainbow'],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Red', 0xFFFF0000),
        TeamColor.hex('Orange', 0xFFFF8C00),
        TeamColor.hex('Yellow', 0xFFFFFF00),
        TeamColor.hex('Green', 0xFF00FF00),
        TeamColor.hex('Blue', 0xFF0000FF),
        TeamColor.hex('Purple', 0xFF800080),
      ],
      suggestedEffects: [9, 10, 41, 0], // Rainbow, Rainbow Cycle, Running, Solid
      defaultSpeed: 128,
      defaultIntensity: 200,
      month: 6,
    ),

    // -- Earth Day --
    HolidayColorEntry(
      id: 'earth_day',
      name: 'Earth Day',
      aliases: ['earth day'],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Forest Green', 0xFF228B22),
        TeamColor.hex('Ocean Blue', 0xFF0000FF),
        TeamColor.hex('Cloud White', 0xFFFFFFFF),
      ],
      suggestedEffects: [2, 110, 0], // Breathe, Flow, Solid
      defaultSpeed: 60,
      defaultIntensity: 140,
      month: 4,
      day: 22,
    ),

    // -- Breast Cancer Awareness --
    HolidayColorEntry(
      id: 'breast_cancer_awareness',
      name: 'Breast Cancer Awareness',
      aliases: [
        'breast cancer awareness',
        'pink ribbon',
        'think pink',
      ],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Awareness Pink', 0xFFFF69B4),
        TeamColor.hex('White', 0xFFFFFFFF),
      ],
      suggestedEffects: [2, 0], // Breathe, Solid
      defaultSpeed: 50,
      defaultIntensity: 128,
      month: 10,
    ),

    // -- Eid al-Fitr --
    HolidayColorEntry(
      id: 'eid_al_fitr',
      name: 'Eid al-Fitr',
      aliases: ['eid', 'eid al fitr', 'eid ul fitr'],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Green', 0xFF00FF00),
        TeamColor.hex('Gold', 0xFFFFD700),
        TeamColor.hex('White', 0xFFFFFFFF),
      ],
      suggestedEffects: [43, 2, 0], // Twinkle, Breathe, Solid
      defaultSpeed: 70,
      defaultIntensity: 150,
      // Floating - depends on Islamic calendar; no fixed month/day
    ),

    // -- Eid al-Adha --
    HolidayColorEntry(
      id: 'eid_al_adha',
      name: 'Eid al-Adha',
      aliases: ['eid al adha', 'eid ul adha'],
      type: HolidayType.cultural,
      colors: [
        TeamColor.hex('Green', 0xFF00FF00),
        TeamColor.hex('Gold', 0xFFFFD700),
        TeamColor.hex('White', 0xFFFFFFFF),
      ],
      suggestedEffects: [43, 2, 0], // Twinkle, Breathe, Solid
      defaultSpeed: 70,
      defaultIntensity: 150,
      // Floating - depends on Islamic calendar; no fixed month/day
    ),

    // -- New Year's Eve --
    HolidayColorEntry(
      id: 'new_years_eve',
      name: "New Year's Eve",
      aliases: ['new years eve', 'nye', 'new year'],
      type: HolidayType.popular,
      colors: [
        TeamColor.hex('Gold', 0xFFFFD700),
        TeamColor.hex('Silver', 0xFFC0C0C0),
        TeamColor.hex('Black', 0xFF000000),
      ],
      suggestedEffects: [52, 43, 87, 0], // Fireworks, Twinkle, Glitter, Solid
      defaultSpeed: 128,
      defaultIntensity: 200,
      month: 12,
      day: 31,
    ),

    // -- Memorial Day --
    HolidayColorEntry(
      id: 'memorial_day',
      name: 'Memorial Day',
      aliases: ['memorial day'],
      type: HolidayType.federal,
      colors: [
        TeamColor.hex('Red', 0xFFFF0000),
        TeamColor.hex('White', 0xFFFFFFFF),
        TeamColor.hex('Blue', 0xFF0000FF),
      ],
      suggestedEffects: [0], // Solid - respectful
      defaultSpeed: 128,
      defaultIntensity: 128,
      isColorful: false,
      month: 5, // floating - last Monday of May
    ),

    // -- Labor Day --
    HolidayColorEntry(
      id: 'labor_day',
      name: 'Labor Day',
      aliases: ['labor day'],
      type: HolidayType.federal,
      colors: [
        TeamColor.hex('Red', 0xFFFF0000),
        TeamColor.hex('White', 0xFFFFFFFF),
        TeamColor.hex('Blue', 0xFF0000FF),
      ],
      suggestedEffects: [0], // Solid
      defaultSpeed: 128,
      defaultIntensity: 128,
      isColorful: false,
      month: 9, // floating - first Monday of September
    ),
  ];

  // -----------------------------------------------------------------------
  // resolve()
  // -----------------------------------------------------------------------

  /// Resolve a free-text query to the best-matching holiday / event entry.
  ///
  /// Scoring strategy:
  /// - Exact alias match -> 1.0
  /// - Alias starts-with or ends-with match -> 0.9
  /// - Alias contains or is contained -> 0.8
  /// - ID exact match -> 1.0
  /// - ID partial match -> 0.75
  /// - Word overlap -> 0.7
  /// - Temporal fallback (generic keywords + current month) -> 0.5-0.6
  static HolidayResolverResult resolve(String query) {
    final q = _normalize(query);
    if (q.isEmpty) return const HolidayResolverResult.empty();

    final scores = <HolidayColorEntry, double>{};

    for (final entry in allEntries) {
      double best = 0.0;

      // --- ID matching ---
      final nId = _normalize(entry.id);
      if (nId == q) {
        best = 1.0;
      } else if (nId.contains(q) || q.contains(nId)) {
        best = best > 0.75 ? best : 0.75;
      }

      // --- Alias matching ---
      for (final alias in entry.aliases) {
        final na = _normalize(alias);
        if (na == q) {
          best = 1.0;
          break; // can't beat 1.0
        }
        if (na.startsWith(q) || q.startsWith(na)) {
          best = best > 0.9 ? best : 0.9;
        }
        if (na.contains(q) || q.contains(na)) {
          best = best > 0.8 ? best : 0.8;
        }
      }
      if (best >= 1.0) {
        scores[entry] = best;
        continue;
      }

      // --- Name matching ---
      final nName = _normalize(entry.name);
      if (nName == q) {
        best = 1.0;
      } else if (nName.startsWith(q) || q.startsWith(nName)) {
        best = best > 0.9 ? best : 0.9;
      } else if (nName.contains(q) || q.contains(nName)) {
        best = best > 0.8 ? best : 0.8;
      }

      // --- Word overlap ---
      if (best < 0.7) {
        final qWords = q.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
        final entryWords = <String>{
          ..._normalize(entry.name).split(RegExp(r'\s+')),
          ...entry.aliases.expand((a) => _normalize(a).split(RegExp(r'\s+'))),
        }.where((w) => w.length > 2).toSet();
        final overlap = qWords.intersection(entryWords).length;
        if (overlap > 0) {
          final overlapScore = 0.5 + (overlap / (qWords.length + 1)) * 0.2;
          best = best > overlapScore ? best : overlapScore;
        }
      }

      // --- Temporal context fallback ---
      if (best < 0.5) {
        final temporalScore = _temporalBoost(q, entry);
        best = best > temporalScore ? best : temporalScore;
      }

      if (best > 0.0) {
        scores[entry] = best;
      }
    }

    if (scores.isEmpty) {
      return const HolidayResolverResult.empty();
    }

    // Sort by score descending
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final bestEntry = sorted.first;
    final alternatives = sorted.length > 1
        ? sorted.skip(1).take(5).map((e) => e.key).toList()
        : <HolidayColorEntry>[];

    return HolidayResolverResult(
      resolved: true,
      holiday: bestEntry.key,
      confidence: bestEntry.value,
      alternatives: alternatives,
    );
  }

  /// Normalize a string for matching: lowercase, strip punctuation, collapse
  /// whitespace.
  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[''`]"), '')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Give a small temporal boost when generic keywords are used and the
  /// current date aligns with a holiday.
  static double _temporalBoost(String query, HolidayColorEntry entry) {
    final genericKeywords = {
      'holiday',
      'festive',
      'celebration',
      'lights',
      'seasonal',
      'whats coming up',
      'upcoming',
    };
    final isGeneric = genericKeywords.any((kw) => query.contains(kw));
    if (!isGeneric) return 0.0;

    final now = DateTime.now();
    if (entry.month == null) return 0.0;
    final monthDiff = (entry.month! - now.month).abs();
    if (monthDiff == 0) return 0.6;
    if (monthDiff == 1 || monthDiff == 11) return 0.5;
    return 0.0;
  }

  // -----------------------------------------------------------------------
  // getCurrentSeason()
  // -----------------------------------------------------------------------

  /// Return the season entry matching the current calendar month.
  ///
  /// March-May -> Spring, June-August -> Summer,
  /// September-November -> Autumn, December-February -> Winter.
  static HolidayColorEntry getCurrentSeason() {
    final month = DateTime.now().month;
    final String seasonId;
    if (month >= 3 && month <= 5) {
      seasonId = 'spring';
    } else if (month >= 6 && month <= 8) {
      seasonId = 'summer';
    } else if (month >= 9 && month <= 11) {
      seasonId = 'autumn';
    } else {
      seasonId = 'winter';
    }
    return allEntries.firstWhere(
      (e) => e.id == seasonId,
      orElse: () => allEntries.firstWhere((e) => e.type == HolidayType.season),
    );
  }

  // -----------------------------------------------------------------------
  // getUpcomingHoliday()
  // -----------------------------------------------------------------------

  /// Return the next holiday (non-season) that falls within [withinDays]
  /// from today, or `null` if none is upcoming.
  ///
  /// Uses [USFederalHolidays] for accurate floating-date calculations and
  /// falls back to the month/day hints in [allEntries].
  static HolidayColorEntry? getUpcomingHoliday({int withinDays = 14}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final horizon = today.add(Duration(days: withinDays));

    // Build candidate list with accurate dates
    final candidates = <MapEntry<HolidayColorEntry, DateTime>>[];

    // Accurate dates from USFederalHolidays
    final federalThisYear = [
      ...USFederalHolidays.getHolidaysForYear(now.year),
      ...USFederalHolidays.getPopularHolidaysForYear(now.year),
    ];

    for (final entry in allEntries) {
      if (entry.type == HolidayType.season) continue;

      // Try to find an accurate date from USFederalHolidays
      DateTime? accurateDate;
      for (final fh in federalThisYear) {
        if (_normalize(fh.name) == _normalize(entry.name) ||
            entry.aliases.any((a) => _normalize(a) == _normalize(fh.name))) {
          accurateDate = fh.date;
          break;
        }
      }

      // Fall back to month/day hints
      accurateDate ??= (entry.month != null && entry.day != null)
          ? DateTime(now.year, entry.month!, entry.day!)
          : null;

      if (accurateDate == null) continue;

      final d = DateTime(accurateDate.year, accurateDate.month, accurateDate.day);
      if (!d.isBefore(today) && !d.isAfter(horizon)) {
        candidates.add(MapEntry(entry, d));
      }
    }

    if (candidates.isEmpty) return null;

    // Sort by date ascending to get the soonest
    candidates.sort((a, b) => a.value.compareTo(b.value));
    return candidates.first.key;
  }

  // -----------------------------------------------------------------------
  // getUserFavoriteHolidays()
  // -----------------------------------------------------------------------

  /// Filter [allEntries] to only those whose [id] appears in [favorites].
  static List<HolidayColorEntry> getUserFavoriteHolidays(
      List<String> favorites) {
    final set = favorites.map((f) => f.toLowerCase()).toSet();
    return allEntries.where((e) => set.contains(e.id.toLowerCase())).toList();
  }
}
