import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

class TerminalConnection {
  WebSocketChannel? _channel;
  final String baseUrl;
  final String token;
  final String sessionId;

  final _outputController = StreamController<Uint8List>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  Stream<Uint8List> get output => _outputController.stream;
  Stream<String> get status => _statusController.stream;

  TerminalConnection({
    required this.baseUrl,
    required this.token,
    required this.sessionId,
  });

  void connect() {
    final wsUrl = baseUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsUrl/ws/terminal?session=$sessionId&token=$token');

    _channel = WebSocketChannel.connect(uri);
    _statusController.add('connected');

    _channel!.stream.listen(
      (data) {
        if (data is List<int>) {
          _outputController.add(Uint8List.fromList(data));
        } else if (data is String) {
          // On Flutter Web, WebSocket may deliver data as String
          _outputController.add(Uint8List.fromList(utf8.encode(data)));
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

  void sendInput(String data) {
    _channel?.sink.add(data);
  }

  void resize(int cols, int rows) {
    _channel?.sink.add('{"type":"resize","cols":$cols,"rows":$rows}');
  }

  void dispose() {
    _channel?.sink.close();
    _outputController.close();
    _statusController.close();
  }
}
