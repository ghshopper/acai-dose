import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// "1.25 كغ", "300 غ" or "12 حبة".
String qfmt(dynamic q, String unit) {
  final v = _n(q);
  if (unit == 'pc') return '${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(1)} حبة';
  if (v.abs() >= 1000) {
    var s = (v / 1000).toStringAsFixed(2);
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return '$s كغ';
  }
  return '${v.round()} غ';
}

/// Cost of each drink, stock with stocktakes, purchases and ingredient prices.
class CostPage extends StatefulWidget {
  const CostPage({super.key});
  @override
  State<CostPage> createState() => _CostPageState();
}

class _CostPageState extends State<CostPage> {
  Map<String, dynamic>? _c;
  Map<String, dynamic>? _st;
  String? _err;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([Api.I.get('costing'), Api.I.get('stock')]);
      setState(() {
        _c = Map<String, dynamic>.from(res[0] as Map);
        _st = Map<String, dynamic>.from(res[1] as Map);
        _err = null;
      });
    } catch (e) {
      setState(() => _err = errText(e));
    }
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic>? m, String k) => ((m?[k] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  List<Map<String, dynamic>> get _ings => _list(_c, 'ingredients');
  Map<int, Map<String, dynamic>> get _ingById => {for (final i in _ings) (i['id'] as num).toInt(): i};

  @override
  Widget build(BuildContext context) {
    final ready = _c != null && _st != null;
    return Scaffold(
      backgroundColor: kBg,
      body: Column(children: [
        PageHead(
          title: 'التكلفة والمخزون',
          trailing: ready
              ? CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  onPressed: _buy,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(CupertinoIcons.cart_badge_plus, color: kPurple, size: 24),
                    SizedBox(width: 4),
                    Text('شراء', style: TextStyle(color: kPurple, fontWeight: FontWeight.w600, fontSize: 17)),
                  ]),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Seg<int>(value: _tab, items: const {0: 'الأكواب', 1: 'المخزون', 2: 'الأسعار'}, onChanged: (v) => setState(() => _tab = v)),
        ),
        Expanded(
          child: !ready
              ? Center(child: _err == null ? const CupertinoActivityIndicator() : Text(_err!))
              : RefreshIndicator.adaptive(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
                    if (_tab == 0) ..._cups(),
                    if (_tab == 1) ..._stock(),
                    if (_tab == 2) ..._prices(),
                  ]),
                ),
        ),
      ]),
    );
  }

  // ---------- cups ----------
  List<Widget> _cups() {
    final noPrice = _ings.where((i) => i['active'] == 1 && _n(i['unit_cost']) == 0).map((i) => '${i['name_ar']}').toList();
    final prods = _list(_c, 'products').where((p) => p['kind'] != 'build' || (p['recipe'] as List).isNotEmpty).toList();
    return [
      if (noPrice.isNotEmpty)
        Panel(
          color: const Color(0xFFFDE9C8),
          child: Text('باقي تحط سعر: ${noPrice.join('، ')}. بدون السعر التكلفة تطلع أقل من الحقيقة.', style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5)),
        ),
      const SizedBox(height: 4),
      for (final p in prods) _cupTile(p),
    ];
  }

  Widget _cupTile(Map<String, dynamic> p) {
    final hasRecipe = (p['recipe'] as List).isNotEmpty;
    final price = _n(p['price']), cost = _n(p['cost']), prof = price - cost;
    final pct = price > 0 ? (prof / price * 100).round() : 0;
    final color = pct >= 60 ? const Color(0xFFDDF0E3) : pct >= 45 ? const Color(0xFFFDE9C8) : const Color(0xFFF6D6D6);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Panel(
        onTap: () => _editRecipe(p),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text('${p['name_ar']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                if (p['active'] != 1) ...[const SizedBox(width: 6), const Pill('مخفي')],
              ]),
              const SizedBox(height: 4),
              Text(hasRecipe ? 'البيع ${money(price)} · التكلفة ${money(cost)} · الربح ${money(prof)}' : 'ما فيه وصفة · اضغط وأضفها',
                  style: const TextStyle(color: kInk2, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (hasRecipe)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: Text('$pct%', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kPurple)),
            ),
          const Icon(CupertinoIcons.forward, color: kInk3),
        ]),
      ),
    );
  }

  Future<void> _editRecipe(Map<String, dynamic> p) async {
    final ok = await openSheet<bool>(context, _RecipeSheet(product: p, ingredients: _ings));
    if (ok == true) {
      _load();
      if (mounted) toast(context, 'انحفظت الوصفة');
    }
  }

  // ---------- stock ----------
  List<Widget> _stock() {
    final rows = _list(_st, 'ingredients');
    final counts = _list(_st, 'counts');
    final counted = counts.isNotEmpty;
    return [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            counted
                ? 'آخر جرد: ${'${counts.first['at']}'.substring(0, 16)}\n«المفروض عندك» = الجرد + اللي اشتريته − اللي انستخدم في الأكواب المباعة.'
                : 'ما سويت جرد للحين. سوّ أول جرد، ومن بعده النظام يحسب اللي المفروض يكون عندك.',
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.6),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _count, icon: const Icon(CupertinoIcons.checkmark_seal, size: 20), label: Text(counted ? 'سوّ جرد جديد' : 'سوّ أول جرد')),
        ]),
      ),
      if (counted) ...[
        const SectionTitle('المفروض عندك الحين', top: 20),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['name_ar']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (r['last_at'] != null)
                      Text('جرد ${qfmt(r['last_qty'], '${r['unit']}')} · اشتريت ${qfmt(r['bought'], '${r['unit']}')} · انستخدم ${qfmt(r['used'], '${r['unit']}')}',
                          style: const TextStyle(fontSize: 11, color: kInk2, fontWeight: FontWeight.w700)),
                  ]),
                ),
                Text(r['expected'] == null ? '-' : qfmt(r['expected'], '${r['unit']}'), style: const TextStyle(fontWeight: FontWeight.w700, color: kPurple, fontSize: 16)),
              ]),
            ),
          ),
      ],
    ];
  }

  Future<void> _count() async {
    final res = await openSheet<List<Map<String, dynamic>>>(context, _CountSheet(rows: _list(_st, 'ingredients')));
    if (res == null) return;
    await _load();
    if (!mounted) return;
    if (res.isEmpty) {
      toast(context, 'انحفظ الجرد، ومن الحين النظام يحسب المخزون');
      return;
    }
    showIos<void>(
      context,
      title: 'الفرق بين الجرد والمفروض',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        for (final r in res)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(child: Text('${r['name_ar']}', textAlign: TextAlign.start, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kInk))),
              Text('${_n(r['diff']) > 0 ? '+' : ''}${qfmt(r['diff'], '${r['unit']}')}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _n(r['diff']) < 0 ? kBad : kOk)),
              const SizedBox(width: 8),
              Text(money(r['value']), textDirection: TextDirection.ltr, style: const TextStyle(color: kInk2, fontSize: 13)),
            ]),
          ),
        const SizedBox(height: 8),
        const Text('بالسالب يعني ناقص عن المفروض: هدر، أو زيادة في الكميات، أو بيع ما انسجل. الفرق البسيط طبيعي.',
            style: TextStyle(color: kInk2, fontSize: 12, height: 1.4)),
      ]),
      actions: const [IosAct('تمام', main: true)],
    );
  }

  // ---------- prices & purchases ----------
  List<Widget> _prices() {
    final pur = _list(_c, 'purchases');
    final byId = _ingById;
    return [
      const SectionTitle('أسعار المكونات', note: 'اضغط للتعديل', top: 8),
      for (final i in _ings)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: const EdgeInsets.all(12),
            onTap: () => _editPrice(i),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i['name_ar']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(_n(i['pack_qty']) > 0 ? '${qfmt(i['pack_qty'], '${i['unit']}')} بـ ${money(i['pack_price'])} ر.ع' : 'ما فيه سعر',
                      style: const TextStyle(fontSize: 12, color: kInk2, fontWeight: FontWeight.w700)),
                ]),
              ),
              Text(
                _n(i['unit_cost']) == 0 ? '-' : (i['unit'] == 'pc' ? '${money(i['unit_cost'])} / حبة' : '${money(_n(i['unit_cost']) * 1000)} / كغ'),
                style: const TextStyle(fontWeight: FontWeight.w700, color: kPurple),
              ),
            ]),
          ),
        ),
      OutlinedButton.icon(onPressed: _addIngredient, icon: const Icon(CupertinoIcons.add), label: const Text('مكوّن جديد')),
      if (pur.isNotEmpty) ...[
        const SectionTitle('آخر المشتريات'),
        for (final p in pur)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${byId[(p['ingredient_id'] as num).toInt()]?['name_ar'] ?? '?'} · ${qfmt(p['qty'], '${byId[(p['ingredient_id'] as num).toInt()]?['unit'] ?? 'g'}')}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${p['date']}${'${p['note']}'.isNotEmpty ? ' · ${p['note']}' : ''}${p['expense'] == true ? ' · في المصاريف' : ''}',
                        style: const TextStyle(fontSize: 11, color: kInk2, fontWeight: FontWeight.w700)),
                  ]),
                ),
                Text(money(p['price']), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
                BarButton(icon: CupertinoIcons.trash, color: kBad, size: 20, onPressed: () => _deletePurchase(p)),
              ]),
            ),
          ),
      ],
    ];
  }

  Future<void> _editPrice(Map<String, dynamic> i) async {
    final q = TextEditingController(text: _n(i['pack_qty']) > 0 ? '${_n(i['pack_qty']).round()}' : '');
    final p = TextEditingController(text: _n(i['pack_price']) > 0 ? money(i['pack_price']) : '');
    final unit = i['unit'] == 'pc' ? 'حبة' : 'غرام';
    final ok = await showIos<bool>(context,
        title: '${i['name_ar']}',
        message: 'اكتب آخر مرة اشتريت: الكمية وبكم',
        body: Column(children: [
          alertField(q, placeholder: 'الكمية ($unit)', keyboard: const TextInputType.numberWithOptions(decimal: true), autofocus: true),
          alertField(p, placeholder: 'المبلغ', suffix: 'ر.ع', keyboard: const TextInputType.numberWithOptions(decimal: true)),
        ]),
        actions: const [IosAct('إلغاء', value: false), IosAct('احفظ', value: true, main: true)]);
    if (ok != true) return;
    try {
      await Api.I.post('ingredient_save', {
        'id': i['id'],
        'name_ar': i['name_ar'],
        'name_en': i['name_en'],
        'unit': i['unit'],
        'pack_qty': double.tryParse(q.text.trim()) ?? 0,
        'pack_price': double.tryParse(p.text.trim()) ?? 0,
      });
      HapticFeedback.mediumImpact();
      _load();
    } catch (e) {
      if (mounted) toast(context, errText(e), ok: false);
    }
  }

  Future<void> _addIngredient() async {
    final n = TextEditingController();
    var unit = 'g';
    final ok = await showIos<bool>(context,
        title: 'مكوّن جديد',
        body: StatefulBuilder(
          builder: (d, set) => Column(children: [
            alertField(n, placeholder: 'الاسم، مثلاً: مانجو', autofocus: true),
            const SizedBox(height: 10),
            Seg<String>(value: unit, items: const {'g': 'بالغرام', 'pc': 'بالحبة'}, onChanged: (v) => set(() => unit = v)),
          ]),
        ),
        actions: const [IosAct('إلغاء', value: false), IosAct('أضف', value: true, main: true)]);
    if (ok != true || n.text.trim().isEmpty) return;
    try {
      await Api.I.post('ingredient_save', {'name_ar': n.text.trim(), 'name_en': n.text.trim(), 'unit': unit});
      _load();
    } catch (e) {
      if (mounted) toast(context, errText(e), ok: false);
    }
  }

  Future<void> _deletePurchase(Map<String, dynamic> p) async {
    final ok = await confirm(context, 'تحذف هذا الشراء؟', message: 'إذا كان مسجل في المصاريف ينحذف منها بعد.', yes: 'احذف');
    if (ok != true) return;
    try {
      await Api.I.post('purchase_delete', {'id': p['id']});
      _load();
    } catch (e) {
      if (mounted) toast(context, errText(e), ok: false);
    }
  }

  Future<void> _buy() async {
    final ok = await openSheet<bool>(context, _BuySheet(ingredients: _ings.where((i) => i['active'] == 1).toList()));
    if (ok == true) {
      _load();
      if (mounted) toast(context, 'انسجل الشراء');
    }
  }
}

