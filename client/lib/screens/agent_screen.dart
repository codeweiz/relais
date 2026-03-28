import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/agent_message.dart';
import '../models/agent_status.dart';
import '../models/session.dart';
import '../models/slash_command.dart';
import '../providers/agent_status_provider.dart';
import '../providers/server_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/agent_provider.dart';
import '../providers/task_provider.dart';
import '../widgets/agent_chat.dart';
import '../widgets/agent_picker_menu.dart';
import '../widgets/dispatch_dialog.dart';
import '../widgets/session_switcher.dart';
import '../widgets/slash_command_menu.dart';
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
  final _inputFocusNode = FocusNode();
  AgentSession? _session;
  final _speech = stt.SpeechToText();
  bool _isListening = false;
  final _layerLink = LayerLink();
  final _menuController = SlashCommandMenuController();
  bool _showingMenu = false;
  final _agentPickerController = AgentPickerController();
  bool _showingAgentPicker = false;

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
    // Scroll to bottom after the first frame so existing history is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
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

  void _onInputChanged(String text) {
    final session = _session;
    if (session == null) return;

    if (text.startsWith('/') && !text.contains(' ')) {
      final filter = text.substring(1);
      final dynamic = session.availableCommands ?? [];
      final builtins = ref.read(settingsProvider).builtinSlashCommands
          .map((m) => SlashCommand(name: m['name']!, description: m['description']!))
          .toList();
      final dynamicNames = dynamic.map((c) => c.name).toSet();
      final merged = [...dynamic, ...builtins.where((c) => !dynamicNames.contains(c.name))];

      if (!_showingMenu) {
        _showingMenu = true;
        _menuController.show(
          context: context,
          layerLink: _layerLink,
          commands: merged,
          filter: filter,
          onSelect: _onCommandSelected,
          onDismiss: _onMenuDismissed,
        );
      } else {
        _menuController.updateFilter(
          context: context,
          layerLink: _layerLink,
          commands: merged,
          filter: filter,
          onSelect: _onCommandSelected,
          onDismiss: _onMenuDismissed,
        );
      }
    } else {
      _dismissMenu();
    }

    // @ agent picker
    if (text.startsWith('@') && !text.contains(' ')) {
      final agents = ref.read(agentStatusProvider);
      final agentList = agents.values
          .where((a) => a.sessionId != widget.sessionId)
          .toList();
      if (agentList.isNotEmpty) {
        if (!_showingAgentPicker) {
          _showingAgentPicker = true;
          _agentPickerController.show(
            context: context,
            layerLink: _layerLink,
            agents: agentList,
            onSelect: _onAgentSelected,
            onDismiss: () => _showingAgentPicker = false,
          );
        }
      }
    } else if (_showingAgentPicker) {
      _agentPickerController.dismiss();
      _showingAgentPicker = false;
    }
  }

  void _onCommandSelected(SlashCommand cmd) {
    _inputController.text = '/${cmd.name} ';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
    _showingMenu = false;
    // Re-focus the text field so the user can type arguments or press Enter
    _inputFocusNode.requestFocus();
  }

  void _onMenuDismissed() {
    _showingMenu = false;
  }

  void _dismissMenu() {
    if (_showingMenu) {
      _menuController.dismiss();
      _showingMenu = false;
    }
  }

  void _onAgentSelected(AgentStatusInfo agent) {
    _inputController.text = '@${agent.name} ';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
    _showingAgentPicker = false;
    _inputFocusNode.requestFocus();
  }

  Future<void> _dispatchTask(String text) async {
    // Parse @name description
    final spaceIndex = text.indexOf(' ');
    if (spaceIndex < 0) return;
    final targetName = text.substring(1, spaceIndex);
    final description = text.substring(spaceIndex + 1).trim();
    if (description.isEmpty) return;

    // Validate agent exists
    final agents = ref.read(agentStatusProvider);
    final targetExists = agents.values.any((a) => a.name == targetName);
    if (!targetExists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.agentNotFound)),
        );
      }
      return;
    }

    // Create task
    final taskNotifier = ref.read(taskProvider.notifier);
    await taskNotifier.createTask(
      title: description.length > 50
          ? '${description.substring(0, 50)}...'
          : description,
      prompt: description,
      targetAgent: targetName,
      sourceSessionId: widget.sessionId,
    );

    // Insert local system message
    _session!.messages.add(AgentMessage(
      id: 'dispatch-${DateTime.now().millisecondsSinceEpoch}',
      type: AgentMessageType.progress,
      content: S.dispatched(targetName, description),
      timestamp: DateTime.now(),
    ));
    if (mounted) setState(() {});
  }

  void _showDispatchDialog() {
    final agents = ref.read(agentStatusProvider);
    final agentList = agents.values
        .where((a) => a.sessionId != widget.sessionId)
        .toList();
    showDialog(
      context: context,
      builder: (_) => DispatchDialog(
        agents: agentList,
        onDispatch: (targetAgent, title, prompt, priority) async {
          final taskNotifier = ref.read(taskProvider.notifier);
          await taskNotifier.createTask(
            title: title,
            prompt: prompt.isEmpty ? title : prompt,
            priority: priority,
            targetAgent: targetAgent,
            sourceSessionId: widget.sessionId,
          );
          _session!.messages.add(AgentMessage(
            id: 'dispatch-${DateTime.now().millisecondsSinceEpoch}',
            type: AgentMessageType.progress,
            content: S.dispatched(targetAgent, title),
            timestamp: DateTime.now(),
          ));
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _sendMessage() {
    _dismissMenu();
    final text = _inputController.text.trim();
    if (text.isEmpty || _session == null) return;

    // @ dispatch — don't send to current agent
    if (text.startsWith('@') && text.contains(' ')) {
      _dispatchTask(text);
      _inputController.value = TextEditingValue.empty;
      return;
    }

    // Cancel voice if active — cancel() doesn't fire a final result callback
    if (_isListening) {
      _speech.cancel();
      _isListening = false;
    }

    _session!.sendMessage(text);
    _inputController.value = TextEditingValue.empty;
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
        if (!_isListening) return; // Ignore late callbacks after cancel/send
        _inputController.text = result.recognizedWords;
        // Move cursor to end
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
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
    _inputFocusNode.dispose();
    _menuController.dismiss();
    _agentPickerController.dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return Scaffold(body: Center(child: Text(S.notConnected)));
    }

    final session = _session!;
    final settings = ref.watch(settingsProvider);

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
                    fontSize: settings.fontSize,
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
                  IconButton(
                    onPressed: _showDispatchDialog,
                    icon: const Text('@',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        )),
                    tooltip: S.dispatchTo,
                  ),
                  Expanded(
                    child: CompositedTransformTarget(
                      link: _layerLink,
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocusNode,
                        decoration: InputDecoration(
                          hintText: S.sendMessage,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          isDense: true,
                        ),
                        onChanged: _onInputChanged,
                        onSubmitted: (_) => _sendMessage(),
                        textInputAction: TextInputAction.send,
                      ),
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
