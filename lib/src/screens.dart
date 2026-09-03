import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'app_state.dart';
import 'protocol.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({required this.state, super.key});
  final LocusAppState state;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final scanner = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  final endpoint = TextEditingController();
  final fingerprint = TextEditingController();
  final nonce = TextEditingController();
  final serviceId = TextEditingController();
  bool manual = false;
  bool readingCode = false;

  @override
  void dispose() {
    unawaited(scanner.dispose());
    endpoint.dispose();
    fingerprint.dispose();
    nonce.dispose();
    serviceId.dispose();
    super.dispose();
  }

  Future<void> pairRaw(String raw) async {
    if (readingCode || widget.state.connecting) return;
    readingCode = true;
    try {
      await scanner.stop();
      await widget.state.pair(PairingPayload.parse(raw));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
      await scanner.start();
    } finally {
      readingCode = false;
    }
  }

  Future<void> pairManual() async {
    try {
      final payload = PairingPayload.manual(
        endpoint: endpoint.text,
        fingerprint: fingerprint.text,
        nonce: nonce.text,
        serviceId: serviceId.text,
      );
      if (payload.serviceId.isEmpty ||
          payload.nonce.isEmpty ||
          payload.certificateFingerprint.length != 64) {
        throw const FormatException(
          'Enter all details exactly as shown on the Mac.',
        );
      }
      await widget.state.pair(payload);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> pastePairingDetails() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = clipboard?.text?.trim() ?? '';
    if (raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('The clipboard is empty.')));
      return;
    }
    await pairRaw(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair Locus Mobile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const Icon(Icons.hub_outlined, size: 42),
            const SizedBox(height: 10),
            Text(
              'Connect directly to your Mac',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'In Locus on your Mac, open Settings → General → Mobile Access, then create a pairing code.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (!manual)
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 330,
                  child: MobileScanner(
                    controller: scanner,
                    onDetect: (capture) {
                      final value = capture.barcodes.firstOrNull?.rawValue;
                      if (value != null) unawaited(pairRaw(value));
                    },
                  ),
                ),
              )
            else ...<Widget>[
              OutlinedButton.icon(
                onPressed: widget.state.connecting ? null : pastePairingDetails,
                icon: const Icon(Icons.content_paste),
                label: const Text('Paste pairing details from Mac'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endpoint,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Mac endpoint',
                  hintText: 'wss://100.x.x.x:12345',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fingerprint,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Certificate fingerprint',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nonce,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'One-time nonce'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: serviceId,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Service ID'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.state.connecting ? null : pairManual,
                icon: const Icon(Icons.link),
                label: const Text('Pair securely'),
              ),
            ],
            if (widget.state.connecting) ...const <Widget>[
              SizedBox(height: 16),
              LinearProgressIndicator(),
            ],
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() => manual = !manual),
              child: Text(
                manual ? 'Scan QR code instead' : 'Enter endpoint manually',
              ),
            ),
            const SizedBox(height: 12),
            const _PrivacyNote(),
          ],
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.lock_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'No Locus account or cloud relay is used. The certificate is pinned to this Mac, and the device token is stored in Keychain or Keystore.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({required this.state, super.key});
  final LocusAppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final destinations = <Widget>[
      HomeScreen(state: widget.state),
      ChatsScreen(state: widget.state),
      ActivitySchedulesScreen(state: widget.state),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Locus'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(child: ConnectionPill(online: widget.state.online)),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'endpoint') {
                await _addEndpoint(context);
              } else if (value == 'unpair') {
                await _confirmUnpair(context);
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem(
                value: 'endpoint',
                child: Text('Add Tailscale endpoint'),
              ),
              PopupMenuItem(value: 'unpair', child: Text('Unpair this Mac')),
            ],
          ),
        ],
      ),
      body: destinations[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Activity',
          ),
        ],
      ),
    );
  }

  Future<void> _addEndpoint(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Tailscale endpoint'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'wss://100.x.x.x:12345'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.isNotEmpty) {
      await widget.state.addManualEndpoint(value);
    }
  }

  Future<void> _confirmUnpair(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unpair this Mac?'),
        content: const Text(
          'The device token and cached lists will be removed from this phone. Chats remain on the Mac.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.state.unpair();
  }
}

