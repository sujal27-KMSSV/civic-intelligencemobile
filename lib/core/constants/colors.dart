import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF1A73E8);
  static const Color secondary = Color(0xFF34A853);
  static const Color error = Color(0xFFD93025);
  static const Color warning = Color(0xFFFBBC04);
  static const Color critical = Color(0xFFD93025);
  static const Color high = Color(0xFFEA4335);
  static const Color medium = Color(0xFFFBBC04);
  static const Color low = Color(0xFF34A853);
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Colors.white;
}

class AppDurations {
  AppDurations._();

  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 350);
  static const Duration long = Duration(milliseconds: 500);
}
