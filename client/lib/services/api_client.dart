import 'package:dio/dio.dart';
import '../models/agent_status.dart';
import '../models/session.dart';
import '../models/task.dart';

class ApiClient {
  final Dio _dio;
  final String baseUrl;
  final String token;

  ApiClient({required this.baseUrl, required this.token})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  Future<Map<String, dynamic>> getStatus() async {
    final resp = await _dio.get('/api/v1/status');
    return resp.data as Map<String, dynamic>;
  }

  Future<List<Session>> getSessions() async {
    final resp = await _dio.get('/api/v1/sessions');
    final list = resp.data as List;
    return list.map((e) => Session.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> createSession({
    required String name,
    String type = 'terminal',
    String? provider,
    String? model,
    String? cwd,
  }) async {
    final resp = await _dio.post('/api/v1/sessions', data: {
      'name': name,
      'type': type,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (cwd != null) 'cwd': cwd,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<void> deleteSession(String id) async {
    await _dio.delete('/api/v1/sessions/$id');
  }

  Future<List<Map<String, dynamic>>> getPlugins() async {
    final resp = await _dio.get('/api/v1/plugins');
    final list = resp.data as List;
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getTunnelStatus() async {
    final resp = await _dio.get('/api/v1/tunnel/status');
    return resp.data as Map<String, dynamic>;
  }

  Future<List<AgentStatusInfo>> getAgentStatuses() async {
    final resp = await _dio.get('/api/v1/agents/status');
    final list = resp.data as List;
    return list
        .map((e) => AgentStatusInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TaskInfo>> getTasks() async {
    final resp = await _dio.get('/api/v1/tasks');
    final list = resp.data as List;
    return list
        .map((e) => TaskInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> createTask({
    required String title,
    String prompt = '',
    String priority = 'p1',
    String? targetAgent,
    String? provider,
    String? sourceSessionId,
    String? cwd,
  }) async {
    final resp = await _dio.post('/api/v1/tasks', data: {
      'title': title,
      if (prompt.isNotEmpty) 'prompt': prompt,
      'priority': priority,
      if (targetAgent != null) 'target_agent': targetAgent,
      if (provider != null) 'provider': provider,
      if (sourceSessionId != null) 'source_session_id': sourceSessionId,
      if (cwd != null) 'cwd': cwd,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<void> cancelTask(String id) async {
    await _dio.delete('/api/v1/tasks/$id');
  }

  void dispose() {
    _dio.close();
  }
}
