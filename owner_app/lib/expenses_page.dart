import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'period.dart';
import 'sheets.dart';
import 'stats.dart';
import 'theme.dart';
import 'widgets.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.period, required this.onLoggedOut});
  final PeriodController period;
  final VoidCallback onLoggedOut;
  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  List<Map<String, dynamic>> _exps = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.period.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.period.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Api.I.get('range', {'from': widget.period.fromStr, 'to': widget.period.toStr});
      _exps = ((r as Map)['exps'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on ApiError catch (e) {
      if (e.code == 'login_required' || e.code == 'forbidden') {
        widget.onLoggedOut();
        return;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final ok = await openSheet<bool>(context, const AddExpenseSheet());
    if (ok == true) {
      _load();
      if (mounted) toast(context, 'انحفظ المصروف');
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await confirm(context, 'تحذف هذا المصروف؟', yes: 'احذف');
    if (ok != true) return;
    try {
      await Api.I.post('delete', {'type': 'expense', 'id': (r['id'] as num).toInt()});
    } catch (e) {
      if (mounted) toast(context, errText(e), ok: false);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _exps.fold(0.0, (s, r) => s + numOf(r['amount']));
    final byCat = <String, double>{};
    for (final r in _exps) {
      byCat['${r['category']}'] = (byCat['${r['category']}'] ?? 0) + numOf(r['amount']);
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      backgroundColor: kBg,
      body: Column(children: [
        PageHead(title: 'المصاريف', period: widget.period, loading: _loading, trailing: BarButton(icon: CupertinoIcons.add_circled_solid, size: 30, onPressed: _add)),
        Expanded(
          child: RefreshIndicator.adaptive(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('مصاريف الفترة', style: TextStyle(color: kLilac, fontWeight: FontWeight.w600)),
                  Text(money(total), textDirection: TextDirection.ltr, style: const TextStyle(color: kCream, fontSize: 36, fontWeight: FontWeight.w700)),
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(child: Text(c.key, style: const TextStyle(color: kCream, fontWeight: FontWeight.w600, fontSize: 13))),
                          Text(money(c.value), textDirection: TextDirection.ltr, style: const TextStyle(color: kCream, fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 4),
                        Bar(value: total > 0 ? c.value / total : 0.0, height: 5, color: kOrange, bg: kPurple2),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              if (_exps.isEmpty)
                const EmptyNote('ما فيه مصاريف في هالفترة', icon: CupertinoIcons.creditcard),
              for (final r in _exps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['category']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${r['expense_date']}${(r['note'] ?? '') != '' ? ' · ${r['note']}' : ''}',
                            style: const TextStyle(color: kInk2, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    Text(money(r['amount']), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    BarButton(icon: CupertinoIcons.trash, color: kBad, size: 20, onPressed: () => _delete(r)),
                  ]),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
