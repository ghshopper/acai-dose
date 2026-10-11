import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'printer.dart';
import 'receipt.dart';
import 'theme.dart';

/// In-shop sales: menu grid, current sale, payment buttons and today's sales.
class PosPage extends StatefulWidget {
  const PosPage({super.key, required this.onLoggedOut});
  final VoidCallback onLoggedOut;

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  List<Map<String, dynamic>> _products = [];
  final Map<int, int> _cart = {};
  List<Map<String, dynamic>> _today = [];
  final _given = TextEditingController();
  final _phone = TextEditingController();
  Map<String, dynamic>? _cust;
  bool _useFree = false;
  bool _printIt = false;
  bool _busy = false;
  String _err = '';
  String _menuErr = '';
  Timer? _lookup;

  @override
  void initState() {
    super.initState();
    _loadMenu();
    _loadToday();
    PrintSettings.load().then((c) {
      if (mounted) setState(() => _printIt = c.autoPos);
    });
  }

  @override
  void dispose() {
    _given.dispose();
    _phone.dispose();
    _lookup?.cancel();
    super.dispose();
  }

  Future<void> _loadMenu() async {
    try {
      final r = await Api.I.get('menu');
      setState(() {
        _products = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _menuErr = '';
      });
    } catch (e) {
      setState(() => _menuErr = 'Could not load the menu. ${errText(e)}');
    }
  }

