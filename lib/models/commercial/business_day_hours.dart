/// Operating hours for a single day of the week.
class BusinessDayHours {
  final bool isOpen;
  final String? openTime;
  final String? closeTime;

  const BusinessDayHours({
    this.isOpen = false,
    this.openTime,
    this.closeTime,
  });

  factory BusinessDayHours.fromJson(Map<String, dynamic> json) {
    return BusinessDayHours(
      isOpen: (json['is_open'] as bool?) ?? false,
      openTime: json['open_time'] as String?,
      closeTime: json['close_time'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'is_open': isOpen,
        if (openTime != null) 'open_time': openTime,
        if (closeTime != null) 'close_time': closeTime,
      };

  BusinessDayHours copyWith({
    bool? isOpen,
    String? openTime,
    String? closeTime,
  }) {
    return BusinessDayHours(
      isOpen: isOpen ?? this.isOpen,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
    );
  }

  /// Returns true if the current time of day falls within openTime..closeTime.
  bool isCurrentlyOpen() {
    if (!isOpen || openTime == null || closeTime == null) return false;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final openMinutes = _parseMinutes(openTime!);
    final closeMinutes = _parseMinutes(closeTime!);
    if (openMinutes == null || closeMinutes == null) return false;
    if (closeMinutes > openMinutes) {
      return nowMinutes >= openMinutes && nowMinutes < closeMinutes;
    }
    // Overnight span (e.g. 22:00 – 02:00)
    return nowMinutes >= openMinutes || nowMinutes < closeMinutes;
  }

  static int? _parseMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}
