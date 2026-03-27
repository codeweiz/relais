import 'package:flutter/material.dart';

class AppTheme {
  static const seedColor = Color(0xFF6750A4);

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seedColor,
        brightness: Brightness.light,
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seedColor,
        brightness: Brightness.dark,
      );
}
