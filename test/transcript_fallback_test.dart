import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_mobile/src/app_state.dart';
import 'package:locus_mobile/src/companion_client.dart';
import 'package:locus_mobile/src/protocol.dart';
import 'package:locus_mobile/src/storage.dart';

class TranscriptClient extends CompanionClient {
  final updates = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  Map<String, dynamic> snapshot = <String, dynamic>{};
  final pending = <String, Completer<dynamic>>{};
  bool missingChat = false;
  Object? chatError;

  @override
  Stream<Map<String, dynamic>> get events => updates.stream;

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic> payload = const <String, dynamic>{},
    bool authenticated = true,
  }) async {
    if (method == 'chat.get') {
      if (chatError != null) throw chatError!;
      if (missingChat) {
        throw const LocusProtocolException('chat_not_found', 'Deleted task');
      }
      final id = payload['chat_id'] as String;
      return pending[id]?.future ?? snapshot;
    }
    if (method == 'chats.list') {
      return <dynamic>[
        <String, dynamic>{'id': 'a', 'state': 'completed', 'updated_at': 2},
      ];
    }
    return method == 'status.get' ? <String, dynamic>{} : <dynamic>[];
  }

  @override
  Future<void> dispose() => updates.close();
}

class MemoryOnlyStorage extends CompanionStorage {
  @override
  Future<MacCredentials?> loadCredentials() async => null;

  @override
  Future<Map<String, dynamic>> loadReadOnlyCache() async => <String, dynamic>{};

  @override
  Future<void> saveReadOnlyCache(Map<String, dynamic> cache) async {}
}

void main() {
  test(
    'reconnect refresh replaces tokens with full completed fallback',
    () async {
      final client = TranscriptClient();
      final state = LocusAppState(client: client, storage: MemoryOnlyStorage());
      await state.initialize();
      state.online = true;
      client.snapshot = <String, dynamic>{'id': 'a', 'messages': <dynamic>[]};
      await state.openChat('a');
      state.streamingText['a'] = 'A partial streamed introduction';
      final complete = List.filled(15000, 'Complete writing body.').join('\n');
      client.snapshot = <String, dynamic>{
        'id': 'a',
        'messages': <dynamic>[
          <String, dynamic>{
            'role': 'assistant',
            'item_id': 'answer-a',
            'content': complete,
          },
        ],
      };
      await state.refreshAll();
      final messages = state.selectedChat!['messages'] as List<dynamic>;
      expect(messages, hasLength(1));
      expect((messages.single as Map<String, dynamic>)['content'], complete);
      expect(state.streamingText.containsKey('a'), isFalse);
      state.dispose();
    },
  );

  test('deleted selected chat does not break reconnect refresh', () async {
    final client = TranscriptClient();
    final state = LocusAppState(client: client, storage: MemoryOnlyStorage())
      ..online = true;
    client.snapshot = <String, dynamic>{'id': 'a', 'messages': <dynamic>[]};
    await state.openChat('a');
    state.streamingText['a'] = 'Old partial';
    client.missingChat = true;
    await state.refreshAll();
    expect(state.online, isTrue);
    expect(state.selectedChat, isNull);
    expect(state.streamingText.containsKey('a'), isFalse);
    state.dispose();
  });

  test(
    'late chat response cannot replace the newly selected transcript',
    () async {
      final client = TranscriptClient();
      final state = LocusAppState(client: client, storage: MemoryOnlyStorage())
        ..online = true;
      client.pending['a'] = Completer<dynamic>();
      final earlier = state.openChat('a');
      client.snapshot = <String, dynamic>{'id': 'b', 'messages': <dynamic>[]};
      await state.openChat('b');
      client.pending['a']!.complete(<String, dynamic>{
        'id': 'a',
        'messages': <dynamic>[],
      });
      await earlier;
      expect(state.selectedChat!['id'], 'b');
      state.dispose();
    },
  );

  test(
    'a failed transcript refresh keeps the partial response available',
    () async {
      final client = TranscriptClient();
      final state = LocusAppState(client: client, storage: MemoryOnlyStorage())
        ..online = true;
      client.snapshot = <String, dynamic>{'id': 'a', 'messages': <dynamic>[]};
      await state.openChat('a');
      state.streamingText['a'] = 'Last available partial response';
      client.chatError = const LocusProtocolException(
        'offline',
        'Connection lost',
      );
      await expectLater(
        state.refreshAll(),
        throwsA(isA<LocusProtocolException>()),
      );
      expect(state.streamingText['a'], 'Last available partial response');
      expect(state.selectedChat!['id'], 'a');
      state.dispose();
    },
  );

  test(
    'an older refresh of the same chat cannot replace its newer snapshot',
    () async {
      final client = TranscriptClient();
      final state = LocusAppState(client: client, storage: MemoryOnlyStorage())
        ..online = true;
      final slowResponse = Completer<dynamic>();
      client.pending['a'] = slowResponse;
      final earlier = state.openChat('a');
      client.pending.remove('a');
      client.snapshot = <String, dynamic>{'id': 'a', 'version': 'new'};
      await state.openChat('a');
      slowResponse.complete(<String, dynamic>{'id': 'a', 'version': 'old'});
      await earlier;
      expect(state.selectedChat!['version'], 'new');
      state.dispose();
    },
  );

  test(
    'closing a chat while loading does not reopen it on completion',
    () async {
      final client = TranscriptClient();
      final state = LocusAppState(client: client, storage: MemoryOnlyStorage())
        ..online = true;
      final slowResponse = Completer<dynamic>();
      client.pending['a'] = slowResponse;
      final loading = state.openChat('a');
      state.closeChat();
      slowResponse.complete(<String, dynamic>{
        'id': 'a',
        'messages': <dynamic>[],
      });
      await loading;
      expect(state.selectedChat, isNull);
      state.dispose();
    },
  );
}
