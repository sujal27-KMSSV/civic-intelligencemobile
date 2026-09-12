import 'package:flutter/material.dart';
import '../constants/colors.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final Color? background;
  final Color? foreground;

  const AppLogo({
    super.key,
    this.size = 64,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? AppColors.primary,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(
        Icons.location_city,
        size: size * 0.55,
        color: foreground ?? Colors.white,
      ),
    );
  }
}