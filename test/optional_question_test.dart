import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_mobile/src/app_state.dart';
import 'package:locus_mobile/src/optional_question_card.dart';

Map<String, dynamic> request({String status = 'pending'}) => {
  'kind': 'optional_question',
  'chat_id': 'chat-a',
  'request_id': 'request-a',
  'status': status,
  'remaining_ms': 60000,
  'paused': false,
  'questions': [
    {
      'id': 'q1',
      'question': 'Where should the cache live?',
      'header': 'Storage',
      'multi_select': false,
      'options': [
        {'id': 'sqlite', 'label': 'SQLite', 'description': 'Durable storage'},
      ],
      'recommended_option_ids': ['sqlite'],
      'recommended_text': '',
    },
  ],
};

void main() {
  testWidgets(
    'editing leases renew and release without blocking the composer',
    (tester) async {
      final state = RecordingQuestionState()..online = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  OptionalQuestionCard(state: state, request: request()),
                  const TextField(key: ValueKey('normal-composer')),
                ],
              ),
            ),
          ),
        ),
      );
      final answer = find.byKey(const ValueKey('optionalQuestion.entry.q1'));
      await tester.tap(answer);
      await tester.pump();
      expect(state.messages, isEmpty, reason: 'Focus alone is not an edit');
      await tester.enterText(answer, 'Keep the cache encrypted');
      await tester.pump();
      expect(state.messages.single['active'], isTrue);
      await tester.pump(const Duration(seconds: 5));
      expect(
        state.messages.where((message) => message['active'] == true),
        hasLength(2),
      );
      await tester.tap(find.byKey(const ValueKey('normal-composer')));
      await tester.pump();
      expect(state.messages.last['active'], isFalse);
      await tester.tap(find.text('Skip'));
      await tester.pump();
      final skip = state.messages.singleWhere(
        (message) => message['decision'] == 'skip',
      );
      expect(
        skip['answers'],
        isEmpty,
        reason: 'Skip must not submit an unsent draft',
      );
      expect(
        state.questionDrafts.values.single['text'],
        'Keep the cache encrypted',
      );
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'optional question shows recommendations and preserves draft after timeout',
    (tester) async {
      final state = LocusAppState();
      Widget view(Map<String, dynamic> data) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OptionalQuestionCard(state: state, request: data),
          ),
        ),
      );
      await tester.pumpWidget(view(request()));
      expect(find.text('Optional question'), findsOneWidget);
      expect(find.text('Recommendation: SQLite'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      await tester.enterText(
        find.byType(TextField),
        'Keep the cache encrypted',
      );
      expect(
        state.questionDrafts.values.single['text'],
        'Keep the cache encrypted',
      );
      await tester.pumpWidget(view(request(status: 'defaulted')));
      expect(find.text('Send draft as follow-up'), findsOneWidget);
      expect(
        state.questionDrafts.values.single['text'],
        'Keep the cache encrypted',
      );
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  test('snapshot replacement keeps expired draft in its owning chat', () {
    final state = LocusAppState();
    final value = request();
    state.applyApprovals([value]);
    state.questionDrafts[LocusAppState.questionKey(value, 'q1')] = {
      'selected': <String>[],
      'text': 'Draft',
    };
    state.applyApprovals([]);
    expect(state.approvals.single['chat_id'], 'chat-a');
    expect(state.approvals.single['status'], 'finished');
    expect(state.questionDrafts.keys.single, 'chat-a/request-a/q1');
    state.dispose();
  });
}

class RecordingQuestionState extends LocusAppState {
  final messages = <Map<String, dynamic>>[];

  @override
  Future<void> respondToApproval(
    Map<String, dynamic> approval,
    String decision, {
    Map<String, dynamic> fields = const {},
  }) async {
    messages.add({...fields, 'decision': decision});
  }
}
