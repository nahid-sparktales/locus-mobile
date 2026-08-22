import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'protocol.dart';

class CompanionStorage {
  CompanionStorage({FlutterSecureStorage? secureStorage})
    : _secure = secureStorage ?? const FlutterSecureStorage();

  static const _tokenKey = 'locus.mac.deviceToken';
  static const _credentialsKey = 'locus.mac.credentials';
  static const _cacheKey = 'locus.readOnlyCache';

  final FlutterSecureStorage _secure;

  Future<MacCredentials?> loadCredentials() async {
    final token = await _secure.read(key: _tokenKey);
    final encoded = await _secure.read(key: _credentialsKey);
    if (token == null || encoded == null) return null;
    try {
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      final credentials = MacCredentials.fromJson(value, token);
      if (credentials.serviceId.isEmpty ||
          credentials.deviceId.isEmpty ||
          credentials.certificateFingerprint.length != 64 ||
          credentials.endpoints.isEmpty) {
        return null;
      }
      return credentials;
    } on Object {
      return null;
    }
  }

  Future<void> saveCredentials(MacCredentials credentials) async {
    await _secure.write(key: _tokenKey, value: credentials.deviceToken);
    await _secure.write(
      key: _credentialsKey,
      value: jsonEncode(credentials.toJson()),
    );
  }

  Future<Map<String, dynamic>> loadReadOnlyCache() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_cacheKey);
    if (encoded == null) return <String, dynamic>{};
    try {
      return jsonDecode(encoded) as Map<String, dynamic>;
    } on Object {
      return <String, dynamic>{};
    }
  }

  Future<void> saveReadOnlyCache(Map<String, dynamic> cache) async {
    final preferences = await SharedPreferences.getInstance();
    // Full transcripts are deliberately excluded. This cache only keeps list
    // and status snapshots so offline screens remain useful without leaving a
    // second copy of conversation contents in preferences.
    await preferences.setString(_cacheKey, jsonEncode(cache));
  }

  Future<void> clear() async {
    await _secure.delete(key: _tokenKey);
    await _secure.delete(key: _credentialsKey);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_cacheKey);
  }
}
