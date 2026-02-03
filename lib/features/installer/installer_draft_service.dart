import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';

/// Service for persisting and restoring installer wizard drafts.
///
/// Saves wizard progress to SharedPreferences so installers can resume
/// interrupted installations without losing data.
class InstallerDraftService {
  static const String _draftKey = 'installer_wizard_draft';

  /// Save a draft to persistent storage
  static Future<void> saveDraft(InstallerDraft draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = draft.toJsonString();
      await prefs.setString(_draftKey, jsonString);
      debugPrint('InstallerDraft: Saved draft for ${draft.customerName}');
    } catch (e) {
      debugPrint('InstallerDraft: Error saving draft: $e');
    }
  }

  /// Load a draft from persistent storage
  static Future<InstallerDraft?> loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_draftKey);
      if (jsonString == null || jsonString.isEmpty) {
        return null;
      }
      final draft = InstallerDraft.fromJsonString(jsonString);
      debugPrint('InstallerDraft: Loaded draft for ${draft.customerName}');
      return draft;
    } catch (e) {
      debugPrint('InstallerDraft: Error loading draft: $e');
      // If draft is corrupted, clear it
      await clearDraft();
      return null;
    }
  }

  /// Clear any saved draft
  static Future<void> clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
      debugPrint('InstallerDraft: Cleared draft');
    } catch (e) {
      debugPrint('InstallerDraft: Error clearing draft: $e');
    }
  }

  /// Check if a draft exists without loading it
  static Future<bool> hasDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_draftKey);
      return jsonString != null && jsonString.isNotEmpty;
    } catch (e) {
      debugPrint('InstallerDraft: Error checking for draft: $e');
      return false;
    }
  }

  /// Get draft metadata without loading full draft (for resume dialog)
  static Future<DraftMetadata?> getDraftMetadata() async {
    try {
      final draft = await loadDraft();
      if (draft == null) return null;
      return DraftMetadata(
        customerName: draft.customerName,
        savedAt: draft.savedAt,
        stepIndex: draft.currentStepIndex,
      );
    } catch (e) {
      debugPrint('InstallerDraft: Error getting draft metadata: $e');
      return null;
    }
  }
}

/// Lightweight metadata about a saved draft for display in resume dialog
class DraftMetadata {
  final String customerName;
  final DateTime savedAt;
  final int stepIndex;

  const DraftMetadata({
    required this.customerName,
    required this.savedAt,
    required this.stepIndex,
  });

  /// Format saved date for display
  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(savedAt);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minutes ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hours ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      // Format as date
      return '${savedAt.month}/${savedAt.day}/${savedAt.year}';
    }
  }

  /// Get step name from index
  String get stepName {
    switch (stepIndex) {
      case 0:
        return 'Customer Info';
      case 1:
        return 'Controller Setup';
      case 2:
        return 'Zone Configuration';
      case 3:
        return 'Handoff';
      default:
        return 'Step ${stepIndex + 1}';
    }
  }
}
