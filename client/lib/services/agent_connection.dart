import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/agent_message.dart';

class AgentConnection {
  WebSocketChannel? _channel;
  final String baseUrl;
  final String token;
  final String sessionId;

  final _messageController = StreamController<AgentMessage>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  Stream<AgentMessage> get messages => _messageController.stream;
  Stream<String> get status => _statusController.stream;

  AgentConnection({
    required this.baseUrl,
    required this.token,
    required this.sessionId,
  });

  void connect() {
    final wsUrl = baseUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsUrl/ws/agent?session=$sessionId&token=$token');

    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (data) {
        if (data is String) {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final type = json['type'] as String?;

          if (type == 'status') {
            _statusController.add(json['status'] as String? ?? 'unknown');
            return;
          }

          final msg = AgentMessage.fromServerEvent(json);
          _messageController.add(msg);
        }
      },
      onError: (error) {
        _statusController.add('error');
      },
      onDone: () {
        _statusController.add('disconnected');
      },
    );
  }

  void sendMessage(String text) {
    _channel?.sink.add(jsonEncode({'type': 'message', 'text': text}));
  }

  void cancel() {
    _channel?.sink.add(jsonEncode({'type': 'cancel'}));
  }

  void dispose() {
    _channel?.sink.close();
    _messageController.close();
    _statusController.close();
  }
}
