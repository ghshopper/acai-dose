import 'package:flutter/material.dart';

import 'api.dart';

const Color kPurple = Color(0xFF470D43);
const Color kPurple2 = Color(0xFF5E1A55);
const Color kCream = Color(0xFFFAF3E0);
const Color kCream2 = Color(0xFFF1E6CF);
const Color kOrange = Color(0xFFE39A2E);
const Color kLilac = Color(0xFFD9BCDB);
const Color kOk = Color(0xFF2F7D4F);
const Color kBad = Color(0xFFB23A3A);
const Color kLine = Color(0xFFE3D6BF);

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
    if (!shop.isKarak) return Image.asset(dark ? 'assets/logo-cream.png' : 'assets/logo-purple.png', height: height);
    final c = dark ? kCream : const Color(0xFF3A3A3C);
    return SizedBox(
      height: height,
      child: FittedBox(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('كرك دوز', style: TextStyle(color: c, fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
          Text('K A R A K   D O S E', style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        ]),
      ),
    );
  }
}
