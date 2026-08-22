import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'companion_client.dart';
import 'discovery.dart';
import 'protocol.dart';
import 'storage.dart';

class LocusAppState extends ChangeNotifier {
  LocusAppState({
    CompanionClient? client,
    CompanionStorage? storage,
    BonjourDiscovery? discovery,
  }) : _client = client ?? CompanionClient(),
       _storage = storage ?? CompanionStorage(),
       _discovery = discovery ?? const BonjourDiscovery();

  final CompanionClient _client;
  final CompanionStorage _storage;
  final BonjourDiscovery _discovery;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  MacCredentials? _credentials;
  String? _selectedChatId;

  bool initialized = false;
  bool connecting = false;
  bool online = false;
  String? errorMessage;
  Map<String, dynamic> status = <String, dynamic>{};
  List<Map<String, dynamic>> chats = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> activity = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> schedules = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> approvals = <Map<String, dynamic>>[];
  Map<String, dynamic>? selectedChat;
  Map<String, String> streamingText = <String, String>{};

  bool get isPaired => _credentials != null;
  MacCredentials? get credentials => _credentials;

  Future<void> initialize() async {
    _eventSubscription = _client.events.listen(_handleEvent);
    try {
      _credentials = await _storage.loadCredentials();
      final cache = await _storage.loadReadOnlyCache();
      _applyCache(cache);
    } on Object catch (error) {
      errorMessage = 'Secure storage is unavailable: $error';
      _credentials = null;
    } finally {
      initialized = true;
      notifyListeners();
    }
    if (_credentials != null) unawaited(connect());
  }

