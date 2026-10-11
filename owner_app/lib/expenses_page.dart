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
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تحذف هذا المصروف؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لا')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: kBad), onPressed: () => Navigator.pop(c, true), child: const Text('احذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.post('delete', {'type': 'expense', 'id': (r['id'] as num).toInt()});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errText(e))));
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
      backgroundColor: kCream2,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: kOrange,
        foregroundColor: kPurple,
        icon: const Icon(Icons.add),
        label: const Text('مصروف جديد', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(children: [
        PageHead(title: 'المصاريف', period: widget.period),
        if (_loading) const LinearProgressIndicator(minHeight: 3, color: kOrange, backgroundColor: kCream2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(22)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('مصاريف الفترة', style: TextStyle(color: kLilac, fontWeight: FontWeight.w800)),
                  Text(money(total), textDirection: TextDirection.ltr, style: const TextStyle(color: kCream, fontSize: 36, fontWeight: FontWeight.w900)),
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(child: Text(c.key, style: const TextStyle(color: kCream, fontWeight: FontWeight.w600, fontSize: 13))),
                          Text(money(c.value), textDirection: TextDirection.ltr, style: const TextStyle(color: kCream, fontWeight: FontWeight.w800)),
                        ]),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(value: total > 0 ? c.value / total : 0, minHeight: 5, color: kOrange, backgroundColor: kPurple2),
                        ),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              if (_exps.isEmpty)
                const EmptyNote('ما فيه مصاريف في هالفترة', icon: Icons.payments_outlined),
              for (final r in _exps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['category']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${r['expense_date']}${(r['note'] ?? '') != '' ? ' · ${r['note']}' : ''}',
                            style: const TextStyle(color: Colors.black45, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    Text(money(r['amount']), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    IconButton(onPressed: () => _delete(r), icon: const Icon(Icons.delete_outline, color: kBad)),
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
