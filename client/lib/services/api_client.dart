import 'package:dio/dio.dart';
import '../models/session.dart';

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

  void dispose() {
    _dio.close();
  }
}
