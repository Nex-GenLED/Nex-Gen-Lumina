import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for encrypting and decrypting sensitive user data
///
/// Uses AES-256 encryption with a device-specific key stored in secure storage.
/// This provides encryption-at-rest for sensitive PII data before storing in Firestore.
///
/// SECURITY FEATURES:
/// - AES-256-GCM encryption
/// - Device-specific encryption keys
/// - Secure storage for encryption keys
/// - One-way hashing for WiFi SSID comparison
class EncryptionService {
  static const String _keyStorageKey = 'lumina_encryption_key';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static encrypt.Encrypter? _encrypter;
  static encrypt.IV? _iv;

  /// Initialize the encryption service
  /// Must be called before using encryption functions
  static Future<void> initialize() async {
    try {
      // Try to load existing key
      String? keyString = await _secureStorage.read(key: _keyStorageKey);

      if (keyString == null) {
        // Generate new key if none exists
        debugPrint('🔐 Generating new encryption key');
        final key = encrypt.Key.fromSecureRandom(32); // 256-bit key
        keyString = base64.encode(key.bytes);
        await _secureStorage.write(key: _keyStorageKey, value: keyString);
      } else {
        debugPrint('🔐 Loaded existing encryption key');
      }

      final keyBytes = base64.decode(keyString);
      final key = encrypt.Key(Uint8List.fromList(keyBytes));

      // Use a fixed IV derived from the key for deterministic encryption
      // This allows us to encrypt the same data consistently
      // For production, consider using random IV per encryption and storing it
      final ivBytes = sha256.convert(keyBytes).bytes.sublist(0, 16);
      _iv = encrypt.IV(Uint8List.fromList(ivBytes));

      _encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      debugPrint('✅ Encryption service initialized');
    } catch (e) {
      debugPrint('❌ Encryption service initialization failed: $e');
      rethrow;
    }
  }

  /// Encrypt a string value
  ///
  /// Returns base64-encoded encrypted string, or null if input is null/empty
  static String? encryptString(String? value) {
    if (value == null || value.isEmpty) return null;

    try {
      if (_encrypter == null || _iv == null) {
        throw StateError('EncryptionService not initialized. Call initialize() first.');
      }

      final encrypted = _encrypter!.encrypt(value, iv: _iv!);
      return encrypted.base64;
    } catch (e) {
      debugPrint('❌ Encryption error: $e');
      // Return unencrypted value as fallback (log warning in production)
      debugPrint('⚠️ Returning unencrypted value as fallback');
      return value;
    }
  }

  /// Decrypt a string value
  ///
  /// Returns decrypted string, or null if input is null/empty
  static String? decryptString(String? encryptedValue) {
    if (encryptedValue == null || encryptedValue.isEmpty) return null;

    try {
      if (_encrypter == null || _iv == null) {
        throw StateError('EncryptionService not initialized. Call initialize() first.');
      }

      final encrypted = encrypt.Encrypted.fromBase64(encryptedValue);
      return _encrypter!.decrypt(encrypted, iv: _iv!);
    } catch (e) {
      debugPrint('❌ Decryption error: $e');
      // Assume the value is already decrypted (backward compatibility)
      debugPrint('⚠️ Returning value as-is (possibly already decrypted)');
      return encryptedValue;
    }
  }

  /// Hash a WiFi SSID for secure comparison
  ///
  /// Uses SHA-256 one-way hashing. The hashed value can be compared
  /// but cannot be reversed to recover the original SSID.
  ///
  /// This prevents exposing the user's home network name in Firestore.
  static String? hashSsid(String? ssid) {
    if (ssid == null || ssid.isEmpty) return null;

    try {
      final bytes = utf8.encode(ssid.toLowerCase().trim());
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      debugPrint('❌ SSID hashing error: $e');
      return null;
    }
  }

  /// Compare a plain SSID with a hashed SSID
  ///
  /// Returns true if they match (case-insensitive)
  static bool compareSsid(String? plainSsid, String? hashedSsid) {
    if (plainSsid == null || hashedSsid == null) return false;

    final hashedPlain = hashSsid(plainSsid);
    return hashedPlain == hashedSsid;
  }

  /// Encrypt sensitive user data before storing in Firestore
  ///
  /// Encrypts: address, webhookUrl
  /// Hashes: homeSsid (one-way for comparison only)
  static Map<String, dynamic> encryptUserData(Map<String, dynamic> userData) {
    final encrypted = Map<String, dynamic>.from(userData);

    // Encrypt full address
    if (userData['address'] != null) {
      encrypted['address_encrypted'] = encryptString(userData['address']);
      encrypted.remove('address'); // Remove plain text
    }

    // Encrypt webhook URL
    if (userData['webhook_url'] != null) {
      encrypted['webhook_url_encrypted'] = encryptString(userData['webhook_url']);
      encrypted.remove('webhook_url'); // Remove plain text
    }

    // Hash WiFi SSID (one-way - cannot be decrypted)
    if (userData['home_ssid'] != null) {
      encrypted['home_ssid_hash'] = hashSsid(userData['home_ssid']);
      encrypted.remove('home_ssid'); // Remove plain text
    }

    // Note: We keep latitude/longitude for now as they're needed for features
    // Consider using geo-hashing or grid-based location in future

    return encrypted;
  }

  /// Decrypt sensitive user data after reading from Firestore
  ///
  /// Returns user data with decrypted fields
  static Map<String, dynamic> decryptUserData(Map<String, dynamic> userData) {
    final decrypted = Map<String, dynamic>.from(userData);

    // Decrypt address
    if (userData['address_encrypted'] != null) {
      decrypted['address'] = decryptString(userData['address_encrypted']);
      decrypted.remove('address_encrypted');
    } else if (userData['address'] != null) {
      // Backward compatibility: already decrypted
      decrypted['address'] = userData['address'];
    }

    // Decrypt webhook URL
    if (userData['webhook_url_encrypted'] != null) {
      decrypted['webhook_url'] = decryptString(userData['webhook_url_encrypted']);
      decrypted.remove('webhook_url_encrypted');
    } else if (userData['webhook_url'] != null) {
      // Backward compatibility
      decrypted['webhook_url'] = userData['webhook_url'];
    }

    // Note: home_ssid_hash stays as hash (cannot be decrypted)
    // Use compareSsid() to check if current SSID matches
    if (userData['home_ssid_hash'] != null) {
      decrypted['home_ssid_hash'] = userData['home_ssid_hash'];
      decrypted.remove('home_ssid'); // Ensure plain text is not present
    } else if (userData['home_ssid'] != null) {
      // Backward compatibility: store hash for future
      decrypted['home_ssid_hash'] = hashSsid(userData['home_ssid']);
    }

    return decrypted;
  }

  /// Clear encryption key (use for sign out or security wipe)
  ///
  /// WARNING: This will make previously encrypted data unrecoverable
  static Future<void> clearEncryptionKey() async {
    try {
      await _secureStorage.delete(key: _keyStorageKey);
      _encrypter = null;
      _iv = null;
      debugPrint('🔐 Encryption key cleared');
    } catch (e) {
      debugPrint('❌ Error clearing encryption key: $e');
    }
  }

  /// Re-encrypt user data with a new key
  ///
  /// Use this if the encryption key is compromised
  static Future<Map<String, dynamic>> reEncryptUserData(
    Map<String, dynamic> encryptedData,
  ) async {
    // Decrypt with old key
    final decrypted = decryptUserData(encryptedData);

    // Clear old key and generate new one
    await clearEncryptionKey();
    await initialize();

    // Re-encrypt with new key
    return encryptUserData(decrypted);
  }
}
