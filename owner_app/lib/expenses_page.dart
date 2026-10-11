import 'package:flutter/material.dart';

import 'api.dart';
import 'period.dart';
import 'stats.dart';
import 'summary_page.dart';
import 'theme.dart';

const List<String> kCats = ['مواد خام (آساي وفواكه)', 'أكواب وتغليف', 'رواتب', 'إيجار', 'كهرباء وماء', 'تسويق وإعلانات', 'صيانة', 'أخرى'];

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
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCream2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (c) => const _AddExpense(),
    );
    if (ok == true) _load();
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
                      child: Row(children: [
                        Expanded(child: Text(c.key, style: const TextStyle(color: kCream, fontWeight: FontWeight.w600, fontSize: 13))),
                        Text(money(c.value), textDirection: TextDirection.ltr, style: const TextStyle(color: kCream, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              if (_exps.isEmpty)
                const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('ما فيه مصاريف في هالفترة', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black45)))),
              for (final r in _exps)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
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
            ]),
          ),
        ),
      ]),
    );
  }
}

class _AddExpense extends StatefulWidget {
  const _AddExpense();
  @override
  State<_AddExpense> createState() => _AddExpenseState();
}

class _AddExpenseState extends State<_AddExpense> {
  DateTime _date = DateTime.now();
  String _cat = kCats.first;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String _err = '';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = double.tryParse(_amount.text.trim());
    if (a == null || a < 0) {
      setState(() => _err = 'اكتب المبلغ');
      return;
    }
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      await Api.I.post('add_expense', {'expense_date': ymd(_date), 'category': _cat, 'amount': a, 'note': _note.text.trim()});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _err = errText(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('مصروف جديد', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kPurple)),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(ymd(_date)),
          onPressed: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now(), initialDate: _date);
            if (d != null) setState(() => _date = d);
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _cat,
          items: [for (final c in kCats) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _cat = v ?? _cat),
          decoration: const InputDecoration(labelText: 'النوع'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'المبلغ (ر.ع)'),
        ),
        const SizedBox(height: 10),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
        const SizedBox(height: 8),
        Text(_err, style: const TextStyle(color: kBad, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'لحظة…' : 'احفظ')),
      ]),
    );
  }
}
