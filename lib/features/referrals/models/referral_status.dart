import 'package:flutter/material.dart';
import 'package:nexgen_command/app_colors.dart';

enum ReferralStatus {
  lead,
  visitScheduled,
  estimateSent,
  confirmed,
  installing,
  installed,
  paid,
}

extension ReferralStatusX on ReferralStatus {
  String get label {
    switch (this) {
      case ReferralStatus.lead:
        return 'Lead';
      case ReferralStatus.visitScheduled:
        return 'Visit Scheduled';
      case ReferralStatus.estimateSent:
        return 'Estimate Sent';
      case ReferralStatus.confirmed:
        return 'Confirmed';
      case ReferralStatus.installing:
        return 'Installing';
      case ReferralStatus.installed:
        return 'Installed';
      case ReferralStatus.paid:
        return 'Paid';
    }
  }

  Color get color {
    switch (this) {
      case ReferralStatus.lead:
        return NexGenPalette.textMedium;
      case ReferralStatus.visitScheduled:
      case ReferralStatus.estimateSent:
      case ReferralStatus.confirmed:
      case ReferralStatus.installing:
        return NexGenPalette.amber;
      case ReferralStatus.installed:
      case ReferralStatus.paid:
        return NexGenPalette.green;
    }
  }

  double get progressFraction {
    switch (this) {
      case ReferralStatus.lead:
        return 0.14;
      case ReferralStatus.visitScheduled:
        return 0.28;
      case ReferralStatus.estimateSent:
        return 0.42;
      case ReferralStatus.confirmed:
        return 0.57;
      case ReferralStatus.installing:
        return 0.71;
      case ReferralStatus.installed:
        return 0.86;
      case ReferralStatus.paid:
        return 1.0;
    }
  }

  static ReferralStatus fromString(String s) {
    switch (s.toLowerCase().replaceAll(RegExp(r'[\s_]+'), '')) {
      case 'visitscheduled':
        return ReferralStatus.visitScheduled;
      case 'estimatesent':
        return ReferralStatus.estimateSent;
      case 'confirmed':
        return ReferralStatus.confirmed;
      case 'installing':
        return ReferralStatus.installing;
      case 'installed':
        return ReferralStatus.installed;
      case 'paid':
        return ReferralStatus.paid;
      default:
        return ReferralStatus.lead;
    }
  }
}
