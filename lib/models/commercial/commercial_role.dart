/// Role a user holds within the commercial organization hierarchy.
enum CommercialRole {
  storeStaff,
  storeManager,
  regionalManager,
  corporateAdmin,
}

extension CommercialRoleX on CommercialRole {
  String get displayName {
    switch (this) {
      case CommercialRole.storeStaff:
        return 'Store Staff';
      case CommercialRole.storeManager:
        return 'Store Manager';
      case CommercialRole.regionalManager:
        return 'Regional Manager';
      case CommercialRole.corporateAdmin:
        return 'Corporate Admin';
    }
  }

  /// Permission map for this role.
  Map<String, bool> get permissions {
    switch (this) {
      case CommercialRole.storeStaff:
        return const {
          'canViewOwnLocation': true,
          'canEditOwnSchedule': false,
          'canOverrideNow': false,
          'canViewAllLocations': false,
          'canPushToRegion': false,
          'canPushToAll': false,
          'canApplyCorporateLock': false,
          'canManageUsers': false,
          'canEditBrandColors': false,
        };
      case CommercialRole.storeManager:
        return const {
          'canViewOwnLocation': true,
          'canEditOwnSchedule': true,
          'canOverrideNow': true,
          'canViewAllLocations': false,
          'canPushToRegion': false,
          'canPushToAll': false,
          'canApplyCorporateLock': false,
          'canManageUsers': false,
          'canEditBrandColors': false,
        };
      case CommercialRole.regionalManager:
        return const {
          'canViewOwnLocation': true,
          'canEditOwnSchedule': true,
          'canOverrideNow': true,
          'canViewAllLocations': true,
          'canPushToRegion': true,
          'canPushToAll': false,
          'canApplyCorporateLock': false,
          'canManageUsers': true,
          'canEditBrandColors': false,
        };
      case CommercialRole.corporateAdmin:
        return const {
          'canViewOwnLocation': true,
          'canEditOwnSchedule': true,
          'canOverrideNow': true,
          'canViewAllLocations': true,
          'canPushToRegion': true,
          'canPushToAll': true,
          'canApplyCorporateLock': true,
          'canManageUsers': true,
          'canEditBrandColors': true,
        };
    }
  }

  /// Shorthand permission check.
  bool hasPermission(String permission) => permissions[permission] ?? false;
}

CommercialRole parseCommercialRole(String? value) {
  switch (value) {
    case 'storeStaff':
      return CommercialRole.storeStaff;
    case 'storeManager':
      return CommercialRole.storeManager;
    case 'regionalManager':
      return CommercialRole.regionalManager;
    case 'corporateAdmin':
      return CommercialRole.corporateAdmin;
    default:
      return CommercialRole.storeStaff;
  }
}
