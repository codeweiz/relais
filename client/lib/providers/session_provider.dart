import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/session.dart';
import 'server_provider.dart';

class SessionNotifier extends StateNotifier<AsyncValue<List<Session>>> {
  final Ref ref;

  SessionNotifier(this.ref) : super(const AsyncValue.loading());

  Future<void> refresh() async {
    final api = ref.read(serverProvider).apiClient;
    if (api == null) {
      state = const AsyncValue.data([]);
      return;
    }

    state = const AsyncValue.loading();
    try {
      final sessions = await api.getSessions();
      sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = AsyncValue.data(sessions);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<String?> createTerminal(String name) async {
    final api = ref.read(serverProvider).apiClient;
    if (api == null) return null;

    try {
      final result = await api.createSession(name: name, type: 'terminal');
      await refresh();
      return result['id'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<String?> createAgent(String name, {String provider = 'claude-code'}) async {
    final api = ref.read(serverProvider).apiClient;
    if (api == null) return null;

    try {
      final result = await api.createSession(name: name, type: 'agent', provider: provider);
      await refresh();
      return result['id'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteSession(String id) async {
    final api = ref.read(serverProvider).apiClient;
    if (api == null) return;

    try {
      await api.deleteSession(id);
      await refresh();
    } catch (_) {}
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, AsyncValue<List<Session>>>((ref) {
  return SessionNotifier(ref);
});
