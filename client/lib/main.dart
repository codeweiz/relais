import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Preload terminal font to avoid flicker
  await GoogleFonts.pendingFonts([
    GoogleFonts.jetBrainsMono(),
  ]);
  runApp(const ProviderScope(child: RelaisApp()));
}
