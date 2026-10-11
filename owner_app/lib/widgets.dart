import 'package:flutter/material.dart';

import 'period.dart';
import 'theme.dart';

/// Page header: purple bar with rounded bottom, title, logo and (optionally) the period chips.
class PageHead extends StatelessWidget {
  const PageHead({super.key, required this.title, this.subtitle, this.period, this.trailing});
  final String title;
  final String? subtitle;
  final PeriodController? period;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kPurple,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, bottom: period == null ? 18 : 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (subtitle != null) Text(subtitle!, style: const TextStyle(color: kLilac, fontSize: 14, fontWeight: FontWeight.w700)),
                Text(title, style: const TextStyle(color: kCream, fontSize: 30, fontWeight: FontWeight.w900, height: 1.15)),
              ]),
            ),
            trailing ?? Image.asset('assets/logo-cream.png', height: 30),
          ]),
        ),
        if (period != null) ...[const SizedBox(height: 14), PeriodBar(period: period!)],
      ]),
    );
  }
}

/// White rounded card with a soft shadow.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color = Colors.white});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x0F470D43), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Section title with a small note at the end.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.note = '', this.top = 26});
  final String title;
  final String note;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(4, top, 4, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kPurple)),
          const Spacer(),
          Flexible(child: Text(note, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black45))),
        ]),
      );
}

/// Small rounded label.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.bg = kCream2, this.fg = kPurple, this.icon});
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
        ]),
      );
}

/// Green or red "+12%" badge comparing with the previous period.
class DeltaBadge extends StatelessWidget {
  const DeltaBadge({super.key, required this.now, required this.before, this.onDark = false, this.lowerIsBetter = false});
  final double now;
  final double before;
  final bool onDark;
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    if (before <= 0 && now <= 0) return const SizedBox.shrink();
    final pct = before <= 0 ? 100.0 : (now - before) / before * 100;
    final up = pct >= 0;
    final good = lowerIsBetter ? !up : up;
    final fg = onDark ? (good ? const Color(0xFFA8E6B8) : const Color(0xFFFFB4B4)) : (good ? kOk : kBad);
    final bg = onDark ? Colors.white.withAlpha(28) : (good ? const Color(0xFFDDF0E3) : const Color(0xFFF6D6D6));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: fg),
        const SizedBox(width: 2),
        Text('${pct.abs().round()}%', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: fg)),
      ]),
    );
  }
}

/// Centered grey message for empty lists.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
        child: Column(children: [
          Icon(icon, size: 46, color: Colors.black26),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black45)),
        ]),
      );
}

/// Row of loyalty cups: [filled] of [need] stamped.
class StampRow extends StatelessWidget {
  const StampRow({super.key, required this.filled, required this.need, this.size = 34});
  final int filled;
  final int need;
  final double size;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
        for (var i = 0; i < need; i++)
          AnimatedScale(
            scale: i < filled ? 1 : 0.86,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Image.asset(i < filled ? 'assets/stamp-on.png' : 'assets/stamp-off.png', height: size * 1.36, width: size),
          ),
      ]);
}

/// Grab handle and title for bottom sheets.
class SheetTop extends StatelessWidget {
  const SheetTop(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(width: 44, height: 5, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(9))),
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kPurple))),
          if (trailing != null) trailing!,
        ]),
      ]);
}

/// Opens a rounded bottom sheet in the app style; returns what the sheet pops.
Future<T?> openSheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: kCream2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => child,
    );

/// Short green or red message at the bottom of the screen.
void toast(BuildContext context, String text, {bool ok = true}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
    backgroundColor: ok ? kOk : kBad,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ));
}
