import 'package:cloud_firestore/cloud_firestore.dart';

/// Audience target for a [NetworkAnnouncement].
enum AnnouncementAudience {
  allDealers,
  installers,
  salesTeam,
  all,
}

extension AnnouncementAudienceX on AnnouncementAudience {
  String get label {
    switch (this) {
      case AnnouncementAudience.allDealers:
        return 'All dealers';
      case AnnouncementAudience.installers:
        return 'Installers';
      case AnnouncementAudience.salesTeam:
        return 'Sales team';
      case AnnouncementAudience.all:
        return 'Everyone';
    }
  }

  static AnnouncementAudience fromString(String? s) =>
      AnnouncementAudience.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AnnouncementAudience.all,
      );
}

/// Network-wide announcement published from the corporate Admin tab.
///
/// Stored at `app_config/announcements/items/{auto}`.
class NetworkAnnouncement {
  final String id;
  final String title;
  final String body;
  final AnnouncementAudience audience;
  final DateTime createdAt;
  final String createdByUid;
  final bool isActive;

  const NetworkAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.createdAt,
    required this.createdByUid,
    required this.isActive,
  });

  NetworkAnnouncement copyWith({
    String? id,
    String? title,
    String? body,
    AnnouncementAudience? audience,
    DateTime? createdAt,
    String? createdByUid,
    bool? isActive,
  }) {
    return NetworkAnnouncement(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      audience: audience ?? this.audience,
      createdAt: createdAt ?? this.createdAt,
      createdByUid: createdByUid ?? this.createdByUid,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'audience': audience.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'createdByUid': createdByUid,
        'isActive': isActive,
      };

  factory NetworkAnnouncement.fromJson(Map<String, dynamic> j) {
    return NetworkAnnouncement(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      audience: AnnouncementAudienceX.fromString(j['audience'] as String?),
      createdAt:
          (j['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdByUid: j['createdByUid'] as String? ?? '',
      isActive: j['isActive'] as bool? ?? true,
    );
  }
}
