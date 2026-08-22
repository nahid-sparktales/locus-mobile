import 'dart:convert';

import 'package:crypto/crypto.dart';

const int locusProtocolVersion = 1;
const String locusServiceType = '_locus-remote._tcp';

class PairingPayload {
  const PairingPayload({
    required this.version,
    required this.serviceId,
    required this.endpoints,
    required this.certificateFingerprint,
    required this.nonce,
    required this.expiresAt,
  });

  final int version;
  final String serviceId;
  final List<String> endpoints;
  final String certificateFingerprint;
  final String nonce;
  final DateTime expiresAt;

  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  factory PairingPayload.parse(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('The pairing code is not a JSON object.');
    }
    final endpoints =
        (value['endpoints'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .where((endpoint) => Uri.tryParse(endpoint)?.scheme == 'wss')
            .toList(growable: false);
    final payload = PairingPayload(
      version: value['v'] as int? ?? 0,
      serviceId: value['service_id'] as String? ?? '',
      endpoints: endpoints,
      certificateFingerprint: normalizeFingerprint(
        value['certificate_fingerprint'] as String? ?? '',
      ),
      nonce: value['nonce'] as String? ?? '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (((value['expires_at'] as num?) ?? 0) * 1000).round(),
      ),
    );
    if (payload.version != locusProtocolVersion ||
        payload.serviceId.isEmpty ||
        payload.endpoints.isEmpty ||
        payload.certificateFingerprint.length != 64 ||
        payload.nonce.isEmpty) {
      throw const FormatException(
        'This pairing code is incomplete or unsupported.',
      );
    }
    if (payload.isExpired) {
      throw const FormatException(
        'This pairing code has expired. Create a new one on the Mac.',
      );
    }
    return payload;
  }

  static PairingPayload manual({
    required String endpoint,
    required String fingerprint,
    required String nonce,
    required String serviceId,
  }) {
    final normalizedEndpoint = endpoint.contains('://')
        ? endpoint
        : 'wss://$endpoint';
    return PairingPayload(
      version: locusProtocolVersion,
      serviceId: serviceId.trim(),
      endpoints: <String>[normalizedEndpoint],
      certificateFingerprint: normalizeFingerprint(fingerprint),
      nonce: nonce.trim(),
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }
}

class MacCredentials {
  const MacCredentials({
    required this.serviceId,
    required this.deviceId,
    required this.deviceToken,
    required this.certificateFingerprint,
    required this.endpoints,
  });

  final String serviceId;
  final String deviceId;
  final String deviceToken;
  final String certificateFingerprint;
  final List<String> endpoints;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'service_id': serviceId,
    'device_id': deviceId,
    'certificate_fingerprint': certificateFingerprint,
    'endpoints': endpoints,
  };

  factory MacCredentials.fromJson(Map<String, dynamic> json, String token) {
    return MacCredentials(
      serviceId: json['service_id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      deviceToken: token,
      certificateFingerprint: normalizeFingerprint(
        json['certificate_fingerprint'] as String? ?? '',
      ),
      endpoints: (json['endpoints'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

class LocusProtocolException implements Exception {
  const LocusProtocolException(
    this.code,
    this.message, {
    this.retryable = false,
  });

  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

String normalizeFingerprint(String value) {
  return value.replaceAll(RegExp('[^a-fA-F0-9]'), '').toLowerCase();
}

bool certificateMatchesPin(
  List<int> certificateDer,
  String expectedFingerprint,
) {
  final actual = sha256.convert(certificateDer).toString();
  return actual == normalizeFingerprint(expectedFingerprint);
}
