import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/session.dart';
import '../providers/server_provider.dart';
import '../providers/agent_provider.dart';
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
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  AgentSession? _session;
  final _speech = stt.SpeechToText();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    final server = ref.read(serverProvider).server;
    if (server != null) {
      _session = ref.read(agentSessionManagerProvider).getOrCreate(
        sessionId: widget.sessionId,
        baseUrl: server.url,
        token: server.token,
      );
      _session!.addListener(_onUpdate);
    }
  }

  void _onUpdate() {
    if (mounted) setState(() {});
    _scrollToBottom();
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
    if (text.isEmpty || _session == null) return;

    // Stop voice if active
    if (_isListening) {
      _speech.stop();
      _isListening = false;
    }

    _session!.sendMessage(text);
    _inputController.clear();
    setState(() {}); // Ensure UI updates after clear
    _scrollToBottom();
  }

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    final available = await _speech.initialize(
      onError: (_) => setState(() => _isListening = false),
    );
    if (!available) return;

    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'zh-CN',
      onResult: (result) {
        _inputController.text = result.recognizedWords;
        if (result.finalResult) {
          setState(() => _isListening = false);
        }
      },
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _session?.removeListener(_onUpdate);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return Scaffold(body: Center(child: Text(S.notConnected)));
    }

    final session = _session!;

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
                  color: session.status == 'connected'
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: session.messages.isEmpty && !session.waiting
                ? Center(
                    child: Text(S.sendHint,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(
                                color: Theme.of(context).colorScheme.outline)),
                  )
                : AgentChat(
                    messages: session.messages,
                    scrollController: _scrollController,
                    waiting: session.waiting,
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
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _toggleVoice,
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    tooltip: _isListening ? '停止' : '语音输入',
                  ),
                  const SizedBox(width: 4),
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
