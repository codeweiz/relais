import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../services/terminal_connection.dart';

class TerminalViewWidget extends StatefulWidget {
  final TerminalConnection connection;

  const TerminalViewWidget({super.key, required this.connection});

  @override
  State<TerminalViewWidget> createState() => _TerminalViewWidgetState();
}

class _TerminalViewWidgetState extends State<TerminalViewWidget> {
  late final Terminal _terminal;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);

    // Pipe terminal output to connection
    _terminal.onOutput = (data) {
      widget.connection.sendInput(data);
    };

    // Pipe connection output to terminal
    widget.connection.output.listen((Uint8List data) {
      _terminal.write(String.fromCharCodes(data));
    });

    // Connect
    widget.connection.connect();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      _terminal,
      textStyle: const TerminalStyle(fontSize: 14),
      autofocus: true,
    );
  }

  @override
  void dispose() {
    widget.connection.dispose();
    super.dispose();
  }
}
