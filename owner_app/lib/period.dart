import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'widgets.dart';

/// The date range the summary, orders and expenses tabs show. Shared by all tabs.
class PeriodController extends ChangeNotifier {
  String key = 'today';
  late DateTime from;
  late DateTime to;

  PeriodController() {
    set('today');
  }

  String get fromStr => ymd(from);
  String get toStr => ymd(to);

  void set(String k) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    key = k;
    switch (k) {
      case 'yest':
        from = to = today.subtract(const Duration(days: 1));
      case 'week':
        to = today;
        from = today.subtract(const Duration(days: 6));
      case 'month':
        to = today;
        from = DateTime(today.year, today.month, 1);
      case 'last':
        from = DateTime(today.year, today.month - 1, 1);
        to = DateTime(today.year, today.month, 0);
      default:
        key = 'today';
        from = to = today;
    }
    notifyListeners();
  }

  void custom(DateTimeRange r) {
    key = 'custom';
    from = r.start;
    to = r.end;
    notifyListeners();
  }

  List<DateTime> get days {
    final out = <DateTime>[];
    for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
      out.add(d);
    }
    return out;
  }
}

/// Period capsules plus a custom range picker.
class PeriodBar extends StatelessWidget {
  const PeriodBar({super.key, required this.period});
  final PeriodController period;

  static const _opts = [
    ['today', 'اليوم'],
    ['yest', 'أمس'],
    ['week', '٧ أيام'],
    ['month', 'هذا الشهر'],
    ['last', 'الشهر الماضي'],
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: period,
      builder: (context, _) => SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          for (final o in _opts)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Capsule(o[1], selected: period.key == o[0], onTap: () => period.set(o[0])),
            ),
          Capsule(
            period.key == 'custom' ? '${period.fromStr.substring(5)} ← ${period.toStr.substring(5)}' : 'تاريخ',
            icon: CupertinoIcons.calendar,
            selected: period.key == 'custom',
            onTap: () async {
              final r = await pickRange(context, period.from, period.to);
              if (r != null) period.custom(r);
            },
          ),
        ]),
      ),
    );
  }
}
