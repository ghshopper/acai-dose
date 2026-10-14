import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'period.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Page structure
// ---------------------------------------------------------------------------

/// iOS large-title header. Shows a back button by itself on pushed pages.
class PageHead extends StatelessWidget {
  const PageHead({super.key, required this.title, this.subtitle, this.period, this.trailing, this.loading = false});
  final String title;
  final String? subtitle;
  final PeriodController? period;
  final Widget? trailing;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Container(
      color: kBg,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + (canPop ? 0 : 10), bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (canPop)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: CupertinoButton(
              padding: const EdgeInsetsDirectional.only(start: 8, end: 12, top: 8, bottom: 4),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.back, color: kPurple, size: 28),
                Text('رجوع', style: TextStyle(color: kPurple, fontSize: 17)),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 20, end: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (subtitle != null) Text(subtitle!, style: const TextStyle(color: kInk2, fontSize: 15, fontWeight: FontWeight.w600)),
                Row(children: [
                  Flexible(child: Text(title, style: const TextStyle(color: kInk, fontSize: 34, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.4))),
                  if (loading) const Padding(padding: EdgeInsetsDirectional.only(start: 10), child: CupertinoActivityIndicator(radius: 9)),
                ]),
              ]),
            ),
            if (trailing != null) trailing!,
          ]),
        ),
        if (period != null) ...[const SizedBox(height: 10), PeriodBar(period: period!)],
      ]),
    );
  }
}

/// Round icon button for headers (iOS bar button).
class BarButton extends StatelessWidget {
  const BarButton({super.key, required this.icon, required this.onPressed, this.color = kPurple, this.size = 26});
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(44, 44),
        onPressed: onPressed,
        child: Icon(icon, color: onPressed == null ? kInk3 : color, size: size),
      );
}

/// White rounded group, like an iOS inset-grouped list. Dims when pressed.
class Panel extends StatefulWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color = Colors.white});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color;

  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final box = AnimatedContainer(
      duration: Duration(milliseconds: _down ? 0 : 180),
      decoration: BoxDecoration(
        color: _down ? Color.alphaBlend(Colors.black.withAlpha(widget.color == Colors.white ? 16 : 30), widget.color) : widget.color,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: widget.padding,
      child: widget.child,
    );
    if (widget.onTap == null) return box;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: box,
    );
  }
}

/// Section header above a group.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.note = '', this.top = 26});
  final String title;
  final String note;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(6, top, 6, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.2)),
          const SizedBox(width: 10),
          Expanded(child: Text(note, textAlign: TextAlign.end, style: const TextStyle(fontSize: 13, color: kInk2))),
        ]),
      );
}

/// iOS-style row: leading icon tile, title, subtitle, chevron.
class NavRow extends StatelessWidget {
  const NavRow({super.key, required this.icon, required this.title, this.sub, this.onTap, this.tint = kPurple, this.external = false, this.danger = false});
  final IconData icon;
  final String title;
  final String? sub;
  final VoidCallback? onTap;
  final Color tint;
  final bool external;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: onTap,
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: danger ? kBad : tint, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: danger ? kBad : kInk, fontSize: 17)),
                if (sub != null) Text(sub!, style: const TextStyle(color: kInk2, fontSize: 13)),
              ]),
            ),
            Icon(external ? CupertinoIcons.arrow_up_right_square : CupertinoIcons.forward, color: kInk3, size: 20),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

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
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ]),
      );
}

/// Tappable capsule used for filters (period, sort, categories).
class Capsule extends StatelessWidget {
  const Capsule(this.label, {super.key, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 34),
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: selected ? kPurple : Colors.white, borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 15, color: selected ? Colors.white : kPurple), const SizedBox(width: 5)],
            Text(label, style: TextStyle(color: selected ? Colors.white : kInk, fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
        ),
      );
}

/// Thin rounded progress bar.
class Bar extends StatelessWidget {
  const Bar({super.key, required this.value, this.height = 6, this.color = kOrange, this.bg = kCream2});
  final double value;
  final double height;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: value.isNaN ? 0 : value.clamp(0.0, 1.0),
            child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99))),
          ),
        ),
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
    final bg = onDark ? Colors.white.withAlpha(28) : (good ? const Color(0xFFDDF2E3) : const Color(0xFFFBDAD8));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? CupertinoIcons.arrow_up : CupertinoIcons.arrow_down, size: 11, color: fg),
        const SizedBox(width: 2),
        Text('${pct.abs().round()}%', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

/// Centered grey message for empty lists.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key, this.icon = CupertinoIcons.tray});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
        child: Column(children: [
          Icon(icon, size: 44, color: kInk3),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w500, color: kInk2, fontSize: 15)),
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

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

/// iOS segmented control that fills the width.
class Seg<T extends Object> extends StatelessWidget {
  const Seg({super.key, required this.value, required this.items, required this.onChanged});
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<T>(
          groupValue: value,
          backgroundColor: kFill,
          children: {
            for (final e in items.entries)
              e.key: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Text(e.value, maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w500, color: kInk)),
              ),
          },
          onValueChanged: (v) {
            if (v == null || v == value) return;
            HapticFeedback.selectionClick();
            onChanged(v);
          },
        ),
      );
}

