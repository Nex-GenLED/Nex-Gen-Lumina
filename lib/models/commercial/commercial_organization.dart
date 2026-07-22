/// Top-level organization that owns one or more commercial locations.
class CommercialOrganization {
  final String orgId;
  final String orgName;
  final String ownerId;
  final String brandProfileId;
  final List<String> locationIds;
  final String? templateScheduleId;

  const CommercialOrganization({
    required this.orgId,
    required this.orgName,
    required this.ownerId,
    required this.brandProfileId,
    this.locationIds = const [],
    this.templateScheduleId,
  });

  factory CommercialOrganization.fromJson(Map<String, dynamic> json) {
    return CommercialOrganization(
      orgId: json['org_id'] as String,
      orgName: json['org_name'] as String,
      ownerId: json['owner_id'] as String,
      brandProfileId: json['brand_profile_id'] as String,
      locationIds: (json['location_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      templateScheduleId: json['template_schedule_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'org_id': orgId,
        'org_name': orgName,
        'owner_id': ownerId,
        'brand_profile_id': brandProfileId,
        'location_ids': locationIds,
        if (templateScheduleId != null)
          'template_schedule_id': templateScheduleId,
      };

  CommercialOrganization copyWith({
    String? orgId,
    String? orgName,
    String? ownerId,
    String? brandProfileId,
    List<String>? locationIds,
    String? templateScheduleId,
  }) {
    return CommercialOrganization(
      orgId: orgId ?? this.orgId,
      orgName: orgName ?? this.orgName,
      ownerId: ownerId ?? this.ownerId,
      brandProfileId: brandProfileId ?? this.brandProfileId,
      locationIds: locationIds ?? this.locationIds,
      templateScheduleId: templateScheduleId ?? this.templateScheduleId,
    );
  }
}
