import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'app_state.dart';

class OptionalQuestionCard extends StatefulWidget {
  const OptionalQuestionCard({
    required this.state,
    required this.request,
    super.key,
  });
  final LocusAppState state;
  final Map<String, dynamic> request;

  @override
  State<OptionalQuestionCard> createState() => _OptionalQuestionCardState();
}

class _OptionalQuestionCardState extends State<OptionalQuestionCard>
    with WidgetsBindingObserver {
  final _editorId = const Uuid().v4();
  Timer? _timer;
  bool _editing = false;
  bool _sending = false;
  String? _error;
  final _controllers = <String, TextEditingController>{};
  final _cardFocus = FocusNode();
  Map<String, dynamic> get request => widget.request;
  bool get pending => request['status'] == 'pending';
  List<Map> get questions =>
      (request['questions'] as List? ?? []).whereType<Map>().toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!widget.state.online) _editing = false;
      if (_editing && timer.tick % 5 == 0) unawaited(_lease(true));
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _release();
  }

  @override
  void dispose() {
    _release();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _cardFocus.dispose();
    super.dispose();
  }

  Future<void> _lease(bool active) async {
    if (!widget.state.online || !pending) return;
    try {
      await widget.state.respondToApproval(
        request,
        'editing',
        fields: {'active': active, 'editor_id': _editorId},
      );
    } on Object {
      /* A lost connection naturally expires the server lease. */
    }
  }

  void _release() {
    if (_editing) unawaited(_lease(false));
    _editing = false;
  }

  Map<String, dynamic> _draft(String id) =>
      widget.state.questionDrafts[LocusAppState.questionKey(request, id)] ??
      <String, dynamic>{'selected': <String>[], 'text': ''};

  void _edit(String id, Map<String, dynamic> value) {
    final key = LocusAppState.questionKey(request, id);
    if (_hasContent(value)) {
      widget.state.questionDrafts[key] = value;
    } else {
      widget.state.questionDrafts.remove(key);
    }
    if (!_editing && pending) {
      _editing = true;
      unawaited(_lease(true));
    }
    setState(() {});
  }

  Future<void> _respond(String action, {String? questionId}) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final answers = action == 'skip'
          ? <Map<String, dynamic>>[]
          : questions
                .where(
                  (q) =>
                      q['answer'] == null &&
                      (questionId == null || q['id'] == questionId),
                )
                .map(
                  (q) => <String, dynamic>{
                    'id': q['id'],
                    ..._draft(q['id'] as String),
                  },
                )
                .toList();
      await widget.state.respondToApproval(
        request,
        action,
        fields: {'answers': answers},
      );
      _release();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _followup() async {
    final text = questions
        .map((q) {
          final draft = _draft(q['id'] as String);
          final selected = draft['selected'] as List? ?? [];
          final labels = (q['options'] as List? ?? [])
              .whereType<Map>()
              .where((option) => selected.contains(option['id']))
              .map((option) => option['label'].toString());
          final parts = [
            ...labels,
            draft['text'] as String? ?? '',
          ].where((text) => text.trim().isNotEmpty).toList();
          return parts.isEmpty
              ? ''
              : '${q['header'] ?? q['question']}: ${parts.join('; ')}';
        })
        .where((text) => text.isNotEmpty)
        .join('\n');
    if (text.isEmpty) return;
    try {
      await widget.state.sendToChat(request['chat_id'] as String, text, 'work');
      for (final q in questions) {
        widget.state.questionDrafts.remove(
          LocusAppState.questionKey(request, q['id'] as String),
        );
      }
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    }
  }

  String get _status {
    if (!widget.state.online) return 'Offline. Your draft is kept.';
    if (request['delivery_status'] == 'applied') {
      return 'Answer applied to the agent’s work.';
    }
    if (request['delivery_status'] == 'accepted') {
      return 'Answer accepted; waiting for the agent to apply it.';
    }
    if (!pending) {
      return 'This question is paused or finished. Your draft is still available.';
    }
    if (request['paused'] == true) return 'Timer paused while editing';
    final deadline = request['deadline_at'] as num?;
    final seconds = deadline == null
        ? ((request['remaining_ms'] as num? ?? 0) / 1000).ceil()
        : (deadline - DateTime.now().millisecondsSinceEpoch / 1000).ceil();
    return seconds > 0
        ? 'Recommendations in ${seconds}s'
        : 'Waiting for saved recommendations…';
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _cardFocus,
      onFocusChange: (focused) {
        if (!focused) _release();
      },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Optional question',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Work continues while you answer. Skip uses recommendations for unanswered questions.',
              ),
              Text(_status),
              for (final question in questions) ...[
                const SizedBox(height: 12),
                Text(
                  question['question'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (question['answer'] is Map)
                  const Text('Answer accepted')
                else ...[
                  for (final option
                      in (question['options'] as List? ?? []).whereType<Map>())
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(option['label'] as String? ?? ''),
                      subtitle: Text(option['description'] as String? ?? ''),
                      value:
                          (_draft(question['id'] as String)['selected'] as List)
                              .contains(option['id']),
                      onChanged: (value) {
                        _cardFocus.requestFocus();
                        final id = question['id'] as String;
                        final selected = List<String>.from(
                          _draft(id)['selected'] as List,
                        );
                        if (question['multi_select'] != true) selected.clear();
                        if (value == true) {
                          selected.add(option['id'] as String);
                        } else {
                          selected.remove(option['id']);
                        }
                        _edit(id, {..._draft(id), 'selected': selected});
                      },
                    ),
                  TextField(
                    key: ValueKey('optionalQuestion.entry.${question['id']}'),
                    controller: _controllers.putIfAbsent(
                      question['id'] as String,
                      () => TextEditingController(
                        text:
                            _draft(question['id'] as String)['text']
                                as String? ??
                            '',
                      ),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Your answer or extra detail',
                    ),
                    maxLines: 3,
                    minLines: 1,
                    onChanged: (text) => _edit(question['id'] as String, {
                      ..._draft(question['id'] as String),
                      'text': text,
                    }),
                  ),
                  Text('Recommendation: ${_recommendation(question)}'),
                  if (pending)
                    FilledButton(
                      onPressed:
                          !widget.state.online ||
                              _sending ||
                              !_hasContent(_draft(question['id'] as String))
                          ? null
                          : () => _respond(
                              'answer',
                              questionId: question['id'] as String,
                            ),
                      child: const Text('Submit answer'),
                    ),
                ],
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (request['response_error'] is String)
                Text(
                  request['response_error'] as String,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (pending)
                OutlinedButton(
                  onPressed: widget.state.online && !_sending
                      ? () => _respond('skip')
                      : null,
                  child: const Text('Skip'),
                ),
              if (request['status'] == 'suspended' ||
                  request['delivery_status'] == 'accepted')
                OutlinedButton(
                  onPressed:
                      widget.state.online && request['can_resume'] == true
                      ? () async {
                          try {
                            await widget.state.respondToApproval(
                              request,
                              'resume',
                            );
                          } on Object catch (error) {
                            if (mounted) {
                              setState(() {
                                _error = error.toString();
                              });
                            }
                          }
                        }
                      : null,
                  child: Text(
                    request['status'] == 'suspended'
                        ? 'Resume question'
                        : 'Resume delivery',
                  ),
                ),
              if (!pending &&
                  questions.any((q) => _hasContent(_draft(q['id'] as String))))
                OutlinedButton(
                  onPressed: widget.state.online ? _followup : null,
                  child: const Text('Send draft as follow-up'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasContent(Map<String, dynamic> draft) =>
      (draft['selected'] as List? ?? []).isNotEmpty ||
      (draft['text'] as String? ?? '').trim().isNotEmpty;
  String _recommendation(Map question) {
    final recommended = question['recommended_option_ids'] as List? ?? [];
    return [
      ...(question['options'] as List? ?? [])
          .whereType<Map>()
          .where((o) => recommended.contains(o['id']))
          .map((o) => o['label'].toString()),
      question['recommended_text'] as String? ?? '',
    ].where((value) => value.isNotEmpty).join('; ');
  }
}