/// iOS switch in the brand colour.
class IosSwitch extends StatelessWidget {
  const IosSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CupertinoSwitch(value: value, activeTrackColor: kOk, onChanged: onChanged);
}

/// A label with a switch at the end, like a Settings row.
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.sub});
  final String title;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: kInk)),
              if (sub != null) Text(sub!, style: const TextStyle(fontSize: 13, color: kInk2)),
            ]),
          ),
          IosSwitch(value: value, onChanged: onChanged),
        ]),
      );
}

/// − / + control like UIStepper.
class IosStepper extends StatelessWidget {
  const IosStepper({super.key, required this.onMinus, required this.onPlus});
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  Widget _b(IconData i, VoidCallback? f) => CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: const Size(46, 34),
        onPressed: f == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                f();
              },
        child: Icon(i, size: 20, color: f == null ? kInk3 : kInk),
      );

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: kFill, borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _b(CupertinoIcons.minus, onMinus),
          Container(width: 1, height: 18, color: kInk3),
          _b(CupertinoIcons.plus, onPlus),
        ]),
      );
}

/// A row that opens an action sheet to pick one value (replaces dropdowns).
class PickField<T> extends StatelessWidget {
  const PickField({super.key, required this.value, required this.items, required this.onChanged, this.label, this.dense = false});
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final String? label;
  final bool dense;

  @override
  Widget build(BuildContext context) => Panel(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 11 : 14),
        onTap: () async {
          final v = await pickFrom<T>(context, label ?? '', items, value);
          if (v != null) onChanged(v);
        },
        child: Row(children: [
          if (label != null && !dense) ...[Text(label!, style: const TextStyle(color: kInk2, fontSize: 15)), const SizedBox(width: 10)],
          Expanded(
            child: Text(items[value] ?? '', textAlign: label != null && !dense ? TextAlign.end : TextAlign.start, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, color: kInk, fontSize: 16)),
          ),
          const SizedBox(width: 6),
          const Icon(CupertinoIcons.chevron_up_chevron_down, size: 16, color: kInk2),
        ]),
      );
}

/// Date row that opens the iOS wheel picker.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.date, required this.onPick, this.label = 'التاريخ'});
  final DateTime date;
  final ValueChanged<DateTime> onPick;
  final String label;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = date.year == now.year && date.month == now.month && date.day == now.day;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      onTap: () async {
        final d = await pickDate(context, date);
        if (d != null) onPick(d);
      },
      child: Row(children: [
        const Icon(CupertinoIcons.calendar, color: kPurple, size: 20),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: kInk2, fontSize: 15)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: kFill, borderRadius: BorderRadius.circular(8)),
          child: Text(today ? 'اليوم' : ymd(date), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w600, color: kPurple, fontSize: 15)),
        ),
      ]),
    );
  }
}

/// Plain iOS text field for alerts.
Widget alertField(TextEditingController c, {String placeholder = '', bool autofocus = false, bool ltr = false, TextInputType? keyboard, int maxLines = 1, String? suffix}) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: CupertinoTextField(
        controller: c,
        autofocus: autofocus,
        placeholder: placeholder,
        keyboardType: keyboard,
        maxLines: maxLines,
        minLines: 1,
        textDirection: ltr ? TextDirection.ltr : null,
        suffix: suffix == null ? null : Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(suffix, style: const TextStyle(color: kInk2))),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
    );

// ---------------------------------------------------------------------------
// Pop-ups
// ---------------------------------------------------------------------------

/// A button in an iOS alert.
class IosAct<T> {
  const IosAct(this.label, {this.value, this.get, this.main = false, this.danger = false});
  final String label;
  final T? value;
  final T Function()? get;
  final bool main;
  final bool danger;
}

/// iOS alert. [body] can hold text fields or a list; pops the chosen action's value.
Future<T?> showIos<T>(BuildContext context, {required String title, String? message, Widget? body, required List<IosAct<T>> actions}) => showCupertinoDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (d) => CupertinoAlertDialog(
        title: Text(title),
        content: message == null && body == null
            ? null
            : Material(
                type: MaterialType.transparency,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (message != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: kInk))),
                  if (body != null) body,
                ]),
              ),
        actions: [
          for (final a in actions)
            CupertinoDialogAction(
              isDefaultAction: a.main,
              isDestructiveAction: a.danger,
              onPressed: () => Navigator.pop(d, a.get != null ? a.get!() : a.value),
              child: Text(a.label),
            ),
        ],
      ),
    );

/// Yes/no question. True only when the second button is pressed.
Future<bool> confirm(BuildContext context, String title, {String? message, String yes = 'تمام', String no = 'إلغاء', bool danger = true}) async =>
    await showIos<bool>(context, title: title, message: message, actions: [
      IosAct(no, value: false),
      IosAct(yes, value: true, danger: danger, main: !danger),
    ]) ==
    true;

