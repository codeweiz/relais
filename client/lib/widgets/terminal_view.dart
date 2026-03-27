import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xterm/xterm.dart';

/// Pure rendering widget — takes an existing Terminal object,
/// does NOT manage connection lifecycle.
class TerminalViewWidget extends StatelessWidget {
  final Terminal terminal;
  final double fontSize;

  const TerminalViewWidget({
    super.key,
    required this.terminal,
    this.fontSize = 14.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0d1117),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: TerminalView(
          terminal,
          textStyle: TerminalStyle(
            fontSize: fontSize,
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
}
