import 'package:flutter/material.dart';

import 'api.dart';

/// Built for Karak Dose (charcoal and karak caramel) or Açaí Dose (purple and orange); chosen when the app is built.
const bool kKarak = String.fromEnvironment('SHOP') == 'karak';
const Color kPurple = kKarak ? Color(0xFF393939) : Color(0xFF470D43);
const Color kPurple2 = kKarak ? Color(0xFF4A4A4A) : Color(0xFF5E1A55);
const Color kCream = kKarak ? Color(0xFFF7EFE4) : Color(0xFFFAF3E0);
const Color kCream2 = kKarak ? Color(0xFFF1EEEA) : Color(0xFFF1E6CF);
const Color kOrange = kKarak ? Color(0xFFC9853A) : Color(0xFFE39A2E);
const Color kLilac = kKarak ? Color(0xFFD9D3CC) : Color(0xFFD9BCDB);
const Color kOk = Color(0xFF2F7D4F);
const Color kBad = Color(0xFFB23A3A);
const Color kLine = kKarak ? Color(0xFFE2DDD6) : Color(0xFFE3D6BF);

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kPurple, primary: kPurple, secondary: kOrange, surface: Colors.white);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kCream2,
    appBarTheme: const AppBarTheme(backgroundColor: kPurple, foregroundColor: kCream, elevation: 0),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPurple,
        foregroundColor: kCream,
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPurple,
        minimumSize: const Size(56, 48),
        side: const BorderSide(color: kPurple, width: 2),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kLine, width: 2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kLine, width: 2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kPurple, width: 2)),
    ),
    cardTheme: const CardThemeData(color: Colors.white, elevation: 0, margin: EdgeInsets.zero),
  );
}

/// Big orange or purple action button used on cards and the POS.
ButtonStyle bigButton(Color bg, Color fg) => FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      minimumSize: const Size(64, 58),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

/// The shop's logo: Açaí Dose's picture, or Karak Dose's name set in type.
class ShopLogo extends StatelessWidget {
  const ShopLogo({super.key, required this.shop, required this.dark, required this.height});
  final Shop shop;
  final bool dark; // true = on the purple bar (light logo)
  final double height;

  @override
  Widget build(BuildContext context) {
    if (shop.isKarak) return Image.asset(dark ? 'assets/karak-white.png' : 'assets/karak-dark.png', height: height);
    return Image.asset(dark ? 'assets/logo-cream.png' : 'assets/logo-purple.png', height: height);
  }
}
