import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'offline.dart';
import 'theme.dart';

/// Money paid from the till's cash (milk, gas, taxi…): today's list and a button to add one. Works offline.
class TillExpenses extends StatefulWidget {
  const TillExpenses({super.key, required this.cashSales, required this.onLoggedOut});
  final double cashSales;
  final VoidCallback onLoggedOut;

  @override
  State<TillExpenses> createState() => TillExpensesState();
}

class TillExpensesState extends State<TillExpenses> {
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    load();
    Outbox.I.addListener(_changed);
    Outbox.I.listen(load);
  }

  @override
  void dispose() {
    Outbox.I.removeListener(_changed);
    Outbox.I.unlisten(load);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    try {
      final r = await Api.I.get('pos_expenses');
      final rows = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await Cache.put('pos_expenses', {'day': stamp(DateTime.now()).substring(0, 10), 'rows': rows});
      if (mounted) setState(() => _rows = rows);
    } on ApiError catch (e) {
      if (e.code == 'login_required') {
        widget.onLoggedOut();
        return;
      }
      final c = await Cache.get('pos_expenses');
      if (c is Map && c['day'] == stamp(DateTime.now()).substring(0, 10) && mounted) {
        setState(() => _rows = ((c['rows'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    }
  }

  String _catName(String k) {
    for (final c in ShopConfig.I.expenseCats) {
      if (c['k'] == k) return '${c['en']}';
    }
    return k;
  }

  List<Map<String, dynamic>> get _pending => Outbox.I.items.where((i) => i['kind'] == 'expense').map((i) => Map<String, dynamic>.from(i['body'] as Map)).toList();

  double get _total => _rows.fold(0.0, (s, r) => s + (r['amount'] as num).toDouble()) + _pending.fold(0.0, (s, r) => s + (r['amount'] as num).toDouble());

  Future<void> _add() async {
    final cats = ShopConfig.I.expenseCats;
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connect to the internet once to load expense types')));
      return;
    }
    String cat = '';
    final amount = TextEditingController();
    final note = TextEditingController();
    String err = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final a = double.tryParse(amount.text) ?? 0;
          return AlertDialog(
            title: const Text('Pay from the till', style: TextStyle(fontWeight: FontWeight.w900)),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('What was it for?', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final x in cats)
                      ChoiceChip(
                        label: Text('${x['en']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        selected: cat == x['k'],
                        showCheckmark: false,
                        selectedColor: kOrange,
                        onSelected: (_) => set(() => cat = '${x['k']}'),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,3})?'))],
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                    decoration: const InputDecoration(labelText: 'Amount', suffixText: 'OMR'),
                    onChanged: (_) => set(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    maxLength: 80,
                    decoration: InputDecoration(labelText: cat == 'other' ? 'What was it? (required)' : 'Note (optional)', hintText: 'e.g. 2 boxes of milk'),
                    onChanged: (_) => set(() {}),
                  ),
                  if (err.isNotEmpty) Text(err, style: const TextStyle(color: kBad, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: cat.isEmpty || a <= 0 || a > 500 || (cat == 'other' && note.text.trim().isEmpty) ? null : () => Navigator.pop(c, true),
                child: Text(a > 0 ? 'Save · ${money(a)}' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final body = {'client_id': newClientId(), 'cat': cat, 'amount': double.parse(amount.text), 'note': note.text.trim()};
    try {
      await Api.I.post('pos_expense', body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: kOk, content: Text('Expense saved · ${_catName(cat)} · ${money(body['amount'])} OMR')));
      load();
    } on ApiError catch (e) {
      if (e.code == 'login_required') {
        widget.onLoggedOut();
        return;
      }
      if (e.code == 'network') {
        await Outbox.I.add('expense', {...body, 'at': stamp(DateTime.now())}, '${_catName(cat)} ${money(body['amount'])}');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: kOrange, content: Text('No internet: expense saved on this device, it will be sent automatically', style: const TextStyle(color: kPurple, fontWeight: FontWeight.w800))));
        setState(() {});
        return;
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errText(e))));
    }
  }

  Future<void> _remove(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${r['cat']} · ${money(r['amount'])}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: kBad), onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.post('pos_expense_void', {'id': (r['id'] as num).toInt()});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errText(e))));
    }
    load();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final drawer = widget.cashSales - _total;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 18),
      Row(children: [
        const Expanded(child: Text('Till expenses today', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: kPurple, foregroundColor: kCream), onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add expense')),
      ]),
      Text('Paid ${money(_total)} · Cash in drawer should be ${money(drawer)} OMR',
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
      const SizedBox(height: 8),
      if (_rows.isEmpty && pending.isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Nothing paid from the till today', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)))),
      for (final p in pending)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: const Color(0xFFFFF4E0),
          child: ListTile(
            leading: const Icon(Icons.cloud_upload_outlined, color: kOrange),
            title: Text('${_catName('${p['cat']}')} · ${money(p['amount'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${'${p['at'] ?? ''}'.length >= 16 ? '${p['at']}'.substring(11, 16) : ''}  ${p['note'] ?? ''} · waiting for internet'),
          ),
        ),
      for (final r in _rows)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.payments_outlined, color: kPurple),
            title: Text('${r['cat']} · ${money(r['amount'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${'${r['at'] ?? ''}'.length >= 16 ? '${r['at']}'.substring(11, 16) : ''}  ${r['note'] ?? ''}${'${r['note'] ?? ''}'.isEmpty ? '' : ' · '}${r['by_user'] ?? ''}'),
            trailing: TextButton(onPressed: () => _remove(r), child: const Text('Remove', style: TextStyle(color: kBad, fontWeight: FontWeight.w800))),
          ),
        ),
    ]);
  }
}