  Future<void> pair(PairingPayload payload) async {
    connecting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final paired = await _client.pair(
        payload: payload,
        deviceName: Platform.localHostname,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      _credentials = paired;
      await _storage.saveCredentials(paired);
      online = true;
      _reconnectAttempt = 0;
      await refreshAll();
    } on Object catch (error) {
      errorMessage = error.toString();
      online = false;
      rethrow;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> connect() async {
    final credentials = _credentials;
    if (credentials == null || connecting || online) return;
    connecting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final discovered = await _discovery.discover();
      await _client.connect(
        endpoints: <String>[...discovered, ...credentials.endpoints],
        certificateFingerprint: credentials.certificateFingerprint,
        deviceToken: credentials.deviceToken,
      );
      online = true;
      _reconnectAttempt = 0;
      await refreshAll();
    } on Object catch (error) {
      online = false;
      errorMessage = error.toString();
      _scheduleReconnect();
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> refreshAll() async {
    if (!online) return;
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      _client.request('status.get'),
      _client.request('chats.list'),
      _client.request('activity.list'),
      _client.request('schedules.list'),
    ]);
    status = _map(results[0]);
    chats = _mapList(results[1]);
    activity = _mapList(results[2]);
    schedules = _mapList(results[3]);
    approvals = _mapList(status['approvals']);
    if (approvals.isEmpty) approvals = _deriveApprovals(activity);
    await _persistCache();
    notifyListeners();
  }

  Future<void> openChat(String chatId) async {
    _requireOnline();
    _selectedChatId = chatId;
    selectedChat = _map(
      await _client.request(
        'chat.get',
        payload: <String, dynamic>{'chat_id': chatId},
      ),
    );
    notifyListeners();
  }

  void closeChat() {
    _selectedChatId = null;
    selectedChat = null;
  }

  Future<void> sendToChat(String chatId, String prompt, String mode) async {
    _requireOnline();
    await _client.request(
      'chat.send',
      payload: <String, dynamic>{
        'chat_id': chatId,
        'prompt': prompt,
        'mode': mode,
      },
    );
    await openChat(chatId);
    await _refreshActivity();
  }

  Future<String> createChat(
    String workspaceId,
    String prompt,
    String mode,
  ) async {
    _requireOnline();
    final result = _map(
      await _client.request(
        'chat.create',
        payload: <String, dynamic>{
          'workspace_id': workspaceId,
          'prompt': prompt,
          'mode': mode,
        },
      ),
    );
    final chatId = result['chat_id'] as String? ?? '';
    if (chatId.isEmpty) {
      throw const LocusProtocolException(
        'chat_failed',
        'The Mac did not create a chat.',
      );
    }
    await refreshAll();
    return chatId;
  }

  Future<void> stopRun(String runId) async {
    _requireOnline();
    await _client.request(
      'run.stop',
      payload: <String, dynamic>{'run_id': runId},
    );
    await _refreshActivity();
  }

  Future<void> respondToApproval(
    Map<String, dynamic> approval,
    String decision,
  ) async {
    _requireOnline();
    await _client.request(
      'approval.respond',
      payload: <String, dynamic>{...approval, 'decision': decision},
    );
    approvals.removeWhere(
      (candidate) =>
          candidate['kind'] == approval['kind'] &&
          candidate['run_id'] == approval['run_id'] &&
          candidate['chat_id'] == approval['chat_id'],
    );
    notifyListeners();
  }

  Future<void> runScheduleNow(String scheduleId) async {
    _requireOnline();
    await _client.request(
      'schedule.runNow',
      payload: <String, dynamic>{'schedule_id': scheduleId},
    );
    await refreshAll();
  }

  Future<void> setScheduleEnabled(String scheduleId, bool enabled) async {
    _requireOnline();
    final updated = _map(
      await _client.request(
        'schedule.setEnabled',
        payload: <String, dynamic>{
          'schedule_id': scheduleId,
          'enabled': enabled,
        },
      ),
    );
    final index = schedules.indexWhere((item) => item['id'] == scheduleId);
    if (index >= 0) {
      schedules[index] = updated;
    }
    await _persistCache();
    notifyListeners();
  }

  Future<void> addManualEndpoint(String endpoint) async {
    final credentials = _credentials;
    if (credentials == null) return;
    final normalized = endpoint.contains('://') ? endpoint : 'wss://$endpoint';
    final updated = MacCredentials(
      serviceId: credentials.serviceId,
      deviceId: credentials.deviceId,
      deviceToken: credentials.deviceToken,
      certificateFingerprint: credentials.certificateFingerprint,
      endpoints: <String>{
        normalized,
        ...credentials.endpoints,
      }.toList(growable: false),
    );
    _credentials = updated;
    await _storage.saveCredentials(updated);
    online = false;
    await connect();
  }

  Future<void> unpair() async {
    _reconnectTimer?.cancel();
    await _client.disconnect();
    await _storage.clear();
    _credentials = null;
    online = false;
    status = <String, dynamic>{};
    chats = <Map<String, dynamic>>[];
    activity = <Map<String, dynamic>>[];
    schedules = <Map<String, dynamic>>[];
    approvals = <Map<String, dynamic>>[];
    selectedChat = null;
    streamingText = <String, String>{};
    notifyListeners();
  }

  void _handleEvent(Map<String, dynamic> envelope) {
    final event = envelope['event'] as String?;
    final data = envelope['data'];
    switch (event) {
      case 'connection.status':
        final connection = _map(data);
        online = connection['state'] != 'offline';
        if (!online) _scheduleReconnect();
      case 'chat.updated':
        final selectedBeforeUpdate = _selectedChatId;
        final selectedWasStreaming =
            selectedBeforeUpdate != null &&
            streamingText[selectedBeforeUpdate]?.isNotEmpty == true;
        final previousUpdatedAt = selectedBeforeUpdate == null
            ? null
            : chats
                  .where((chat) => chat['id'] == selectedBeforeUpdate)
                  .firstOrNull?['updated_at'];
        if (data is Map<String, dynamic>) {
          chats = _mapList(data['chats']);
          streamingText = <String, String>{
            for (final stream in _mapList(data['streams']))
              if (stream['chat_id'] is String && stream['text'] is String)
                stream['chat_id'] as String: stream['text'] as String,
          };
        } else {
          chats = _mapList(data);
        }
        final selected = _selectedChatId;
        final selectedIsStreaming =
            selected != null && streamingText[selected]?.isNotEmpty == true;
        final currentUpdatedAt = selected == null
            ? null
            : chats
                  .where((chat) => chat['id'] == selected)
                  .firstOrNull?['updated_at'];
        final selectedFinishedStreaming =
            selectedWasStreaming && !selectedIsStreaming;
        final selectedSummaryChanged =
            previousUpdatedAt != null &&
            currentUpdatedAt != null &&
            previousUpdatedAt != currentUpdatedAt;
        if (selected != null &&
            online &&
            !selectedIsStreaming &&
            (selectedFinishedStreaming || selectedSummaryChanged)) {
          unawaited(openChat(selected));
        }
      case 'activity.updated':
        activity = _mapList(data);
      case 'schedule.updated':
        schedules = _mapList(data);
      case 'approval.required':
        approvals = _mapList(data);
    }
    unawaited(_persistCache());
    notifyListeners();
  }

  Future<void> _refreshActivity() async {
    activity = _mapList(await _client.request('activity.list'));
    approvals = _deriveApprovals(activity);
    notifyListeners();
  }

  List<Map<String, dynamic>> _deriveApprovals(List<Map<String, dynamic>> runs) {
    return runs
        .where((run) {
          final state = run['state'];
          return state == 'waiting_permission' ||
              state == 'waiting_dispatch_approval';
        })
        .map((run) {
          final permission = run['state'] == 'waiting_permission';
          return <String, dynamic>{
            'kind': permission ? 'permission' : 'dispatch',
            'run_id': run['id'],
            'chat_id': run['chat_id'],
            'title': permission
                ? 'Action needs approval'
                : 'Team plan is ready',
            'decisions': permission
                ? <String>['allow_once', 'deny']
                : <String>['approve', 'cancel'],
          };
        })
        .toList(growable: false);
  }

  void _applyCache(Map<String, dynamic> cache) {
    status = _map(cache['status']);
    chats = _mapList(cache['chats']);
    activity = _mapList(cache['activity']);
    schedules = _mapList(cache['schedules']);
  }

  Future<void> _persistCache() {
    return _storage.saveReadOnlyCache(<String, dynamic>{
      'status': status,
      'chats': chats,
      'activity': activity,
      'schedules': schedules,
    });
  }

  void _scheduleReconnect() {
    if (_credentials == null || _reconnectTimer?.isActive == true) return;
    final seconds = <int>[1, 2, 5, 10, 20, 30][_reconnectAttempt.clamp(0, 5)];
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(
      Duration(seconds: seconds),
      () => unawaited(connect()),
    );
  }

  void _requireOnline() {
    if (!online) {
      throw const LocusProtocolException(
        'offline',
        'The Mac is offline. This command was not queued.',
        retryable: true,
      );
    }
  }

  static Map<String, dynamic> _map(dynamic value) {
    return value is Map<String, dynamic> ? value : <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    return value is List<dynamic>
        ? value.whereType<Map<String, dynamic>>().toList(growable: false)
        : <Map<String, dynamic>>[];
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    unawaited(_eventSubscription?.cancel());
    unawaited(_client.dispose());
    super.dispose();
  }
}
