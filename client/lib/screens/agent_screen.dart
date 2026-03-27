import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/session.dart';
import '../providers/server_provider.dart';
import '../services/agent_connection.dart';
import '../models/agent_message.dart';
import '../widgets/agent_chat.dart';
import '../widgets/session_switcher.dart';
import '../l10n/strings.dart';

class AgentScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const AgentScreen({super.key, required this.sessionId});

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  AgentConnection? _connection;
  final _messages = <AgentMessage>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  String _status = 'connecting';
  bool _waiting = false;
  StreamSubscription? _messageSub;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    final server = ref.read(serverProvider).server;
    if (server != null) {
      _connection = AgentConnection(
        baseUrl: server.url,
        token: server.token,
        sessionId: widget.sessionId,
      );

      _messageSub = _connection!.messages.listen((msg) {
        if (!mounted) return;

        // Skip echoed user messages from server (we added them locally)
        if (msg.type == AgentMessageType.user && msg.source == 'web') return;

        // Skip turn_complete (just a noise marker)
        if (msg.type == AgentMessageType.turnComplete) {
          setState(() => _waiting = false);
          return;
        }

        setState(() {
          // Agent started responding — hide waiting indicator
          if (msg.type == AgentMessageType.text) _waiting = false;

          if (msg.type == AgentMessageType.text && msg.streaming) {
            final idx = _messages.indexWhere((m) => m.id == msg.id);
            if (idx >= 0) {
              _messages[idx] = msg;
            } else {
              _messages.add(msg);
            }
          } else {
            _messages.add(msg);
          }
        });
        _scrollToBottom();
      });

      _statusSub = _connection!.status.listen((s) {
        if (!mounted) return;
        setState(() => _status = s);
      });

      _connection!.connect();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty || _connection == null) return;

    setState(() {
      _messages.add(AgentMessage(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        type: AgentMessageType.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _waiting = true;
    });

    _connection!.sendMessage(text);
    _inputController.clear();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _statusSub?.cancel();
    _connection?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_connection == null) {
      return Scaffold(body: Center(child: Text(S.notConnected)));
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/home')),
        title: SessionSwitcher(
          currentSessionId: widget.sessionId,
          filterKind: SessionKind.agent,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      _status == 'connected' ? Colors.green : Colors.orange,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(S.sendHint,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.outline)),
                  )
                : AgentChat(
                    messages: _messages,
                    scrollController: _scrollController),
          ),
          if (_waiting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Agent 思考中...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: InputDecoration(
                        hintText: S.sendMessage,
                        border: const OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