/// Action sheet listing [items]; the current one is bold.
Future<T?> pickFrom<T>(BuildContext context, String title, Map<T, String> items, T? current) => showCupertinoModalPopup<T>(
      context: context,
      builder: (d) => CupertinoActionSheet(
        title: title.isEmpty ? null : Text(title),
        actions: [
          for (final e in items.entries)
            CupertinoActionSheetAction(
              isDefaultAction: e.key == current,
              onPressed: () => Navigator.pop(d, e.key),
              child: Text(e.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
      ),
    );

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

Widget _pickerShell(BuildContext d, {required Widget child, required VoidCallback onDone, Widget? top}) => Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(d).padding.bottom),
      child: Material(
        type: MaterialType.transparency,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            CupertinoButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
            const Spacer(),
            CupertinoButton(onPressed: onDone, child: const Text('تم', style: TextStyle(fontWeight: FontWeight.w600))),
          ]),
          if (top != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: top),
          SizedBox(height: 216, child: child),
        ]),
      ),
    );

/// iOS wheel date picker (no future dates).
Future<DateTime?> pickDate(BuildContext context, DateTime initial) {
  final max = _day(DateTime.now());
  var v = _day(initial).isAfter(max) ? max : _day(initial);
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (d) => _pickerShell(
      d,
      onDone: () => Navigator.pop(d, v),
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.date,
        initialDateTime: v,
        minimumDate: DateTime(2024),
        maximumDate: max,
        onDateTimeChanged: (x) => v = _day(x),
      ),
    ),
  );
}

/// From / to picker with a segmented switch between the two dates.
Future<DateTimeRange?> pickRange(BuildContext context, DateTime from, DateTime to) {
  final max = _day(DateTime.now());
  var a = _day(from), b = _day(to).isAfter(max) ? max : _day(to);
  var side = 0;
  return showCupertinoModalPopup<DateTimeRange>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => _pickerShell(
        d,
        onDone: () => Navigator.pop(d, a.isAfter(b) ? DateTimeRange(start: b, end: a) : DateTimeRange(start: a, end: b)),
        top: Seg<int>(value: side, items: {0: 'من ${ymd(a).substring(5)}', 1: 'إلى ${ymd(b).substring(5)}'}, onChanged: (v) => set(() => side = v)),
        child: CupertinoDatePicker(
          key: ValueKey(side),
          mode: CupertinoDatePickerMode.date,
          initialDateTime: side == 0 ? a : b,
          minimumDate: DateTime(2024),
          maximumDate: max,
          onDateTimeChanged: (x) => set(() {
            if (side == 0) {
              a = _day(x);
            } else {
              b = _day(x);
            }
          }),
        ),
      ),
    ),
  );
}

/// Grabber and iOS sheet bar: close on one side, title in the middle.
class SheetTop extends StatelessWidget {
  const SheetTop(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(width: 36, height: 5, margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: kInk3, borderRadius: BorderRadius.circular(9))),
        SizedBox(
          height: 44,
          child: Row(children: [
            SizedBox(
              width: 76,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: CupertinoButton(padding: EdgeInsets.zero, onPressed: () => Navigator.of(context).maybePop(), child: const Text('إغلاق', style: TextStyle(fontSize: 17))),
              ),
            ),
            Expanded(child: Text(title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: kInk))),
            SizedBox(width: 76, child: Align(alignment: AlignmentDirectional.centerEnd, child: trailing ?? const SizedBox.shrink())),
          ]),
        ),
      ]);
}

/// Opens an iOS-style card sheet; returns what the sheet pops.
Future<T?> openSheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: kBg,
      barrierColor: Colors.black.withAlpha(70),
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => child,
    );

// ---------------------------------------------------------------------------
// Toast: a small banner that drops from the top, like iOS system HUDs
// ---------------------------------------------------------------------------

OverlayEntry? _toast;

void toast(BuildContext context, String text, {bool ok = true}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toast?.remove();
  _toast = null;
  ok ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
  late final OverlayEntry e;
  e = OverlayEntry(
    builder: (_) => _Toast(
      text: text,
      ok: ok,
      onDone: () {
        if (_toast == e) {
          _toast = null;
          e.remove();
        }
      },
    ),
  );
  _toast = e;
  overlay.insert(e);
}

class _Toast extends StatefulWidget {
  const _Toast({required this.text, required this.ok, required this.onDone});
  final String text;
  final bool ok;
  final VoidCallback onDone;
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 380), reverseDuration: const Duration(milliseconds: 260));

  @override
  void initState() {
    super.initState();
    _a.forward();
    Future.delayed(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;
      await _a.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _a, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 6,
      left: 20,
      right: 20,
      child: IgnorePointer(
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -1.4), end: Offset.zero).animate(curve),
          child: FadeTransition(
            opacity: _a,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(color: Colors.white.withAlpha(225), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.black.withAlpha(12))),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(widget.ok ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.exclamationmark_circle_fill, color: widget.ok ? kOk : kBad, size: 22),
                        const SizedBox(width: 8),
                        Flexible(child: Text(widget.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: kInk))),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