// ---------- sheets ----------

class _BuySheet extends StatefulWidget {
  const _BuySheet({required this.ingredients});
  final List<Map<String, dynamic>> ingredients;
  @override
  State<_BuySheet> createState() => _BuySheetState();
}

class _BuySheetState extends State<_BuySheet> {
  late int _ing = (widget.ingredients.first['id'] as num).toInt();
  final _qty = TextEditingController();
  final _price = TextEditingController();
  final _note = TextEditingController();
  bool _expense = true;
  bool _busy = false;
  String _err = '';

  Map<String, dynamic> get _cur => widget.ingredients.firstWhere((i) => (i['id'] as num).toInt() == _ing);

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final q = double.tryParse(_qty.text.trim()), p = double.tryParse(_price.text.trim());
    if (q == null || q <= 0 || p == null || p < 0) {
      setState(() => _err = 'اكتب الكمية والمبلغ');
      return;
    }
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      await Api.I.post('purchase_add', {'date': ymd(DateTime.now()), 'ingredient_id': _ing, 'qty': q, 'price': p, 'note': _note.text.trim(), 'as_expense': _expense});
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
    final pc = _cur['unit'] == 'pc';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetTop('شراء'),
          const SizedBox(height: 14),
          PickField<int>(
            label: 'الصنف',
            value: _ing,
            items: {for (final i in widget.ingredients) (i['id'] as num).toInt(): '${i['name_ar']}'},
            onChanged: (v) => setState(() => _ing = v),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: pc ? 'الكمية (حبة)' : 'الكمية (غرام)', hintText: pc ? '50' : '5000'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ', suffixText: 'ر.ع'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)', hintText: 'مثلاً: المورد')),
          const SizedBox(height: 6),
          const SizedBox(height: 4),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SwitchRow(title: 'سجّلها في المصاريف', value: _expense, onChanged: (v) => setState(() => _expense = v)),
          ),
          const SizedBox(height: 6),
          if (_err.isNotEmpty) Text(_err, style: const TextStyle(color: kBad, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          FilledButton(onPressed: _busy ? null : _save, child: _busy ? const CupertinoActivityIndicator(color: Colors.white) : const Text('احفظ')),
        ]),
      ),
    );
  }
}

