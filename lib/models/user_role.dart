/// Installation access role in the Nex-Gen Lumina system.
///
/// Determines access level and permissions for installation control.
/// This is separate from the account type (residential, media, dealer, admin).
enum InstallationRole {
  /// Owner of an installation - full access to all features.
  /// Created by installer during system setup.
  primary,

  /// Invited user with limited permissions.
  /// Can control lights but cannot add controllers or manage system.
  subUser,

  /// Certified Nex-Gen installer.
  /// Can create installations and primary user accounts.
  installer,

  /// Nex-Gen staff with admin portal access.
  /// Can manage dealers, installers, and installations.
  admin,

  /// Downloaded app but not yet linked to any installation.
  /// Blocked from all app features until linked.
  unlinked,
}

extension InstallationRoleExtension on InstallationRole {
  String get displayName {
    switch (this) {
      case InstallationRole.primary:
        return 'Owner';
      case InstallationRole.subUser:
        return 'Family Member';
      case InstallationRole.installer:
        return 'Installer';
      case InstallationRole.admin:
        return 'Administrator';
      case InstallationRole.unlinked:
        return 'Unlinked';
    }
  }

  String toJson() => name;

  static InstallationRole fromJson(String? value) {
    if (value == null) return InstallationRole.unlinked;
    return InstallationRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => InstallationRole.unlinked,
    );
  }

  /// Whether this role can control lights (on/off, patterns, brightness).
  bool get canControl =>
      this == InstallationRole.primary ||
      this == InstallationRole.subUser ||
      this == InstallationRole.installer ||
      this == InstallationRole.admin;

  /// Whether this role can add new controllers via BLE pairing.
  bool get canPairControllers =>
      this == InstallationRole.primary ||
      this == InstallationRole.installer ||
      this == InstallationRole.admin;

  /// Whether this role can invite sub-users.
  bool get canInviteUsers =>
      this == InstallationRole.primary || this == InstallationRole.admin;

  /// Whether this role can access system settings.
  bool get canAccessSettings =>
      this == InstallationRole.primary ||
      this == InstallationRole.installer ||
      this == InstallationRole.admin;
}
