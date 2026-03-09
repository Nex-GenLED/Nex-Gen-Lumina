/// Data class capturing Auto-Pilot preference profile during installer handoff.
class InstallerPreferenceDraft {
  final bool useSimpleMode;
  final List<String> sportsTeams;
  final List<String> favoriteHolidays;
  final double vibeLevel;
  final int changeToleranceLevel;
  final int autonomyLevel;
  final String profileType;
  final String? managerEmail;

  const InstallerPreferenceDraft({
    this.useSimpleMode = false,
    this.sportsTeams = const [],
    this.favoriteHolidays = const [],
    this.vibeLevel = 0.5,
    this.changeToleranceLevel = 3,
    this.autonomyLevel = 1,
    this.profileType = 'residential',
    this.managerEmail,
  });

  InstallerPreferenceDraft copyWith({
    bool? useSimpleMode,
    List<String>? sportsTeams,
    List<String>? favoriteHolidays,
    double? vibeLevel,
    int? changeToleranceLevel,
    int? autonomyLevel,
    String? profileType,
    String? managerEmail,
  }) {
    return InstallerPreferenceDraft(
      useSimpleMode: useSimpleMode ?? this.useSimpleMode,
      sportsTeams: sportsTeams ?? this.sportsTeams,
      favoriteHolidays: favoriteHolidays ?? this.favoriteHolidays,
      vibeLevel: vibeLevel ?? this.vibeLevel,
      changeToleranceLevel: changeToleranceLevel ?? this.changeToleranceLevel,
      autonomyLevel: autonomyLevel ?? this.autonomyLevel,
      profileType: profileType ?? this.profileType,
      managerEmail: managerEmail ?? this.managerEmail,
    );
  }

  Map<String, dynamic> toMap() => {
        'useSimpleMode': useSimpleMode,
        'sportsTeams': sportsTeams,
        'favoriteHolidays': favoriteHolidays,
        'vibeLevel': vibeLevel,
        'changeToleranceLevel': changeToleranceLevel,
        'autonomyLevel': autonomyLevel,
        'profileType': profileType,
        'managerEmail': managerEmail,
      };

  factory InstallerPreferenceDraft.fromMap(Map<String, dynamic> map) {
    return InstallerPreferenceDraft(
      useSimpleMode: map['useSimpleMode'] as bool? ?? false,
      sportsTeams: List<String>.from(map['sportsTeams'] as List? ?? []),
      favoriteHolidays: List<String>.from(map['favoriteHolidays'] as List? ?? []),
      vibeLevel: (map['vibeLevel'] as num?)?.toDouble() ?? 0.5,
      changeToleranceLevel: map['changeToleranceLevel'] as int? ?? 3,
      autonomyLevel: map['autonomyLevel'] as int? ?? 1,
      profileType: map['profileType'] as String? ?? 'residential',
      managerEmail: map['managerEmail'] as String?,
    );
  }
}
