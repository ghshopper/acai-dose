import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const Color kPurple = Color(0xFF470D43);
const Color kPurple2 = Color(0xFF5E1A55);
const Color kCream = Color(0xFFFAF3E0);
const Color kCream2 = Color(0xFFF1E9DA);
const Color kOrange = Color(0xFFE39A2E);
const Color kLilac = Color(0xFFD9BCDB);
const Color kOk = Color(0xFF248A3D);
const Color kBad = Color(0xFFE5342B);
const Color kLine = Color(0x2E3C3C43);

/// iOS grouped background, warmed a little towards the brand cream.
const Color kBg = Color(0xFFF4F0E9);

/// iOS label colours.
const Color kInk = Color(0xFF1C1C1E);
const Color kInk2 = Color(0x993C3C43);
const Color kInk3 = Color(0x4D3C3C43);

/// Field fill inside a white group.
const Color kField = Color(0xFFF1EEE9);

/// iOS tertiary fill (segmented controls, steppers, search).
const Color kFill = Color(0x1F767680);

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kPurple, primary: kPurple, secondary: kOrange, surface: Colors.white);
  final noSplash = ButtonStyle(splashFactory: NoSplash.splashFactory, overlayColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed) ? Colors.black.withAlpha(18) : Colors.transparent));
  return ThemeData(
    useMaterial3: true,
    platform: TargetPlatform.iOS,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    canvasColor: kBg,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    cupertinoOverrideTheme: const CupertinoThemeData(primaryColor: kPurple, scaffoldBackgroundColor: kBg),
    pageTransitionsTheme: PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: const CupertinoPageTransitionsBuilder()}),
    dividerTheme: const DividerThemeData(color: kLine, thickness: 0.5, space: 1),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: kPurple, selectionColor: Color(0x40470D43), selectionHandleColor: kPurple),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPurple,
        foregroundColor: Colors.white,
        disabledBackgroundColor: kPurple.withAlpha(90),
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(64, 50),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ).merge(noSplash),
    ),
    // "Tinted" iOS button: light purple fill, no outline
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPurple,
        backgroundColor: kPurple.withAlpha(20),
        minimumSize: const Size(56, 46),
        side: BorderSide.none,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ).merge(noSplash),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kPurple, textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)).merge(noSplash),
    ),
    iconButtonTheme: IconButtonThemeData(style: noSplash),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: const TextStyle(color: kInk2, fontSize: 15, fontWeight: FontWeight.w500),
      floatingLabelStyle: const TextStyle(color: kInk2, fontSize: 15, fontWeight: FontWeight.w500),
      hintStyle: const TextStyle(color: kInk3),
      suffixStyle: const TextStyle(color: kInk2, fontWeight: FontWeight.w500),
      prefixStyle: const TextStyle(color: kInk2, fontWeight: FontWeight.w500),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
  );
}

/// Big filled button (orange or purple) used on the loyalty card.
ButtonStyle bigButton(Color bg, Color fg) => FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      minimumSize: const Size(64, 50),
      elevation: 0,
      splashFactory: NoSplash.splashFactory,
      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
