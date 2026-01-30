/// Granular permissions for sub-users.
///
/// Primary users can customize what sub-users are allowed to do
/// when inviting them to share access to their system.
class SubUserPermissions {
  /// Can turn lights on/off.
  final bool canControl;

  /// Can change patterns/effects/colors.
  final bool canChangePatterns;

  /// Can modify schedules and automations.
  final bool canEditSchedules;

  /// Can invite other sub-users (if within limit).
  final bool canInvite;

  /// Can access system settings (brightness limits, etc.).
  final bool canAccessSettings;

  const SubUserPermissions({
    this.canControl = true,
    this.canChangePatterns = true,
    this.canEditSchedules = false,
    this.canInvite = false,
    this.canAccessSettings = false,
  });

  /// Basic permissions - control and patterns only.
  static const basic = SubUserPermissions(
    canControl: true,
    canChangePatterns: true,
    canEditSchedules: false,
    canInvite: false,
    canAccessSettings: false,
  );

  /// Full permissions - everything except owner-only actions.
  static const full = SubUserPermissions(
    canControl: true,
    canChangePatterns: true,
    canEditSchedules: true,
    canInvite: true,
    canAccessSettings: true,
  );

  /// No permissions - view only.
  static const viewOnly = SubUserPermissions(
    canControl: false,
    canChangePatterns: false,
    canEditSchedules: false,
    canInvite: false,
    canAccessSettings: false,
  );

  Map<String, dynamic> toJson() => {
        'can_control': canControl,
        'can_change_patterns': canChangePatterns,
        'can_edit_schedules': canEditSchedules,
        'can_invite': canInvite,
        'can_access_settings': canAccessSettings,
      };

  factory SubUserPermissions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return SubUserPermissions.basic;
    return SubUserPermissions(
      canControl: json['can_control'] as bool? ?? true,
      canChangePatterns: json['can_change_patterns'] as bool? ?? true,
      canEditSchedules: json['can_edit_schedules'] as bool? ?? false,
      canInvite: json['can_invite'] as bool? ?? false,
      canAccessSettings: json['can_access_settings'] as bool? ?? false,
    );
  }

  SubUserPermissions copyWith({
    bool? canControl,
    bool? canChangePatterns,
    bool? canEditSchedules,
    bool? canInvite,
    bool? canAccessSettings,
  }) =>
      SubUserPermissions(
        canControl: canControl ?? this.canControl,
        canChangePatterns: canChangePatterns ?? this.canChangePatterns,
        canEditSchedules: canEditSchedules ?? this.canEditSchedules,
        canInvite: canInvite ?? this.canInvite,
        canAccessSettings: canAccessSettings ?? this.canAccessSettings,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubUserPermissions &&
          canControl == other.canControl &&
          canChangePatterns == other.canChangePatterns &&
          canEditSchedules == other.canEditSchedules &&
          canInvite == other.canInvite &&
          canAccessSettings == other.canAccessSettings;

  @override
  int get hashCode => Object.hash(
        canControl,
        canChangePatterns,
        canEditSchedules,
        canInvite,
        canAccessSettings,
      );
}
