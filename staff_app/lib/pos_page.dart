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
  /// Sale lines: key = product id, or "id:t1.t2" for a built bowl with its toppings; value = quantity.
  final Map<String, int> _cart = {};
  List<Map<String, dynamic>> _toppings = [];
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
  /// Custom items typed at the till: sale line key -> price
  final Map<String, double> _customPrice = {};
  String _cat = ''; // menu section shown on the till ('' = first section, or everything when the shop has none)
  final _search = TextEditingController();

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
    _search.dispose();
    _lookup?.cancel();
    super.dispose();
  }

  Future<void> _loadMenu() async {
    try {
      final r = await Api.I.get('menu');
      List<Map<String, dynamic>> tops = [];
      try {
        tops = ((await Api.I.get('toppings')) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
      setState(() {
        _products = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _toppings = tops;
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

  Map<String, dynamic>? _prod(int id) {
    for (final p in _products) {
      if (_id(p) == id) return p;
    }
    return null;
  }

  int _keyPid(String k) => int.parse(k.split(':').first);
  List<int> _keyTops(String k) {
    final parts = k.split(':');
    if (parts.length < 2 || parts[1].isEmpty) return [];
    return parts[1].split('.').map(int.parse).toList();
  }

  /// Kitchen note on a line ("Less sugar"), kept as the third part of the key: id:toppings:note
  String _keyNote(String k) {
    final parts = k.split(':');
    return parts.length > 2 ? parts.sublist(2).join(':') : '';
  }

  List<Map<String, dynamic>> get _items => _cart.entries.map((e) {
        final custom = _customPrice[e.key];
        if (custom != null) return {'product_id': _keyPid(e.key), 'qty': e.value, 'name': _keyNote(e.key), 'price': custom};
        return {'product_id': _keyPid(e.key), 'qty': e.value, 'toppings': _keyTops(e.key), if (_keyNote(e.key).isNotEmpty) 'note': _keyNote(e.key)};
      }).toList();

  Map<String, dynamic>? get _openItem {
    for (final p in _products) {
      if (p['kind'] == 'open') return p;
    }
    return null;
  }

  /// An item that isn't on the menu: staff type its name and price.
  Future<void> _customItem() async {
    final open = _openItem;
    if (open == null) return;
    final name = TextEditingController();
    final price = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final v = double.tryParse(price.text.trim()) ?? 0;
          return AlertDialog(
            title: const Text('Custom item'),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Chips, Water bottle')),
                const SizedBox(height: 10),
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  decoration: const InputDecoration(labelText: 'Price (OMR)', hintText: '0.000'),
                  onChanged: (_) => set(() {}),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: v > 0 && v <= 100 ? () => Navigator.pop(c, true) : null, child: Text(v > 0 ? 'Add · ${money(v)}' : 'Add')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(price.text.trim()) ?? 0;
    var n = name.text.trim().replaceAll(':', ' ');
    if (n.isEmpty) n = 'Custom item';
    var key = '${_id(open)}::$n';
    // Same name at another price is its own line
    while (_customPrice.containsKey(key) && _customPrice[key] != v) {
      key = '$key ';
    }
    _customPrice[key] = v;
    _add(key, 1);
  }

  List<Map<String, dynamic>> _topsOf(String k) => [
        for (final id in _keyTops(k))
          for (final t in _toppings)
            if ((t['id'] as num).toInt() == id) t
      ];

  double _unit(String k) {
    final custom = _customPrice[k];
    if (custom != null) return custom;
    final p = _prod(_keyPid(k));
    if (p == null) return 0;
    return _price(p) + _topsOf(k).fold(0.0, (s, t) => s + (t['price'] as num).toDouble());
  }

  String _lineName(String k, {bool ar = false}) {
    final p = _prod(_keyPid(k));
    if (p == null) return '';
    if (_customPrice.containsKey(k)) return _keyNote(k).trim();
    final counts = <int, int>{};
    for (final id in _keyTops(k)) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final tops = [
      for (final e in counts.entries)
        for (final t in _toppings)
          if ((t['id'] as num).toInt() == e.key) '${ar ? t['name_ar'] : t['name_en']}${e.value > 1 ? ' x${e.value}' : ''}'
    ];
    final size = p['size'] == null ? '' : (ar ? '${ShopConfig.I.sizes[p['size']]?['ar'] ?? ''}' : ShopConfig.I.sizeName(p['size'] as String?));
    var base = '${ar ? p['name_ar'] : p['name_en']}${size.isEmpty ? '' : ' ($size)'}';
    if (tops.isNotEmpty) base = '$base (${tops.join(ar ? '، ' : ', ')})';
    final note = _keyNote(k);
    return note.isEmpty ? base : '$base · $note';
  }

  int _qtyOf(int pid) => _cart.entries.where((e) => _keyPid(e.key) == pid).fold<int>(0, (s, e) => s + e.value);

  double get _subtotal => _cart.entries.fold(0.0, (s, e) => s + e.value * _unit(e.key));
  bool get _freeOn => _useFree && _cust != null && ((_cust!['free'] as num?) ?? 0) > 0;
  double get _discount {
    if (!_freeOn || _cart.isEmpty) return 0;
    // The free cup covers the dearest item's base price; toppings stay paid
    return _cart.keys.map((k) => _price(_prod(_keyPid(k)) ?? {'price': 0})).reduce((a, b) => a > b ? a : b);
  }

  double get _total => (_subtotal - _discount).clamp(0, double.infinity).toDouble();

  void _add(String key, int d) {
    setState(() {
      final q = (_cart[key] ?? 0) + d;
      if (q > 0) {
        _cart[key] = q;
      } else {
        _cart.remove(key);
        _customPrice.remove(key);
      }
    });
  }

  /// Build-your-bowl: pick toppings (each up to 3 times), then the bowl goes into the sale.
  Future<void> _buildBowl(Map<String, dynamic> p) async {
    final picked = <int, int>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          var sum = _price(p);
          for (final t in _toppings) {
            sum += (t['price'] as num).toDouble() * (picked[(t['id'] as num).toInt()] ?? 0);
          }
          return AlertDialog(
            title: Text('${p['name_en']}'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final t in _toppings)
                    Builder(builder: (_) {
                      final id = (t['id'] as num).toInt();
                      final n = picked[id] ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: n > 0 ? kOrange.withAlpha(60) : kCream, borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Expanded(child: Text('${t['name_en']}${(t['price'] as num) > 0 ? '  +${money(t['price'])}' : ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                          IconButton(onPressed: n > 0 ? () => set(() => n > 1 ? picked[id] = n - 1 : picked.remove(id)) : null, icon: const Icon(Icons.remove_circle_outline)),
                          SizedBox(width: 26, child: Text('$n', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
                          IconButton(onPressed: n < 3 ? () => set(() => picked[id] = n + 1) : null, icon: const Icon(Icons.add_circle, color: kPurple)),
                        ]),
                      );
                    }),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Add · ${money(sum)} OMR')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final ids = <int>[for (final e in picked.entries) ...List.filled(e.value, e.key)]..sort();
    _add('${_id(p)}:${ids.join('.')}', 1);
  }

  void _reset() {
    setState(() {
      _cart.clear();
      _customPrice.clear();
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
    final items = _items;
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
          for (final e in _cart.entries) ReceiptItem(qty: e.value, nameEn: _lineName(e.key), nameAr: _lineName(e.key, ar: true), price: _unit(e.key)),
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
      final payName = payment == 'cash' ? 'Cash' : payment == 'card' ? 'Card' : ShopConfig.I.channelName(payment);
      var msg = 'Sale #${r['ref']} saved · ${money(r['total'])} OMR ($payName)';
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

  /// Order taken at the car: goes to the orders screen inside, paid when it is handed over.
  Future<void> _sendCurb() async {
    final ph = _phone.text;
    if (ph.isNotEmpty && !RegExp(r'^[279]\d{7}$').hasMatch(ph)) {
      setState(() => _err = 'Customer mobile must be 8 digits (or leave it empty)');
      return;
    }
    final plate = TextEditingController();
    final desc = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Car order'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: plate,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1),
                decoration: const InputDecoration(labelText: 'Car plate', hintText: '12345 A'),
                onChanged: (_) => set(() {}),
              ),
              const SizedBox(height: 8),
              TextField(controller: desc, decoration: const InputDecoration(labelText: 'Car model & colour (optional)', hintText: 'White Land Cruiser')),
              const SizedBox(height: 8),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'No ice')),
              const SizedBox(height: 10),
              Text('${money(_subtotal)} OMR · paid when you hand it over', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: plate.text.trim().isEmpty ? null : () => Navigator.pop(c, true), child: const Text('Send inside')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      final r = Map<String, dynamic>.from(await Api.I.post('curb_order', {
        'items': _items,
        'car_plate': plate.text.trim().toUpperCase(),
        'car_desc': desc.text.trim(),
        'notes': note.text.trim(),
        'phone': ph.isNotEmpty ? '+968$ph' : '',
        'name': _cust != null ? '${_cust!['name'] ?? ''}' : '',
      }) as Map);
      _reset();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: kOk,
        content: Text('Order #${r['ref']} sent inside · car ${plate.text.trim().toUpperCase()} · collect ${money(r['total'])} OMR',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ));
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

  static const _drinkCats = {'karak', 'milk', 'drinks'};
  static const _drinkNotes = ['Less sugar', 'No sugar', 'Extra sugar', 'Extra strong', 'Cold'];
  /// Bought-in drinks get no sugar notes; food gets no notes at all
  static const _noNotes = {'Water', 'Kinza', 'Top Fruit'};

  /// Items on the till: sizes of the same item (Karak Small / Large) share one tile.
  List<List<Map<String, dynamic>>> get _tiles {
    final out = <String, List<Map<String, dynamic>>>{};
    final q = _search.text.trim().toLowerCase();
    for (final p in _products) {
      if (p['kind'] == 'open') continue;
      if (q.isNotEmpty) {
        if (!'${p['name_en']} ${p['name_ar']}'.toLowerCase().contains(q)) continue;
      } else if (_cats.isNotEmpty && p['cat'] != _currentCat) {
        continue;
      }
      out.putIfAbsent('${p['cat'] ?? ''}|${p['name_en']}', () => []).add(p);
    }
    return out.values.toList();
  }

  List<Map<String, dynamic>> get _cats => ShopConfig.I.cats.where((c) => _products.any((p) => p['cat'] == c['k'])).toList();
  String get _currentCat => _cat.isNotEmpty ? _cat : (_cats.isEmpty ? '' : '${_cats.first['k']}');

  /// Size and kitchen note for a tile, then into the sale.
  Future<void> _pick(List<Map<String, dynamic>> variants) async {
    final first = variants.first;
    if (variants.every((v) => v['soldout'] == true)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sold out. Long-press the item to bring it back.')));
      return;
    }
    if (first['kind'] == 'build') {
      await _buildBowl(first);
      return;
    }
    if (!Api.I.shop.isKarak) {
      _add('${_id(first)}', 1);
      return;
    }
    var size = variants.firstWhere((v) => v['soldout'] != true);
    String note = '';
    final notes = _drinkCats.contains(first['cat']) && !_noNotes.contains(first['name_en']) ? _drinkNotes : const <String>[];
    if (variants.length == 1 && notes.isEmpty) {
      _add('${_id(size)}', 1);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('${first['name_en']}', style: const TextStyle(fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (variants.length > 1) ...[
                Row(children: [
                  for (final (i, v) in variants.indexed) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: bigButton(identical(v, size) ? kPurple : Colors.white, identical(v, size) ? kCream : kPurple)
                            .copyWith(minimumSize: const WidgetStatePropertyAll(Size(64, 74))),
                        onPressed: v['soldout'] == true ? null : () => set(() => size = v),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(ShopConfig.I.sizeName(v['size'] as String?)),
                          Text(v['soldout'] == true ? 'Sold out' : money(v['price']), style: const TextStyle(fontSize: 15)),
                        ]),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 14),
              ],
              if (notes.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: [
                for (final n in notes)
                  ChoiceChip(
                    label: Text(n, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    selected: note == n,
                    onSelected: (on) => set(() => note = on ? n : ''),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Add · ${money(size['price'])}')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    _add(note.isEmpty ? '${_id(size)}' : '${_id(size)}::$note', 1);
  }

  /// Staff mark an item as run out (it disappears from the order page) or back in stock.
  Future<void> _toggleSoldOut(List<Map<String, dynamic>> variants) async {
    final out = variants.every((v) => v['soldout'] == true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(out ? '${variants.first['name_en']} is back?' : '${variants.first['name_en']} sold out?'),
        content: Text(out ? 'It shows again on the till and the order page.' : 'It is hidden from the order page and greyed out here until you bring it back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: out ? kOk : kBad), onPressed: () => Navigator.pop(c, true), child: Text(out ? 'Back in stock' : 'Sold out')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      for (final v in variants) {
        await Api.I.post('soldout', {'id': _id(v), 'soldout': !out});
      }
      await _loadMenu();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errText(e))));
    }
  }

  String _priceLabel(List<Map<String, dynamic>> vs) => vs.map((v) => money(v['price'])).toSet().join(' / ');

  Widget _grid(bool wide) {
    if (_menuErr.isNotEmpty) {
      return Padding(padding: const EdgeInsets.all(20), child: Column(children: [Text(_menuErr), const SizedBox(height: 10), FilledButton(onPressed: _loadMenu, child: const Text('Retry'))]));
    }
    if (_products.isEmpty) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
    final karak = Api.I.shop.isKarak;
    final tiles = _tiles;
    final cats = _cats;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (karak) ...[
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'Search the menu',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
      ],
      if (cats.isNotEmpty && _search.text.trim().isEmpty) ...[
        SizedBox(
          height: 50,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final c in cats)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${c['en']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  selected: _currentCat == c['k'],
                  showCheckmark: false,
                  selectedColor: kOrange,
                  onSelected: (_) => setState(() => _cat = '${c['k']}'),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      if (_openItem != null) ...[
        OutlinedButton.icon(onPressed: _customItem, icon: const Icon(Icons.edit_note), label: const Text('Custom item (type name and price)')),
        const SizedBox(height: 10),
      ],
      if (tiles.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nothing matches', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700))),
      GridView.count(
        crossAxisCount: karak ? (wide ? 4 : 2) : (wide ? 3 : 2),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: karak ? 1.45 : 0.95,
        children: [
          for (final vs in tiles)
            Builder(builder: (_) {
              final p = vs.first;
              final out = vs.every((v) => v['soldout'] == true);
              final n = vs.fold<int>(0, (s, v) => s + _qtyOf(_id(v)));
              final img = '${p['img'] ?? ''}';
              return Material(
                color: out ? const Color(0xFFE6E0E4) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _pick(vs),
                  onLongPress: karak ? () => _toggleSoldOut(vs) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Stack(clipBehavior: Clip.none, children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (img.isNotEmpty || !karak)
                          Expanded(
                            child: Center(
                              child: Image.network('$kSite/assets/${img.isEmpty ? 'cup-smoothie.png' : img}',
                                  fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.local_drink, size: 64, color: kPurple)),
                            ),
                          )
                        else
                          const Spacer(),
                        const SizedBox(height: 6),
                        Text('${p['name_en']}',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: karak ? 17 : 15, decoration: out ? TextDecoration.lineThrough : null)),
                        if (karak) Text('${p['name_ar']}', textAlign: TextAlign.center, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54)),
                        Text(out ? 'SOLD OUT' : _priceLabel(vs),
                            textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: out ? kBad : kPurple)),
                        if (karak) const Spacer(),
                      ]),
                      if (n > 0)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: kOrange,
                            child: Text('$n', style: const TextStyle(color: kPurple, fontWeight: FontWeight.w900, fontSize: 16)),
                          ),
                        ),
                    ]),
                  ),
                ),
              );
            }),
        ],
      ),
    ]);
  }

  Widget _ticket() {
    final rows = _cart.keys.toList();
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
          for (final k in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(_lineName(k), style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton.outlined(onPressed: () => _add(k, -1), icon: const Icon(Icons.remove)),
                SizedBox(width: 30, child: Text('${_cart[k]}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                IconButton.outlined(onPressed: () => _add(k, 1), icon: const Icon(Icons.add)),
                SizedBox(width: 70, child: Text(money((_cart[k] ?? 0) * _unit(k)), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
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
          const Text('Car order · pay on hand-over', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54)),
          const SizedBox(height: 6),
          FilledButton.icon(
            style: bigButton(kOk, Colors.white),
            onPressed: can ? _sendCurb : null,
            icon: const Icon(Icons.directions_car),
            label: const Text('Send to inside'),
          ),
          const SizedBox(height: 12),
          const Text('Delivery app order', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54)),
          const SizedBox(height: 6),
          Row(children: [
            for (final (i, a) in ShopConfig.I.channels.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: can ? () => _sell('${a['k']}') : null, child: FittedBox(child: Text('${a['en']}')))),
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
