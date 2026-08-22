import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'protocol.dart';

class CompanionClient {
  CompanionClient({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  final Map<String, Completer<dynamic>> _pending =
      <String, Completer<dynamic>>{};
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  String? _deviceToken;

  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get isConnected => _channel != null;

  Future<String> connect({
    required List<String> endpoints,
    required String certificateFingerprint,
    String? deviceToken,
  }) async {
    await disconnect();
    Object? latestError;
    for (final endpoint in endpoints.toSet()) {
      try {
        await _connectEndpoint(
          endpoint,
          normalizeFingerprint(certificateFingerprint),
          deviceToken,
        );
        return endpoint;
      } on Object catch (error) {
        latestError = error;
        await disconnect();
      }
    }
    throw LocusProtocolException(
      'offline',
      latestError?.toString() ?? 'The paired Mac could not be reached.',
      retryable: true,
    );
  }

  Future<void> _connectEndpoint(
    String endpoint,
    String expectedFingerprint,
    String? deviceToken,
  ) async {
    final client = HttpClient();
    var pinnedCertificateSeen = false;
    client.badCertificateCallback = (certificate, host, port) {
      pinnedCertificateSeen = certificateMatchesPin(
        certificate.der,
        expectedFingerprint,
      );
      return pinnedCertificateSeen;
    };
    final channel = IOWebSocketChannel.connect(
      Uri.parse(endpoint),
      customClient: client,
      pingInterval: const Duration(seconds: 20),
      connectTimeout: const Duration(seconds: 5),
    );
    await channel.ready.timeout(const Duration(seconds: 6));
    if (!pinnedCertificateSeen) {
      await channel.sink.close();
      throw const LocusProtocolException(
        'certificate_mismatch',
        'The Mac certificate does not match the pairing code.',
      );
    }
    _channel = channel;
    _deviceToken = deviceToken;
    _subscription = channel.stream.listen(
      _receive,
      onError: _closed,
      onDone: () => _closed(
        const LocusProtocolException(
          'offline',
          'The Mac connection closed.',
          retryable: true,
        ),
      ),
      cancelOnError: true,
    );
  }

  Future<MacCredentials> pair({
    required PairingPayload payload,
    required String deviceName,
    required String platform,
  }) async {
    final connectedEndpoint = await connect(
      endpoints: payload.endpoints,
      certificateFingerprint: payload.certificateFingerprint,
    );
    final result = await request(
      'pair.exchange',
      payload: <String, dynamic>{
        'nonce': payload.nonce,
        'device_name': deviceName,
        'platform': platform,
      },
      authenticated: false,
    ) as Map<String, dynamic>;
    final token = result['device_token'] as String? ?? '';
    final deviceId = result['device_id'] as String? ?? '';
    if (token.isEmpty || deviceId.isEmpty) {
      throw const LocusProtocolException(
        'pairing_failed',
        'The Mac returned an incomplete pairing response.',
      );
    }
    _deviceToken = token;
    return MacCredentials(
      serviceId: payload.serviceId,
      deviceId: deviceId,
      deviceToken: token,
      certificateFingerprint: payload.certificateFingerprint,
      endpoints: <String>{
        connectedEndpoint,
        ...payload.endpoints,
      }.toList(growable: false),
    );
  }

  Future<dynamic> request(
    String method, {
    Map<String, dynamic> payload = const <String, dynamic>{},
    bool authenticated = true,
  }) async {
    final channel = _channel;
    if (channel == null) {
      throw const LocusProtocolException(
        'offline',
        'The Mac is offline. Commands are not queued.',
        retryable: true,
      );
    }
    final id = _uuid.v4();
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    channel.sink.add(
      jsonEncode(<String, dynamic>{
        'v': locusProtocolVersion,
        'id': id,
        'method': method,
        if (authenticated) 'token': _deviceToken,
        'payload': payload,
      }),
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      _pending.remove(id);
      throw const LocusProtocolException(
        'timeout',
        'The Mac did not answer in time. Check its connection before retrying.',
        retryable: true,
      );
    }
  }

  void _receive(dynamic message) {
    final decoded = jsonDecode(message as String);
    if (decoded is! Map<String, dynamic>) return;
    final event = decoded['event'];
    if (event is String) {
      _events.add(decoded);
      return;
    }
    final id = decoded['id'];
    if (id is! String) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (decoded['ok'] == true) {
      completer.complete(decoded['data']);
      return;
    }
    final error =
        decoded['error'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    completer.completeError(
      LocusProtocolException(
        error['code'] as String? ?? 'command_failed',
        error['message'] as String? ?? 'The command failed.',
        retryable: error['retryable'] == true,
      ),
    );
  }

  void _closed(Object error) {
    _channel = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
    _events.add(<String, dynamic>{
      'event': 'connection.status',
      'data': <String, dynamic>{'state': 'offline'},
    });
  }

  Future<void> disconnect() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const LocusProtocolException(
            'offline',
            'The Mac connection closed.',
            retryable: true,
          ),
        );
      }
    }
    _pending.clear();
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}
