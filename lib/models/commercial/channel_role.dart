import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Coverage policy for a commercial lighting channel.
enum CoveragePolicy {
  alwaysOn,
  smartFill,
  scheduledOnly,
}

/// Daylight suppression behaviour when suppression is active.
enum DaylightMode {
  softDim,
  hardOff,
  disabled,
}

/// The physical role a lighting channel plays in a commercial venue.
enum ChannelRoleType {
  interior,
  outdoorFacade,
  windowDisplay,
  patio,
  canopy,
  signage,
}

// ---------------------------------------------------------------------------
// ChannelRoleType helpers
// ---------------------------------------------------------------------------

extension ChannelRoleTypeX on ChannelRoleType {
  /// Human-readable display name.
  String get displayName {
    switch (this) {
      case ChannelRoleType.interior:
        return 'Interior';
      case ChannelRoleType.outdoorFacade:
        return 'Outdoor Façade';
      case ChannelRoleType.windowDisplay:
        return 'Window Display';
      case ChannelRoleType.patio:
        return 'Patio';
      case ChannelRoleType.canopy:
        return 'Canopy';
      case ChannelRoleType.signage:
        return 'Signage / Accent';
    }
  }

  /// Material icon reference for UI tiles.
  IconData get icon {
    switch (this) {
      case ChannelRoleType.interior:
        return Icons.chair;
      case ChannelRoleType.outdoorFacade:
        return Icons.storefront;
      case ChannelRoleType.windowDisplay:
        return Icons.window;
      case ChannelRoleType.patio:
        return Icons.deck;
      case ChannelRoleType.canopy:
        return Icons.roofing;
      case ChannelRoleType.signage:
        return Icons.signpost;
    }
  }

  /// Default coverage policy for this role.
  CoveragePolicy get defaultCoveragePolicy {
    switch (this) {
      case ChannelRoleType.interior:
        return CoveragePolicy.smartFill;
      case ChannelRoleType.outdoorFacade:
        return CoveragePolicy.alwaysOn;
      case ChannelRoleType.windowDisplay:
        return CoveragePolicy.smartFill;
      case ChannelRoleType.patio:
        return CoveragePolicy.scheduledOnly;
      case ChannelRoleType.canopy:
        return CoveragePolicy.alwaysOn;
      case ChannelRoleType.signage:
        return CoveragePolicy.alwaysOn;
    }
  }

  /// Whether daylight suppression should default to enabled.
  bool get defaultDaylightSuppression {
    switch (this) {
      case ChannelRoleType.interior:
      case ChannelRoleType.windowDisplay:
        return false;
      case ChannelRoleType.outdoorFacade:
      case ChannelRoleType.patio:
      case ChannelRoleType.canopy:
      case ChannelRoleType.signage:
        return true;
    }
  }

  /// Whether this is an outdoor role.
  bool get isOutdoor => defaultDaylightSuppression;
}

// ---------------------------------------------------------------------------
// Serialization helpers
// ---------------------------------------------------------------------------

CoveragePolicy _parseCoveragePolicy(String? value) {
  switch (value) {
    case 'always_on':
      return CoveragePolicy.alwaysOn;
    case 'smart_fill':
      return CoveragePolicy.smartFill;
    case 'scheduled_only':
      return CoveragePolicy.scheduledOnly;
    default:
      return CoveragePolicy.smartFill;
  }
}

String _coveragePolicyToJson(CoveragePolicy p) {
  switch (p) {
    case CoveragePolicy.alwaysOn:
      return 'always_on';
    case CoveragePolicy.smartFill:
      return 'smart_fill';
    case CoveragePolicy.scheduledOnly:
      return 'scheduled_only';
  }
}

DaylightMode _parseDaylightMode(String? value) {
  switch (value) {
    case 'soft_dim':
      return DaylightMode.softDim;
    case 'hard_off':
      return DaylightMode.hardOff;
    case 'disabled':
      return DaylightMode.disabled;
    default:
      return DaylightMode.softDim;
  }
}

String _daylightModeToJson(DaylightMode m) {
  switch (m) {
    case DaylightMode.softDim:
      return 'soft_dim';
    case DaylightMode.hardOff:
      return 'hard_off';
    case DaylightMode.disabled:
      return 'disabled';
  }
}

ChannelRoleType _parseRoleType(String? value) {
  switch (value) {
    case 'interior':
      return ChannelRoleType.interior;
    case 'outdoorFacade':
      return ChannelRoleType.outdoorFacade;
    case 'windowDisplay':
      return ChannelRoleType.windowDisplay;
    case 'patio':
      return ChannelRoleType.patio;
    case 'canopy':
      return ChannelRoleType.canopy;
    case 'signage':
      return ChannelRoleType.signage;
    default:
      return ChannelRoleType.interior;
  }
}

// ---------------------------------------------------------------------------
// ChannelRoleConfig — per-channel commercial configuration
// ---------------------------------------------------------------------------

/// Stores per-channel commercial configuration: role, coverage policy,
/// daylight suppression settings, and optional default design.
class ChannelRoleConfig {
  final String channelId;
  final String friendlyName;
  final ChannelRoleType role;
  final CoveragePolicy coveragePolicy;
  final bool daylightSuppression;
  final DaylightMode daylightMode;
  final String? defaultDesignId;

  const ChannelRoleConfig({
    required this.channelId,
    required this.friendlyName,
    required this.role,
    this.coveragePolicy = CoveragePolicy.smartFill,
    this.daylightSuppression = true,
    this.daylightMode = DaylightMode.softDim,
    this.defaultDesignId,
  });

  factory ChannelRoleConfig.fromJson(Map<String, dynamic> json) {
    return ChannelRoleConfig(
      channelId: json['channel_id'] as String,
      friendlyName: json['friendly_name'] as String,
      role: _parseRoleType(json['role'] as String?),
      coveragePolicy: _parseCoveragePolicy(json['coverage_policy'] as String?),
      daylightSuppression:
          (json['daylight_suppression'] as bool?) ?? true,
      daylightMode:
          _parseDaylightMode(json['daylight_mode'] as String?),
      defaultDesignId: json['default_design_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'channel_id': channelId,
        'friendly_name': friendlyName,
        'role': role.name,
        'coverage_policy': _coveragePolicyToJson(coveragePolicy),
        'daylight_suppression': daylightSuppression,
        'daylight_mode': _daylightModeToJson(daylightMode),
        if (defaultDesignId != null) 'default_design_id': defaultDesignId,
      };

  ChannelRoleConfig copyWith({
    String? channelId,
    String? friendlyName,
    ChannelRoleType? role,
    CoveragePolicy? coveragePolicy,
    bool? daylightSuppression,
    DaylightMode? daylightMode,
    String? defaultDesignId,
  }) {
    return ChannelRoleConfig(
      channelId: channelId ?? this.channelId,
      friendlyName: friendlyName ?? this.friendlyName,
      role: role ?? this.role,
      coveragePolicy: coveragePolicy ?? this.coveragePolicy,
      daylightSuppression:
          daylightSuppression ?? this.daylightSuppression,
      daylightMode: daylightMode ?? this.daylightMode,
      defaultDesignId: defaultDesignId ?? this.defaultDesignId,
    );
  }

  /// Whether this channel is an outdoor role (facade, patio, canopy, signage).
  bool get isOutdoorRole => role.isOutdoor;
}

/// Convenience alias used by UserModel and other consumers.
typedef ChannelRole = ChannelRoleConfig;