class _CountSheet extends StatefulWidget {
  const _CountSheet({required this.rows});
  final List<Map<String, dynamic>> rows;
  @override
  State<_CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends State<_CountSheet> {
  late final Map<int, TextEditingController> _c = {for (final r in widget.rows) (r['id'] as num).toInt(): TextEditingController()};
  bool _busy = false;
  String _err = '';

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final items = [
      for (final e in _c.entries)
        if (e.value.text.trim().isNotEmpty) {'ingredient_id': e.key, 'qty': double.tryParse(e.value.text.trim()) ?? 0}
    ];
    if (items.isEmpty) {
      setState(() => _err = 'اكتب كمية واحدة على الأقل');
      return;
    }
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      final r = Map<String, dynamic>.from(await Api.I.post('stock_count', {'items': items}) as Map);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, ((r['diff'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) {
      setState(() {
        _err = errText(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        maxChildSize: 0.96,
        builder: (context, scroll) => ListView(controller: scroll, padding: EdgeInsets.fromLTRB(18, 12, 18, MediaQuery.of(context).viewInsets.bottom + 30), children: [
          const SheetTop('الجرد'),
          const SizedBox(height: 6),
          const Text('اكتب الموجود عندك الحين: بالغرام، والأكواب والأغطية بالحبة. اللي ما عديته خلّه فاضي.',
              style: TextStyle(color: kInk2, fontWeight: FontWeight.w700, height: 1.5)),
          const SizedBox(height: 12),
          for (final r in widget.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _c[(r['id'] as num).toInt()],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '${r['name_ar']}',
                  suffixText: r['unit'] == 'pc' ? 'حبة' : 'غ',
                  helperText: r['expected'] == null ? null : 'المفروض ${qfmt(r['expected'], '${r['unit']}')}',
                ),
              ),
            ),
          if (_err.isNotEmpty) Text(_err, style: const TextStyle(color: kBad, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _save, child: _busy ? const CupertinoActivityIndicator(color: Colors.white) : const Text('احفظ الجرد')),
        ]),
      );
}

class _RecipeSheet extends StatefulWidget {
  const _RecipeSheet({required this.product, required this.ingredients});
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> ingredients;
  @override
  State<_RecipeSheet> createState() => _RecipeSheetState();
}

class _RecipeSheetState extends State<_RecipeSheet> {
  late final List<_Line> _lines = [
    for (final r in (widget.product['recipe'] as List)) _Line((r['ingredient_id'] as num).toInt(), TextEditingController(text: _fmt(_n(r['qty'])))),
  ];
  bool _busy = false;
  String _err = '';

  static String _fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  Map<String, dynamic>? _ing(int id) {
    for (final i in widget.ingredients) {
      if ((i['id'] as num).toInt() == id) return i;
    }
    return null;
  }

  double get _cost => _lines.fold(0.0, (s, l) => s + (double.tryParse(l.qty.text.trim()) ?? 0) * _n(_ing(l.ing)?['unit_cost']));

  @override
  void dispose() {
    for (final l in _lines) {
      l.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      await Api.I.post('recipe_save', {
        'product_id': widget.product['id'],
        'items': [
          for (final l in _lines)
            if ((double.tryParse(l.qty.text.trim()) ?? 0) > 0) {'ingredient_id': l.ing, 'qty': double.parse(l.qty.text.trim())}
        ],
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
    final price = _n(widget.product['price']), cost = _cost;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.96,
      builder: (context, scroll) => ListView(controller: scroll, padding: EdgeInsets.fromLTRB(18, 12, 18, MediaQuery.of(context).viewInsets.bottom + 30), children: [
        SheetTop('${widget.product['name_ar']}'),
        const SizedBox(height: 10),
        Panel(
          color: kPurple,
          child: Row(children: [
            Expanded(child: Text('التكلفة ${money(cost)}\nالبيع ${money(price)}', style: const TextStyle(color: kCream, fontWeight: FontWeight.w600, height: 1.5))),
            Text(price > 0 ? '${((price - cost) / price * 100).round()}%' : '-', textDirection: TextDirection.ltr, style: const TextStyle(color: kOrange, fontWeight: FontWeight.w700, fontSize: 28)),
          ]),
        ),
        const SizedBox(height: 12),
        for (final l in _lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              CupertinoButton(
                padding: const EdgeInsetsDirectional.only(end: 8),
                minimumSize: const Size(30, 44),
                onPressed: () => setState(() => _lines.remove(l)),
                child: const Icon(CupertinoIcons.minus_circle_fill, color: kBad, size: 24),
              ),
              Expanded(
                flex: 3,
                child: PickField<int>(
                  dense: true,
                  label: 'المكوّن',
                  value: l.ing,
                  items: {for (final i in widget.ingredients) (i['id'] as num).toInt(): '${i['name_ar']}'},
                  onChanged: (v) => setState(() => l.ing = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: l.qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(isDense: true, suffixText: _ing(l.ing)?['unit'] == 'pc' ? 'حبة' : 'غ'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
          ),
        OutlinedButton.icon(
          onPressed: () => setState(() => _lines.add(_Line((widget.ingredients.first['id'] as num).toInt(), TextEditingController()))),
          icon: const Icon(CupertinoIcons.add),
          label: const Text('مكوّن'),
        ),
        if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err, style: const TextStyle(color: kBad, fontWeight: FontWeight.w600))),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _save, child: _busy ? const CupertinoActivityIndicator(color: Colors.white) : const Text('احفظ الوصفة')),
      ]),
    );
  }
}

class _Line {
  _Line(this.ing, this.qty);
  int ing;
  final TextEditingController qty;
}
