import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  final _terminalKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);

    // Pipe terminal keyboard input to server
    _terminal.onOutput = (data) {
      widget.connection.sendInput(data);
    };

    // Pipe server output to terminal
    widget.connection.output.listen((Uint8List data) {
      _terminal.write(utf8.decode(data, allowMalformed: true));
    });

    // Connect
    widget.connection.connect();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Send resize when layout changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _sendResize(constraints);
        });

        return Container(
          color: const Color(0xFF0d1117),
          child: TerminalView(
            _terminal,
            key: _terminalKey,
            textStyle: TerminalStyle(
              fontSize: 14,
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
        );
      },
    );
  }

  void _sendResize(BoxConstraints constraints) {
    // Estimate character cell size (approximate for the font)
    const charWidth = 8.4; // JetBrains Mono at 14px
    const charHeight = 18.0;

    final cols = (constraints.maxWidth / charWidth).floor().clamp(10, 500);
    final rows = (constraints.maxHeight / charHeight).floor().clamp(2, 200);

    widget.connection.resize(cols, rows);
  }

  @override
  void dispose() {
    widget.connection.dispose();
    super.dispose();
  }
}
