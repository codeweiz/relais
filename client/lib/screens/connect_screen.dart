import 'package:flutter/material.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
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
                Text(
                  'Relais',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect to a server',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://your-server.example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
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
                FilledButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Connection not yet implemented')),
                    );
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
