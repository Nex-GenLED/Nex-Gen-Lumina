import 'package:nexgen_command/models/commercial/brand_color.dart';
import 'package:nexgen_command/models/commercial/business_day_hours.dart';

/// Full commercial business profile attached to a commercial UserModel.
class BusinessProfile {
  final String businessType;
  final String businessName;
  final String primaryAddress;
  final String? addressLatLng;
  final List<BrandColor> brandColors;
  final Map<String, BusinessDayHours> hoursOfOperation;
  final int preOpenBufferMinutes;
  final int postCloseWindDownMinutes;
  final List<String> customClosureDates;
  final bool observesUsHolidays;

  const BusinessProfile({
    required this.businessType,
    required this.businessName,
    required this.primaryAddress,
    this.addressLatLng,
    this.brandColors = const [],
    this.hoursOfOperation = const {},
    this.preOpenBufferMinutes = 30,
    this.postCloseWindDownMinutes = 15,
    this.customClosureDates = const [],
    this.observesUsHolidays = true,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      businessType: json['business_type'] as String,
      businessName: json['business_name'] as String,
      primaryAddress: json['primary_address'] as String,
      addressLatLng: json['address_lat_lng'] as String?,
      brandColors: (json['brand_colors'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => BrandColor.fromJson(e))
              .toList() ??
          const [],
      hoursOfOperation: (json['hours_of_operation'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(
                  k, BusinessDayHours.fromJson(v as Map<String, dynamic>))) ??
          const {},
      preOpenBufferMinutes:
          (json['pre_open_buffer_minutes'] as num?)?.toInt() ?? 30,
      postCloseWindDownMinutes:
          (json['post_close_wind_down_minutes'] as num?)?.toInt() ?? 15,
      customClosureDates: (json['custom_closure_dates'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      observesUsHolidays:
          (json['observes_us_holidays'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'business_type': businessType,
        'business_name': businessName,
        'primary_address': primaryAddress,
        if (addressLatLng != null) 'address_lat_lng': addressLatLng,
        'brand_colors': brandColors.map((e) => e.toJson()).toList(),
        'hours_of_operation':
            hoursOfOperation.map((k, v) => MapEntry(k, v.toJson())),
        'pre_open_buffer_minutes': preOpenBufferMinutes,
        'post_close_wind_down_minutes': postCloseWindDownMinutes,
        'custom_closure_dates': customClosureDates,
        'observes_us_holidays': observesUsHolidays,
      };

  BusinessProfile copyWith({
    String? businessType,
    String? businessName,
    String? primaryAddress,
    String? addressLatLng,
    List<BrandColor>? brandColors,
    Map<String, BusinessDayHours>? hoursOfOperation,
    int? preOpenBufferMinutes,
    int? postCloseWindDownMinutes,
    List<String>? customClosureDates,
    bool? observesUsHolidays,
  }) {
    return BusinessProfile(
      businessType: businessType ?? this.businessType,
      businessName: businessName ?? this.businessName,
      primaryAddress: primaryAddress ?? this.primaryAddress,
      addressLatLng: addressLatLng ?? this.addressLatLng,
      brandColors: brandColors ?? this.brandColors,
      hoursOfOperation: hoursOfOperation ?? this.hoursOfOperation,
      preOpenBufferMinutes:
          preOpenBufferMinutes ?? this.preOpenBufferMinutes,
      postCloseWindDownMinutes:
          postCloseWindDownMinutes ?? this.postCloseWindDownMinutes,
      customClosureDates:
          customClosureDates ?? this.customClosureDates,
      observesUsHolidays:
          observesUsHolidays ?? this.observesUsHolidays,
    );
  }
}
