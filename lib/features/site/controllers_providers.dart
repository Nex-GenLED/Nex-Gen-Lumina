import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';

/// Streams the current user's controllers collection
final controllersStreamProvider = StreamProvider<List<ControllerInfo>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    debugPrint('🔒 controllersStreamProvider: No user logged in');
    return const Stream.empty();
  }

  debugPrint('📡 controllersStreamProvider: Listening to controllers for user ${user.uid}');

  // Don't use orderBy to avoid composite index requirement - we'll sort in memory
  final col = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('controllers');

  return col.snapshots().map((snap) {
    debugPrint('📦 controllersStreamProvider: Received ${snap.docs.length} controllers from Firestore');

    final controllers = snap.docs.map((d) {
      final data = d.data();
      final createdTs = data['createdAt'];
      final updatedTs = data['updatedAt'];

      debugPrint('   - Controller ${d.id}: name=${data['name']}, ip=${data['ip']}');

      return ControllerInfo(
        id: d.id,
        ip: (data['ip'] ?? '') as String,
        name: data['name'] as String?,
        serial: data['serial'] as String?,
        ssid: data['ssid'] as String?,
        wifiConfigured: data['wifiConfigured'] as bool?,
        createdAt: createdTs is Timestamp ? createdTs.toDate() : null,
        updatedAt: updatedTs is Timestamp ? updatedTs.toDate() : null,
      );
    }).toList();

    // Sort by createdAt in memory (newest first), putting nulls at the end
    controllers.sort((a, b) {
      if (a.createdAt == null && b.createdAt == null) return 0;
      if (a.createdAt == null) return 1;
      if (b.createdAt == null) return -1;
      return b.createdAt!.compareTo(a.createdAt!);
    });

    return controllers;
  });
});

/// Deletes a controller document by id
final deleteControllerProvider = Provider<Future<bool> Function(String)>((ref) {
  return (String id) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('controllers').doc(id).delete();
      return true;
    } catch (e) {
      debugPrint('Delete controller failed: $e');
      return false;
    }
  };
});

/// Renames a controller in Firestore
final renameControllerProvider = Provider<Future<bool> Function(String, String)>((ref) {
  return (String id, String newName) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('controllers')
          .doc(id)
          .update({
        'name': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Controller renamed to: $newName');
      return true;
    } catch (e) {
      debugPrint('Rename controller failed: $e');
      return false;
    }
  };
});

/// Auto-connects to the user's first saved controller when the app loads.
/// This provider should be watched early in the app (e.g., in MainScaffold).
/// It only sets the selectedDeviceIpProvider once when controllers first load.
///
/// Returns true if auto-connect was triggered, false otherwise.
final autoConnectControllerProvider = Provider<bool>((ref) {
  final controllersAsync = ref.watch(controllersStreamProvider);
  final currentSelection = ref.watch(selectedDeviceIpProvider);

  // If already connected, no action needed
  if (currentSelection != null) {
    return false;
  }

  bool triggered = false;
  controllersAsync.whenData((controllers) {
    if (controllers.isNotEmpty) {
      final firstController = controllers.first;
      if (firstController.ip.isNotEmpty) {
        debugPrint('🔌 Auto-connecting to saved controller: ${firstController.name ?? firstController.ip}');
        // Schedule the state update for after the current build phase
        Future.microtask(() {
          // Double-check selection is still null before setting
          final stillNull = ref.read(selectedDeviceIpProvider) == null;
          if (stillNull) {
            ref.read(selectedDeviceIpProvider.notifier).state = firstController.ip;
          }
        });
        triggered = true;
      }
    }
  });

  return triggered;
});
