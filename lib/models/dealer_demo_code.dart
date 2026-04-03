import 'package:cloud_firestore/cloud_firestore.dart';

/// A dealer-issued demo code that gates access to the demo experience.
class DealerDemoCode {
  final String code;
  final String dealerCode;
  final String dealerName;
  final String market;
  final bool isActive;
  final int usageCount;
  final int? maxUses;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const DealerDemoCode({
    required this.code,
    required this.dealerCode,
    required this.dealerName,
    required this.market,
    this.isActive = true,
    this.usageCount = 0,
    this.maxUses,
    required this.createdAt,
    this.expiresAt,
  });

  factory DealerDemoCode.fromJson(Map<String, dynamic> json) {
    return DealerDemoCode(
      code: json['code'] as String,
      dealerCode: json['dealerCode'] as String,
      dealerName: json['dealerName'] as String,
      market: (json['market'] ?? json['Market'] ?? '') as String,
      isActive: json['isActive'] as bool? ?? true,
      usageCount: json['usageCount'] as int? ?? 0,
      maxUses: json['maxUses'] as int?,
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.parse(json['createdAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? json['expiresAt'] is Timestamp
              ? (json['expiresAt'] as Timestamp).toDate()
              : DateTime.parse(json['expiresAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'dealerCode': dealerCode,
      'dealerName': dealerName,
      'market': market,
      'isActive': isActive,
      'usageCount': usageCount,
      if (maxUses != null) 'maxUses': maxUses,
      'createdAt': Timestamp.fromDate(createdAt),
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
    };
  }

  DealerDemoCode copyWith({
    String? code,
    String? dealerCode,
    String? dealerName,
    String? market,
    bool? isActive,
    int? usageCount,
    int? maxUses,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return DealerDemoCode(
      code: code ?? this.code,
      dealerCode: dealerCode ?? this.dealerCode,
      dealerName: dealerName ?? this.dealerName,
      market: market ?? this.market,
      isActive: isActive ?? this.isActive,
      usageCount: usageCount ?? this.usageCount,
      maxUses: maxUses ?? this.maxUses,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