class ConnectionPill extends StatelessWidget {
  const ConnectionPill({required this.online, super.key});
  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = online
        ? const Color(0xFF2E7D58)
        : Theme.of(context).colorScheme.error;
    return Semantics(
      label: online ? 'Mac online' : 'Mac offline',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              online ? Icons.check_circle : Icons.cloud_off,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(
              online ? 'Online' : 'Offline',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.state, super.key});
  final LocusAppState state;

  @override
  Widget build(BuildContext context) {
    final running = state.status['running_count'] as num? ?? 0;
    final next = state.status['next_schedule'] as Map<String, dynamic>?;
    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (!state.online) _OfflineBanner(state: state),
          Text(
            'Your Mac',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _MetricGrid(
            items: <_Metric>[
              _Metric(
                Icons.memory,
                state.status['agent_online'] == true ? 'Ready' : 'Unavailable',
                'Agent',
              ),
              _Metric(
                Icons.play_circle_outline,
                '${running.toInt()}',
                'Running',
              ),
              _Metric(
                Icons.approval_outlined,
                '${state.approvals.length}',
                'Approvals',
              ),
              _Metric(
                Icons.schedule,
                next?['name'] as String? ?? 'None',
                'Next schedule',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Needs attention',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (state.approvals.isEmpty)
            const _EmptyCard(
              icon: Icons.check_circle_outline,
              text: 'Nothing needs your approval.',
            )
          else
            ...state.approvals.map(
              (approval) => _ApprovalCard(state: state, approval: approval),
            ),
          const SizedBox(height: 20),
          Text(
            'Running work',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...state.activity
              .where(
                (run) => <String>{
                  'queued',
                  'running',
                  'dispatching',
                  'reviewing',
                }.contains(run['state']),
              )
              .take(4)
              .map((run) => _RunCard(state: state, run: run)),
          if (!state.activity.any(
            (run) => <String>{
              'queued',
              'running',
              'dispatching',
              'reviewing',
            }.contains(run['state']),
          ))
            const _EmptyCard(
              icon: Icons.bedtime_outlined,
              text: 'No work is running.',
            ),
        ],
      ),
    );
  }
}

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({required this.state, super.key});
  final LocusAppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.online ? () => _newChat(context) : null,
        icon: const Icon(Icons.add),
        label: const Text('New chat'),
      ),
      body: RefreshIndicator(
        onRefresh: state.refreshAll,
        child: state.chats.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  const _EmptyCard(
                    icon: Icons.chat_bubble_outline,
                    text: 'No saved chats yet.',
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: state.chats.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final chat = state.chats[index];
                  return Card(
                    child: ListTile(
                      title: Text(
                        chat['title'] as String? ?? 'Saved chat',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        chat['preview'] as String? ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      leading: _StateIcon(
                        state: chat['state'] as String? ?? 'idle',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final id = chat['id'] as String?;
                        if (id == null) return;
                        await state.openChat(id);
                        if (!context.mounted) return;
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ChatDetailScreen(state: state, chatId: id),
                          ),
                        );
                        state.closeChat();
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _newChat(BuildContext context) async {
    final created = await showModalBottomSheet<_NewChatDraft>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _NewChatSheet(workspaces: state.status['workspaces']),
    );
    if (created == null) return;
    try {
      final chatId = await state.createChat(
        created.workspaceId,
        created.prompt,
        created.mode,
      );
      await state.openChat(chatId);
      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ChatDetailScreen(state: state, chatId: chatId),
        ),
      );
      state.closeChat();
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    required this.state,
    required this.chatId,
    super.key,
  });
  final LocusAppState state;
  final String chatId;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final composer = TextEditingController();
  String mode = 'work';
  bool sending = false;

  @override
  void dispose() {
    composer.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final prompt = composer.text.trim();
    if (prompt.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      composer.clear();
      await widget.state.sendToChat(widget.chatId, prompt, mode);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final detail = widget.state.selectedChat;
        final messages =
            (detail?['messages'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .toList(growable: false);
        final stream = widget.state.streamingText[widget.chatId];
        return Scaffold(
          appBar: AppBar(title: Text(detail?['title'] as String? ?? 'Chat')),
          body: Column(
            children: <Widget>[
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount:
                      messages.length + (stream?.isNotEmpty == true ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return _MessageBubble(
                        role: 'assistant',
                        content: stream!,
                        streaming: true,
                      );
                    }
                    final message = messages[index];
                    return _MessageBubble(
                      role: message['role'] as String? ?? 'assistant',
                      content: message['content'] as String? ?? '',
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          DropdownButton<String>(
                            value: mode,
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem(
                                value: 'ask',
                                child: Text('Ask'),
                              ),
                              DropdownMenuItem(
                                value: 'work',
                                child: Text('Work'),
                              ),
                              DropdownMenuItem(
                                value: 'plan',
                                child: Text('Plan'),
                              ),
                              DropdownMenuItem(
                                value: 'grill',
                                child: Text('Grill'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => mode = value ?? mode),
                          ),
                          const Spacer(),
                          if (!widget.state.online)
                            const Text('Offline · not queued'),
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: composer,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Message Locus…',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: widget.state.online && !sending
                                ? send
                                : null,
                            icon: sending
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_upward),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ActivitySchedulesScreen extends StatelessWidget {
  const ActivitySchedulesScreen({required this.state, super.key});
  final LocusAppState state;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          const TabBar(
            tabs: <Tab>[
              Tab(text: 'Activity'),
              Tab(text: 'Schedules'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                RefreshIndicator(
                  onRefresh: state.refreshAll,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      ...state.approvals.map(
                        (approval) =>
                            _ApprovalCard(state: state, approval: approval),
                      ),
                      ...state.activity.map(
                        (run) => _RunCard(state: state, run: run),
                      ),
                      if (state.activity.isEmpty)
                        const _EmptyCard(
                          icon: Icons.bolt_outlined,
                          text: 'No recent activity.',
                        ),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: state.refreshAll,
                  child: state.schedules.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          children: const <Widget>[
                            _EmptyCard(
                              icon: Icons.schedule_outlined,
                              text: 'No schedules are configured on this Mac.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: state.schedules.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) => _ScheduleCard(
                            state: state,
                            schedule: state.schedules[index],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.state});
  final LocusAppState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Your Mac is offline. Commands are disabled and will not be queued.',
              ),
            ),
            TextButton(
              onPressed: state.connecting ? null : state.connect,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});
  final List<_Metric> items;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.65,
      children: items
          .map(
            (item) => Card(
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(item.icon, size: 20),
                    const Spacer(),
                    Text(
                      item.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      item.label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.state, required this.approval});
  final LocusAppState state;
  final Map<String, dynamic> approval;

  @override
  Widget build(BuildContext context) {
    final permission = approval['kind'] == 'permission';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              approval['title'] as String? ?? 'Approval needed',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (approval['detail'] is String) ...<Widget>[
              const SizedBox(height: 4),
              Text(approval['detail'] as String),
            ],
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                FilledButton(
                  onPressed: state.online
                      ? () => state.respondToApproval(
                          approval,
                          permission ? 'allow_once' : 'approve',
                        )
                      : null,
                  child: Text(permission ? 'Allow once' : 'Approve'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: state.online
                      ? () => state.respondToApproval(
                          approval,
                          permission ? 'deny' : 'cancel',
                        )
                      : null,
                  child: Text(permission ? 'Deny' : 'Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.state, required this.run});
  final LocusAppState state;
  final Map<String, dynamic> run;

  @override
  Widget build(BuildContext context) {
    final canStop = run['can_stop'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: _StateIcon(state: run['state'] as String? ?? ''),
          title: Text(run['chat_title'] as String? ?? 'Saved chat'),
          subtitle: Text(
            '${run['state'] ?? 'unknown'} · ${run['kind'] ?? 'solo'}',
          ),
          trailing: canStop
              ? TextButton(
                  onPressed: state.online
                      ? () => state.stopRun(run['id'] as String)
                      : null,
                  child: const Text('Stop'),
                )
              : null,
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.state, required this.schedule});
  final LocusAppState state;
  final Map<String, dynamic> schedule;

  @override
  Widget build(BuildContext context) {
    final enabled = schedule['enabled'] == true;
    final next = schedule['next_run_at'] as num?;
    final id = schedule['id'] as String;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    schedule['name'] as String? ?? 'Schedule',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: state.online
                      ? (value) => state.setScheduleEnabled(id, value)
                      : null,
                ),
              ],
            ),
            Text(
              next == null
                  ? 'No next run'
                  : 'Next ${DateTime.fromMillisecondsSinceEpoch((next * 1000).round()).toLocal()}',
            ),
            if (schedule['last_error'] case final String error) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: state.online ? () => state.runScheduleNow(id) : null,
              child: const Text('Run now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final active = <String>{
      'queued',
      'running',
      'dispatching',
      'reviewing',
    }.contains(state);
    final attention = <String>{
      'waiting_permission',
      'waiting_dispatch_approval',
      'failed',
      'paused',
    }.contains(state);
    return Icon(
      active
          ? Icons.motion_photos_on
          : attention
          ? Icons.error_outline
          : Icons.check_circle_outline,
      color: active
          ? Theme.of(context).colorScheme.primary
          : attention
          ? Theme.of(context).colorScheme.error
          : const Color(0xFF2E7D58),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.role,
    required this.content,
    this.streaming = false,
  });
  final String role;
  final String content;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final user = role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: user
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (streaming) ...const <Widget>[
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
            ],
            Flexible(child: SelectableText(content)),
          ],
        ),
      ),
    );
  }
}

class _NewChatDraft {
  const _NewChatDraft(this.workspaceId, this.prompt, this.mode);
  final String workspaceId;
  final String prompt;
  final String mode;
}

class _NewChatSheet extends StatefulWidget {
  const _NewChatSheet({required this.workspaces});
  final dynamic workspaces;

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final prompt = TextEditingController();
  String? workspaceId;
  String mode = 'work';

  List<Map<String, dynamic>> get workspaces =>
      widget.workspaces is List<dynamic>
      ? (widget.workspaces as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList(growable: false)
      : <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    workspaceId = workspaces.firstOrNull?['id'] as String?;
  }

  @override
  void dispose() {
    prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'New chat on your Mac',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: workspaceId,
            decoration: const InputDecoration(labelText: 'Workspace'),
            items: workspaces
                .map(
                  (workspace) => DropdownMenuItem<String>(
                    value: workspace['id'] as String?,
                    child: Text(workspace['name'] as String? ?? 'Workspace'),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => workspaceId = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: mode,
            decoration: const InputDecoration(labelText: 'Mode'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'ask', child: Text('Ask')),
              DropdownMenuItem(value: 'work', child: Text('Work')),
              DropdownMenuItem(value: 'plan', child: Text('Plan')),
              DropdownMenuItem(value: 'grill', child: Text('Grill')),
            ],
            onChanged: (value) => setState(() => mode = value ?? mode),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: prompt,
            autofocus: true,
            minLines: 3,
            maxLines: 7,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Prompt'),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: workspaceId == null
                ? null
                : () {
                    final text = prompt.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(
                      context,
                      _NewChatDraft(workspaceId!, text, mode),
                    );
                  },
            child: const Text('Create and send'),
          ),
        ],
      ),
    );
  }
}
