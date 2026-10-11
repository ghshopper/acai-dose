import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

const List<String> kCats = ['مواد خام (آساي وفواكه)', 'أكواب وتغليف', 'رواتب', 'إيجار', 'كهرباء وماء', 'تسويق وإعلانات', 'صيانة', 'أخرى'];
const Map<String, String> kChannelNames = {'talabat': 'طلبات', 'snoonu': 'سنونو', 'khedmah': 'خدمة'};

/// Shared layout for the small "add something" sheets.
class _FormSheet extends StatelessWidget {
  const _FormSheet({required this.title, required this.children, required this.busy, required this.err, required this.onSave, this.saveText = 'احفظ'});
  final String title;
  final List<Widget> children;
  final bool busy;
  final String err;
  final VoidCallback onSave;
  final String saveText;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetTop(title),
            const SizedBox(height: 16),
            ...children,
            if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err, style: const TextStyle(color: kBad, fontWeight: FontWeight.w800))),
            const SizedBox(height: 16),
            FilledButton(onPressed: busy ? null : onSave, child: Text(busy ? 'لحظة…' : saveText)),
          ]),
        ),
      );
}

Widget _gap() => const SizedBox(height: 10);

/// New expense.
class AddExpenseSheet extends StatefulWidget {
  const AddExpenseSheet({super.key});
  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
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
    if (a == null || a <= 0) {
      setState(() => _err = 'اكتب المبلغ');
      return;
    }
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      await Api.I.post('add_expense', {'expense_date': ymd(_date), 'category': _cat, 'amount': a, 'note': _note.text.trim()});
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _err = errText(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
        title: 'مصروف جديد',
        busy: _busy,
        err: _err,
        onSave: _save,
        children: [
          _DateButton(date: _date, onPick: (d) => setState(() => _date = d)),
          _gap(),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in kCats)
              ChoiceChip(
                label: Text(c),
                selected: _cat == c,
                showCheckmark: false,
                selectedColor: kPurple,
                backgroundColor: Colors.white,
                side: BorderSide.none,
                labelStyle: TextStyle(color: _cat == c ? kCream : kPurple, fontWeight: FontWeight.w800, fontSize: 13),
                onSelected: (_) => setState(() => _cat = c),
              ),
          ]),
          _gap(),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            decoration: const InputDecoration(labelText: 'المبلغ', suffixText: 'ر.ع'),
          ),
          _gap(),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
        ],
      );
}

/// Sales typed in by hand from Talabat / Snoonu / Khedmah statements.
class AppSaleSheet extends StatefulWidget {
  const AppSaleSheet({super.key});
  @override
  State<AppSaleSheet> createState() => _AppSaleSheetState();
}

class _AppSaleSheetState extends State<AppSaleSheet> {
  DateTime _date = DateTime.now();
  String _ch = 'talabat';
  Map<String, double> _pcts = {};
  final _gross = TextEditingController();
  final _pct = TextEditingController();
  final _count = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String _err = '';

  @override
  void initState() {
    super.initState();
    Api.I.get('settings').then((r) {
      final c = (r as Map)['commissions'];
      if (c is Map && mounted) {
        setState(() {
          _pcts = {for (final e in c.entries) '${e.key}': ((e.value as num?) ?? 0).toDouble()};
          _pct.text = _fmtPct(_pcts[_ch]);
        });
      }
    }).catchError((_) {});
  }

  String _fmtPct(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void dispose() {
    _gross.dispose();
    _pct.dispose();
    _count.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final g = double.tryParse(_gross.text.trim());
    final p = double.tryParse(_pct.text.trim().isEmpty ? '0' : _pct.text.trim());
    if (g == null || g <= 0) {
      setState(() => _err = 'اكتب مبلغ المبيعات');
      return;
    }
    if (p == null || p < 0 || p > 100) {
      setState(() => _err = 'نسبة العمولة بين 0 و 100');
      return;
    }
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      await Api.I.post('add_sale', {
        'sale_date': ymd(_date),
        'channel': _ch,
        'gross': g,
        'commission_pct': p,
        'orders_count': int.tryParse(_count.text.trim()),
        'note': _note.text.trim(),
      });
      HapticFeedback.mediumImpact();
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
    final g = double.tryParse(_gross.text.trim()) ?? 0;
    final p = double.tryParse(_pct.text.trim()) ?? 0;
    return _FormSheet(
      title: 'مبيعات التطبيقات',
      busy: _busy,
      err: _err,
      onSave: _save,
      children: [
        const Text('من كشف طلبات أو سنونو أو خدمة، لليوم كامل', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
        _gap(),
        SegmentedButton<String>(
          segments: [for (final e in kChannelNames.entries) ButtonSegment(value: e.key, label: Text(e.value))],
          selected: {_ch},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() {
            _ch = v.first;
            _pct.text = _fmtPct(_pcts[_ch]);
          }),
        ),
        _gap(),
        _DateButton(date: _date, onPick: (d) => setState(() => _date = d)),
        _gap(),
        TextField(
          controller: _gross,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          decoration: const InputDecoration(labelText: 'المبيعات', suffixText: 'ر.ع'),
          onChanged: (_) => setState(() {}),
        ),
        _gap(),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _pct,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'العمولة', suffixText: '%'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'عدد الطلبات'),
            ),
          ),
        ]),
        if (g > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Panel(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Text('يوصلك تقريباً', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54)),
                const Spacer(),
                Text('${money(g - g * p / 100)} ر.ع', textDirection: TextDirection.rtl, style: const TextStyle(fontWeight: FontWeight.w900, color: kPurple, fontSize: 17)),
              ]),
            ),
          ),
        _gap(),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
      ],
    );
  }
}

/// New customer by mobile number: they get a loyalty card straight away.
class AddCustomerSheet extends StatefulWidget {
  const AddCustomerSheet({super.key});
  @override
  State<AddCustomerSheet> createState() => _AddCustomerSheetState();
}

class _AddCustomerSheetState extends State<AddCustomerSheet> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  bool _offers = true;
  bool _busy = false;
  String _err = '';

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!RegExp(r'^[279]\d{7}$').hasMatch(_phone.text.trim())) {
      setState(() => _err = 'الرقم لازم ٨ أرقام');
      return;
    }
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      await Api.I.post('customer_add', {'phone': '+968${_phone.text.trim()}', 'name': _name.text.trim(), 'offers': _offers});
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _err = errText(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
        title: 'عميل جديد',
        busy: _busy,
        err: _err,
        onSave: _save,
        saveText: 'أضف العميل',
        children: [
          TextField(
            controller: _phone,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1),
            decoration: const InputDecoration(labelText: 'رقم الجوال', hintText: '9XXXXXXX', prefixText: '+968  '),
          ),
          _gap(),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم (اختياري)')),
          _gap(),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: SwitchListTile(
              value: _offers,
              onChanged: (v) => setState(() => _offers = v),
              title: const Text('يبي يوصله العروض', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      );
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.date, required this.onPick});
  final DateTime date;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = date.year == now.year && date.month == now.month && date.day == now.day;
    return OutlinedButton.icon(
      icon: const Icon(Icons.event),
      label: Text(today ? 'اليوم · ${ymd(date)}' : ymd(date)),
      onPressed: () async {
        final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: now, initialDate: date);
        if (d != null) onPick(d);
      },
    );
  }
}
