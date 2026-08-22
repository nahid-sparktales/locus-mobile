import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_mobile/src/protocol.dart';

void main() {
  test('shared protocol fixtures use compatible versioned envelopes', () {
    final raw = File('fixtures/companion-v1.json').readAsStringSync();
    final fixture = jsonDecode(raw) as Map<String, dynamic>;
    final requests = fixture['requests'] as List<dynamic>;

    for (final request in requests.whereType<Map<String, dynamic>>()) {
      expect(request['v'], locusProtocolVersion);
      expect(request['id'], isNotEmpty);
      expect(request['method'], isNotEmpty);
      expect(request['payload'], isA<Map<String, dynamic>>());
    }
    expect((fixture['response'] as Map<String, dynamic>)['v'], 1);
    expect((fixture['event'] as Map<String, dynamic>)['v'], 1);
  });

  test('pairing payload rejects unsupported versions', () {
    final raw = jsonEncode(<String, dynamic>{
      'v': 2,
      'service_id': 'mac-1',
      'endpoints': <String>['wss://192.168.1.8:9410'],
      'certificate_fingerprint': List<String>.filled(64, 'a').join(),
      'nonce': 'nonce',
      'expires_at':
          DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch /
          1000,
    });

    expect(() => PairingPayload.parse(raw), throwsFormatException);
  });

  test('fingerprints are normalized before pinning', () {
    expect(normalizeFingerprint('AA:bb 01-ff'), 'aabb01ff');
  });

  test('certificate pinning compares the full SHA-256 DER fingerprint', () {
    const fingerprint =
        '03:90:58:C6:F2:C0:CB:49:2C:53:3B:0A:4D:14:EF:77:'
        'CC:0F:78:AB:CC:CE:D5:28:7D:84:A1:A2:01:1C:FB:81';
    expect(certificateMatchesPin(<int>[1, 2, 3], fingerprint), isTrue);
    expect(certificateMatchesPin(<int>[1, 2, 4], fingerprint), isFalse);
  });
}