  Future<void> _loadToday() async {
    try {
      final r = await Api.I.get('pos_today');
      if (!mounted) return;
      setState(() => _today = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } on ApiError catch (e) {
      if (e.code == 'login_required') widget.onLoggedOut();
    }
  }

  double _price(Map<String, dynamic> p) => (p['price'] as num).toDouble();
  int _id(Map<String, dynamic> p) => (p['id'] as num).toInt();

  double get _subtotal => _products.fold(0.0, (s, p) => s + (_cart[_id(p)] ?? 0) * _price(p));
  bool get _freeOn => _useFree && _cust != null && ((_cust!['free'] as num?) ?? 0) > 0;
  double get _discount {
    if (!_freeOn) return 0;
    final inCart = _products.where((p) => (_cart[_id(p)] ?? 0) > 0).map(_price).toList();
    return inCart.isEmpty ? 0 : inCart.reduce((a, b) => a > b ? a : b);
  }

  double get _total => (_subtotal - _discount).clamp(0, double.infinity).toDouble();

  void _add(int id, int d) {
    setState(() {
      final q = (_cart[id] ?? 0) + d;
      if (q > 0) {
        _cart[id] = q;
      } else {
        _cart.remove(id);
      }
    });
  }

  void _reset() {
    setState(() {
      _cart.clear();
      _given.clear();
      _phone.clear();
      _cust = null;
      _useFree = false;
      _err = '';
    });
    PrintSettings.load().then((c) {
      if (mounted) setState(() => _printIt = c.autoPos);
    });
  }

  void _phoneChanged(String v) {
    _lookup?.cancel();
    setState(() {
      _cust = null;
      _useFree = false;
    });
    if (!RegExp(r'^[279]\d{7}$').hasMatch(v)) return;
    _lookup = Timer(const Duration(milliseconds: 250), () async {
      try {
        final r = await Api.I.get('pos_customer', {'phone': '+968$v'});
        if (mounted && _phone.text == v) setState(() => _cust = Map<String, dynamic>.from(r as Map));
      } catch (_) {}
    });
  }

  Future<void> _sell(String payment) async {
    final ph = _phone.text;
    if (ph.isNotEmpty && !RegExp(r'^[279]\d{7}$').hasMatch(ph)) {
      setState(() => _err = 'Customer mobile must be 8 digits (or leave it empty)');
      return;
    }
    final shop = payment == 'cash' || payment == 'card';
    final items = _cart.entries.map((e) => {'product_id': e.key, 'qty': e.value}).toList();
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      final r = Map<String, dynamic>.from(await Api.I.post('pos_sale', {
        'items': items,
        'payment': payment,
        'phone': ph.isNotEmpty && shop ? '+968$ph' : '',
        'use_free': shop && _freeOn,
      }) as Map);
      final loy = r['loyalty'] is Map ? Map<String, dynamic>.from(r['loyalty'] as Map) : null;
      final receipt = ReceiptData(
        ref: '${r['ref']}',
        time: DateTime.now(),
        source: 'pos',
        items: [
          for (final p in _products)
            if ((_cart[_id(p)] ?? 0) > 0)
              ReceiptItem(qty: _cart[_id(p)]!, nameEn: '${p['name_en'] ?? ''}', nameAr: '${p['name_ar'] ?? ''}', price: _price(p)),
        ],
        total: ((r['total'] as num?) ?? _total).toDouble(),
        discount: ((r['free_cups'] as num?) ?? 0) > 0 ? _discount : 0,
        payment: payment,
        stamps: loy != null ? '${loy['stamps']}/${loy['need']}' : '',
      );
      final printIt = _printIt;
      _reset();
      if (printIt) {
        ReceiptPrinter.print(receipt).then((perr) {
          if (perr != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(perr)));
        });
      }
      if (!mounted) return;
      var msg = 'Sale #${r['ref']} saved · ${money(r['total'])} OMR ($payment)';
      if (loy != null) msg += ' · Stamps ${loy['stamps']}/${loy['need']}${((loy['free'] as num?) ?? 0) > 0 ? ' · FREE cup ready' : ''}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: kOk, content: Text(msg, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))));
      _loadToday();
    } on ApiError catch (e) {
      if (e.code == 'login_required') {
        widget.onLoggedOut();
        return;
      }
      setState(() => _err = errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _void(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Void sale #${r['ref']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: kBad), onPressed: () => Navigator.pop(c, true), child: const Text('Void')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.post('pos_void', {'id': (r['id'] as num).toInt()});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errText(e))));
    }
    _loadToday();
  }

  Future<void> _reprint(Map<String, dynamic> r) async {
    final err = await ReceiptPrinter.print(ReceiptData.fromOrder(r));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Receipt printed')));
  }

  // ---------- widgets ----------

  Widget _grid(bool wide) {
    if (_menuErr.isNotEmpty) {
      return Padding(padding: const EdgeInsets.all(20), child: Column(children: [Text(_menuErr), const SizedBox(height: 10), FilledButton(onPressed: _loadMenu, child: const Text('Retry'))]));
    }
    if (_products.isEmpty) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
    return GridView.count(
      crossAxisCount: wide ? 3 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.95,
      children: [
        for (final p in _products)
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _add(_id(p), 1),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(children: [
                  Expanded(
                    child: Stack(clipBehavior: Clip.none, children: [
                      Center(
                        child: Image.network('$kSite/assets/${p['img'] ?? 'cup-smoothie.png'}',
                            fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.local_drink, size: 64, color: kPurple)),
                      ),
                      if ((_cart[_id(p)] ?? 0) > 0)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: kOrange,
                            child: Text('${_cart[_id(p)]}', style: const TextStyle(color: kPurple, fontWeight: FontWeight.w900, fontSize: 16)),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Text('${p['name_en']}', textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(money(p['price']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: kPurple)),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _ticket() {
    final rows = _products.where((p) => (_cart[_id(p)] ?? 0) > 0).toList();
    final given = double.tryParse(_given.text);
    final t = _total;
    final can = t > 0 && !_busy;
    final cust = _cust;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Text('Current sale', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(onPressed: _reset, child: const Text('Clear')),
          ]),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Tap a drink to add it', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700))),
          for (final p in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text('${p['name_en']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton.outlined(onPressed: () => _add(_id(p), -1), icon: const Icon(Icons.remove)),
                SizedBox(width: 30, child: Text('${_cart[_id(p)]}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                IconButton.outlined(onPressed: () => _add(_id(p), 1), icon: const Icon(Icons.add)),
                SizedBox(width: 70, child: Text(money((_cart[_id(p)] ?? 0) * _price(p)), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ),
          const Divider(height: 20),
          Row(children: [
            const Text('Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const Spacer(),
            Text('${money(t)} OMR', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 30)),
          ]),
          if (_discount > 0) Text('−${money(_discount)} free cup', textAlign: TextAlign.right, style: const TextStyle(color: kOk, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kCream, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                decoration: const InputDecoration(labelText: 'Customer mobile (optional, loyalty)', hintText: '9XXXXXXX', prefixText: '+968 '),
                onChanged: _phoneChanged,
              ),
              if (cust != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${cust['found'] == true ? (('${cust['name'] ?? ''}').isEmpty ? 'Customer' : cust['name']) : 'New customer'} · Stamps ${cust['stamps']}/${cust['need']}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                if (((cust['free'] as num?) ?? 0) > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(color: kOrange, borderRadius: BorderRadius.circular(10)),
                    child: CheckboxListTile(
                      value: _useFree,
                      onChanged: (v) => setState(() => _useFree = v ?? false),
                      title: Text('Use FREE cup (${cust['free']} available)', style: const TextStyle(fontWeight: FontWeight.w800, color: kPurple)),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  )
                else
                  const Text('Stamps are added for Cash / Card', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            SizedBox(
              width: 160,
              child: TextField(
                controller: _given,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cash given'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            if (given != null && t > 0)
              Expanded(
                child: Text(given >= t ? 'Change: ${money(given - t)}' : 'Short: ${money(t - given)}',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: given >= t ? kOk : kBad)),
              ),
          ]),
          CheckboxListTile(
            value: _printIt,
            onChanged: (v) => setState(() => _printIt = v ?? false),
            title: const Text('Print receipt', style: TextStyle(fontWeight: FontWeight.w800)),
            secondary: const Icon(Icons.print, color: kPurple),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          const Text('In-shop payment', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: FilledButton(style: bigButton(kPurple, kCream), onPressed: can ? () => _sell('cash') : null, child: const Text('Cash'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(style: bigButton(kOrange, kPurple), onPressed: can ? () => _sell('card') : null, child: const Text('Card'))),
          ]),
          const SizedBox(height: 12),
          const Text('Delivery app order', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54)),
          const SizedBox(height: 6),
          Row(children: [
            for (final a in const [['talabat', 'Talabat'], ['snoonu', 'Snoonu'], ['khedmah', 'Khedmah']]) ...[
              Expanded(child: OutlinedButton(onPressed: can ? () => _sell(a[0]) : null, child: Text(a[1]))),
              if (a[0] != 'khedmah') const SizedBox(width: 8),
            ],
          ]),
          if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err, style: const TextStyle(color: kBad, fontWeight: FontWeight.w800))),
        ]),
      ),
    );
  }

  Widget _todayList() {
    final ok = _today.where((r) => r['status'] != 'cancelled').toList();
    double sum([String? k]) => ok.where((r) => k == null || r['payment'] == k).fold(0.0, (s, r) => s + (r['total'] as num).toDouble());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 18),
      const Text("Today's shop sales", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      Text('${ok.length} sales · Total ${money(sum())} · Cash ${money(sum('cash'))} · Card ${money(sum('card'))}',
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
      const SizedBox(height: 8),
      if (_today.isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No shop sales yet today', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)))),
      for (final r in _today)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              '#${r['ref']} · ${money(r['total'])} · ${r['payment'] ?? ''}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                decoration: r['status'] == 'cancelled' ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Text(
              '${'${r['created_at'] ?? ''}'.length >= 16 ? '${r['created_at']}'.substring(11, 16) : ''}  '
              '${((r['items'] as List?) ?? []).map((i) => '${i['qty']}× ${i['name_en']}').join(', ')}'
              '${((r['free_cups'] as num?) ?? 0) > 0 ? ' (1 free)' : ''} · ${r['by_user'] ?? ''}',
            ),
            trailing: r['status'] == 'cancelled'
                ? const Text('Voided', style: TextStyle(color: kBad, fontWeight: FontWeight.w800))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Print receipt', onPressed: () => _reprint(r), icon: const Icon(Icons.print, color: kPurple)),
                    TextButton(onPressed: () => _void(r), child: const Text('Void', style: TextStyle(color: kBad, fontWeight: FontWeight.w800))),
                  ]),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadToday,
            child: ListView(padding: const EdgeInsets.all(14), children: [_grid(true), _todayList()]),
          ),
        ),
        SizedBox(width: 430, child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(0, 14, 14, 14), child: _ticket())),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _loadToday,
      child: ListView(padding: const EdgeInsets.all(12), children: [_grid(false), const SizedBox(height: 12), _ticket(), _todayList()]),
    );
  }
}
