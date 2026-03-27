import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/server_provider.dart';
import '../models/server.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  List<Server> _savedServers = [];

  @override
  void initState() {
    super.initState();
    _loadSavedServers();
  }

  Future<void> _loadSavedServers() async {
    final servers = await ref.read(serverProvider.notifier).loadSavedServers();
    setState(() => _savedServers = servers);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// Parse a URL that may contain ?token= query param.
  /// e.g. "http://127.0.0.1:3000?token=abc123" → url + token split.
  void _parseUrlInput() {
    final input = _urlController.text.trim();
    try {
      final uri = Uri.parse(input);
      final tokenParam = uri.queryParameters['token'];
      if (tokenParam != null && tokenParam.isNotEmpty) {
        // Strip token from URL, put it in token field
        final cleanUri = uri.replace(queryParameters: {});
        final cleanUrl = cleanUri.toString().replaceAll('?', '').replaceAll(RegExp(r'/$'), '');
        _urlController.text = cleanUrl;
        _tokenController.text = tokenParam;
      }
    } catch (_) {
      // Not a valid URL, ignore
    }
  }

  Future<void> _connect() async {
    _parseUrlInput();
    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();
    if (url.isEmpty || token.isEmpty) return;

    await ref.read(serverProvider.notifier).connect(url, token);
    final state = ref.read(serverProvider);
    if (state.isConnected && mounted) {
      context.go('/home');
    } else if (state.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: ${state.error}')),
      );
    }
  }

  void _selectServer(Server server) {
    _urlController.text = server.url;
    _tokenController.text = server.token;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serverProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.terminal_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text('Relais',
                      style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Connect to a server',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'http://host:3000?token=xxx',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                    onChanged: (_) => _parseUrlInput(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      labelText: 'Token',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: state.connecting ? null : _connect,
                      icon: state.connecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.link),
                      label: Text(
                          state.connecting ? 'Connecting...' : 'Connect'),
                    ),
                  ),
                  if (_savedServers.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Saved Servers',
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    const SizedBox(height: 8),
                    ...(_savedServers.map((s) => Card.filled(
                          child: ListTile(
                            leading: const Icon(Icons.dns),
                            title: Text(s.name),
                            subtitle: Text(s.url),
                            onTap: () => _selectServer(s),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        ))),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
