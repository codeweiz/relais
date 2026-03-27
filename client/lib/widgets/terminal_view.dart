import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xterm/xterm.dart';
import '../services/terminal_connection.dart';

class TerminalViewWidget extends StatefulWidget {
  final TerminalConnection connection;
  final double fontSize;

  const TerminalViewWidget({super.key, required this.connection, this.fontSize = 14.0});

  @override
  State<TerminalViewWidget> createState() => _TerminalViewWidgetState();
}

class _TerminalViewWidgetState extends State<TerminalViewWidget> {
  late final Terminal _terminal;
  StreamSubscription? _outputSubscription;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 100);

    // Keyboard input → server (binary)
    _terminal.onOutput = (data) {
      widget.connection.sendInput(data);
    };

    // Wait for first resize before connecting — this ensures the server
    // knows the correct terminal size before sending capture-pane content.
    _terminal.onResize = (cols, rows, pixelWidth, pixelHeight) {
      if (!_connected) {
        _connected = true;
        // Connect and immediately send resize so server has correct size
        // before capture-pane fires
        widget.connection.connect();
        widget.connection.resize(cols, rows);

        // Start listening to output after connect
        _outputSubscription = widget.connection.output.listen((Uint8List data) {
          try {
            _terminal.write(utf8.decode(data, allowMalformed: true));
          } catch (_) {
            // xterm dart package has a bug in eraseLineToCursor when
            // cursor is at position 0 (index -1 access). Silently
            // ignore — the terminal continues working.
          }
        });
      } else {
        widget.connection.resize(cols, rows);
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0d1117),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: TerminalView(
          _terminal,
          textStyle: TerminalStyle(
            fontSize: widget.fontSize,
            fontFamily: GoogleFonts.jetBrainsMono().fontFamily ?? 'monospace',
          ),
          theme: const TerminalTheme(
            cursor: Color(0xFFc9d1d9),
            selection: Color(0x40388bfd),
            foreground: Color(0xFFc9d1d9),
            background: Color(0xFF0d1117),
            black: Color(0xFF484f58),
            red: Color(0xFFff7b72),
            green: Color(0xFF3fb950),
            yellow: Color(0xFFd29922),
            blue: Color(0xFF58a6ff),
            magenta: Color(0xFFbc8cff),
            cyan: Color(0xFF39d2db),
            white: Color(0xFFb1bac4),
            brightBlack: Color(0xFF6e7681),
            brightRed: Color(0xFFffa198),
            brightGreen: Color(0xFF56d364),
            brightYellow: Color(0xFFe3b341),
            brightBlue: Color(0xFF79c0ff),
            brightMagenta: Color(0xFFd2a8ff),
            brightCyan: Color(0xFF56d4dd),
            brightWhite: Color(0xFFf0f6fc),
            searchHitBackground: Color(0xFFffd33d),
            searchHitBackgroundCurrent: Color(0xFFf2cc60),
            searchHitForeground: Color(0xFF0d1117),
          ),
          autofocus: true,
          alwaysShowCursor: true,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    widget.connection.dispose();
    super.dispose();
  }
}
