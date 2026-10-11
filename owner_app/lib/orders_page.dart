import 'package:flutter/material.dart';

import 'api.dart';
import 'period.dart';
import 'order_sheet.dart';
import 'stats.dart';
import 'theme.dart';
import 'widgets.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key, required this.period, required this.onLoggedOut});
  final PeriodController period;
  final VoidCallback onLoggedOut;
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = false;
  String _filter = 'all';

  static const _st = kStatusNames;
  static const _pay = kPayNames;

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
      _orders = ((r as Map)['orders'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on ApiError catch (e) {
      if (e.code == 'login_required' || e.code == 'forbidden') {
        widget.onLoggedOut();
        return;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _orders.where((o) {
      if (_filter == 'web') return o['source'] != 'pos';
      if (_filter == 'shop') return o['source'] == 'pos';
      return true;
    }).toList();
    final valid = list.where((o) => o['status'] != 'cancelled').toList();
    final sum = valid.fold(0.0, (s, o) => s + numOf(o['total']));
    return Column(children: [
      PageHead(title: 'الطلبات', period: widget.period),
      if (_loading) const LinearProgressIndicator(minHeight: 3, color: kOrange, backgroundColor: kCream2),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('الكل')),
            ButtonSegment(value: 'web', label: Text('الموقع')),
            ButtonSegment(value: 'shop', label: Text('المحل')),
          ],
          selected: {_filter},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _filter = v.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Row(children: [
          Text('${valid.length} طلب', style: const TextStyle(fontWeight: FontWeight.w900, color: kPurple)),
          const Spacer(),
          Text('${money(sum)} ر.ع', textDirection: TextDirection.rtl, style: const TextStyle(fontWeight: FontWeight.w900, color: kPurple)),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: list.isEmpty
              ? ListView(children: const [EmptyNote('ما فيه طلبات في هالفترة', icon: Icons.receipt_long_outlined)])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _tile(list[i]),
                ),
        ),
      ),
    ]);
  }

  Widget _tile(Map<String, dynamic> o) {
    final cancelled = o['status'] == 'cancelled';
    final web = o['source'] != 'pos';
    final items = ((o['items'] as List?) ?? []).map((e) => '${(e as Map)['qty']}× ${e['name_ar'] ?? e['name_en']}').join('، ');
    final when = '${o['created_at'] ?? ''}';
    final who = web ? '${o['customer_name'] ?? ''}${(o['car_plate'] ?? '') != '' ? ' · ${o['car_plate']}' : ''}' : (o['customer_name'] == 'Imported' ? 'مبيعات مستوردة' : 'المحل');
    return Panel(
      padding: const EdgeInsets.all(14),
      onTap: () async {
        final changed = await openSheet<bool>(context, OrderSheet(order: o));
        if (changed == true) {
          _load();
          if (mounted) toast(context, 'انلغى الطلب');
        }
      },
      child: Opacity(
        opacity: cancelled ? 0.5 : 1,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('#${o['ref']}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: kPurple)),
            const SizedBox(width: 8),
            _chip(web ? 'الموقع' : 'المحل', web ? const Color(0xFFFDE9C8) : kCream2),
            const SizedBox(width: 6),
            _chip(_st[o['status']] ?? '${o['status']}', o['status'] == 'done' ? const Color(0xFFDDF0E3) : cancelled ? const Color(0xFFF6D6D6) : kCream2),
            const Spacer(),
            Text(money(o['total']), textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, decoration: cancelled ? TextDecoration.lineThrough : null)),
          ]),
          const SizedBox(height: 6),
          Text(items, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text(who, style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600))),
            Text(
              '${_pay[o['payment']] ?? (web ? 'ما انستلم' : '')}${numOf(o['commission']) > 0 ? ' · عمولة ${money(o['commission'])}' : ''}  ${when.length >= 16 ? when.substring(5, 16) : ''}',
              style: const TextStyle(color: Colors.black45, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _chip(String t, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
      );
}
