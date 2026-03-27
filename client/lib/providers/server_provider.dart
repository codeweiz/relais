import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/server.dart';
import '../services/api_client.dart';

class ServerState {
  final Server? server;
  final ApiClient? apiClient;
  final bool connecting;
  final String? error;

  const ServerState({this.server, this.apiClient, this.connecting = false, this.error});

  ServerState copyWith({Server? server, ApiClient? apiClient, bool? connecting, String? error}) {
    return ServerState(
      server: server ?? this.server,
      apiClient: apiClient ?? this.apiClient,
      connecting: connecting ?? this.connecting,
      error: error,
    );
  }

  bool get isConnected => server != null && apiClient != null && error == null;
}

class ServerNotifier extends StateNotifier<ServerState> {
  ServerNotifier() : super(const ServerState());

  Future<void> connect(String url, String token, {String name = 'Default'}) async {
    state = state.copyWith(connecting: true, error: null);

    final cleanUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final api = ApiClient(baseUrl: cleanUrl, token: token);

    try {
      await api.getStatus();
      final server = Server(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        url: cleanUrl,
        token: token,
      );
      state = ServerState(server: server, apiClient: api);
      await _saveServer(server);
    } catch (e) {
      api.dispose();
      state = state.copyWith(connecting: false, error: e.toString());
    }
  }

  void disconnect() {
    state.apiClient?.dispose();
    state = const ServerState();
  }

  Future<List<Server>> loadSavedServers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('saved_servers');
    if (data == null) return [];
    final list = jsonDecode(data) as List;
    return list.map((e) => Server.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _saveServer(Server server) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadSavedServers();
    existing.removeWhere((s) => s.url == server.url);
    existing.insert(0, server);
    await prefs.setString('saved_servers', jsonEncode(existing.map((s) => s.toJson()).toList()));
  }
}

final serverProvider = StateNotifierProvider<ServerNotifier, ServerState>((ref) {
  return ServerNotifier();
});
