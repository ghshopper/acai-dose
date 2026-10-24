import 'package:flutter/material.dart';

import 'api.dart';
import 'orders_controller.dart';
import 'printer.dart';
import 'receipt.dart';
import 'theme.dart';

/// Website orders in three columns: New, Preparing, Ready.
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key, required this.controller});
  final OrdersController controller;

  static const _cols = [
    ['new', 'New'],
    ['preparing', 'Preparing'],
    ['ready', 'Ready for pickup'],
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final wide = MediaQuery.of(context).size.width >= 900;
        final lists = {
          for (final c in _cols) c[0]: controller.orders.where((o) => o['status'] == c[0]).toList(),
        };
        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final c in _cols)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _header(c[1], lists[c[0]]!.length, c[0]),
                      const SizedBox(height: 10),
                      Expanded(
                        child: lists[c[0]]!.isEmpty
                            ? const _Empty()
                            : ListView.separated(
                                itemCount: lists[c[0]]!.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (_, i) => OrderCard(order: lists[c[0]]![i], controller: controller),
                              ),
                      ),
                    ]),
                  ),
                ),
            ]),
          );
        }
        return RefreshIndicator(
          onRefresh: controller.poll,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            for (final c in _cols) ...[
              _header(c[1], lists[c[0]]!.length, c[0]),
              const SizedBox(height: 10),
              if (lists[c[0]]!.isEmpty) const _Empty(),
              for (final o in lists[c[0]]!) ...[OrderCard(order: o, controller: controller), const SizedBox(height: 12)],
              const SizedBox(height: 12),
            ],
          ]),
        );
      },
    );
  }

  Widget _header(String title, int n, String key) {
    final bg = key == 'new' ? kOrange : key == 'ready' ? kOk : kPurple;
    final fg = key == 'new' ? kPurple : Colors.white;
    return Row(children: [
      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kPurple)),
      const SizedBox(width: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text('$n', style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    ]);
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white.withAlpha(140), borderRadius: BorderRadius.circular(16)),
        child: const Text('No orders', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
      );
}

class OrderCard extends StatefulWidget {
  const OrderCard({super.key, required this.order, required this.controller});
  final Map<String, dynamic> order;
  final OrdersController controller;

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  bool _busy = false;

  String _pickup(dynamic v) {
    if (v == null || v == '' || v == 'ASAP') return 'ASAP';
    final p = (v as String).split(':');
    if (p.length != 2) return v;
    final h = int.tryParse(p[0]) ?? 0;
    return '${((h + 11) % 12) + 1}:${p[1]} ${h < 12 ? 'AM' : 'PM'}';
  }

  String _age(dynamic created) {
    final t = DateTime.tryParse('${created ?? ''}'.replaceFirst(' ', 'T'));
    if (t == null) return '';
    final m = DateTime.now().difference(t).inMinutes;
    return m < 1 ? 'just now' : '$m min ago';
  }

  Future<void> _act(String status, {String? payment}) async {
    if (status == 'cancelled') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Cancel this order?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: kBad), onPressed: () => Navigator.pop(c, true), child: const Text('Cancel order')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final wasNew = widget.order['status'] == 'new';
    final snapshot = Map<String, dynamic>.from(widget.order);
    setState(() => _busy = true);
    final err = await widget.controller.setStatus((widget.order['id'] as num).toInt(), status, payment: payment);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    if (wasNew && status == 'preparing') {
      final perr = await ReceiptPrinter.print(ReceiptData.fromOrder(snapshot));
      if (perr != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(perr)));
    }
  }

  Future<void> _print() async {
    final err = await ReceiptPrinter.print(ReceiptData.fromOrder(widget.order));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Receipt printed')));
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final st = o['status'] as String;
    final arrived = OrdersController.isArrived(o);
    final items = (o['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final free = ((o['free_cups'] as num?) ?? 0) > 0;
    final notes = '${o['notes'] ?? ''}'.trim();
    final carDesc = '${o['car_desc'] ?? ''}'.trim();

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: st == 'new' ? kOrange : arrived ? kOk : Colors.transparent, width: 3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('#${o['ref']}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kPurple)),
            const Spacer(),
            Text(_age(o['created_at']), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
            const SizedBox(width: 6),
            IconButton(tooltip: 'Print receipt', onPressed: _print, icon: const Icon(Icons.print, color: kPurple)),
          ]),
          if (arrived) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: kOk, borderRadius: BorderRadius.circular(10)),
              child: const Text('Customer is here', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: kCream, border: Border.all(color: kPurple, width: 2), borderRadius: BorderRadius.circular(10)),
              child: Text('${o['car_plate'] ?? ''}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1, color: kPurple)),
            ),
            const SizedBox(width: 10),
            if (carDesc.isNotEmpty) Expanded(child: Text(carDesc, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          if (o['source'] == 'curb')
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(8)),
              child: Text('CAR ORDER · taken outside${'${o['phone'] ?? ''}'.isNotEmpty ? ' · ${o['phone']}' : ''}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            )
          else ...[
            Text('${o['customer_name'] ?? ''} · ${o['phone'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            Text('Pickup: ${_pickup(o['pickup_time'])}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
          const Divider(height: 18),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${i['qty']}×  ${i['name_en'] ?? i['name_ar'] ?? ''}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          if (notes.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: kCream, borderRadius: BorderRadius.circular(8)),
              child: Text('Note: $notes', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          if (free)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: kOrange, borderRadius: BorderRadius.circular(10)),
              child: Text('Loyalty: 1 cup FREE (−${money(o['discount'])})', style: const TextStyle(color: kPurple, fontWeight: FontWeight.w800)),
            ),
          const SizedBox(height: 8),
          Text('Collect: ${money(o['total'])} OMR', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (_busy) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())) else ..._buttons(st),
        ]),
      ),
    );
  }

  List<Widget> _buttons(String st) {
    if (st == 'new') {
      return [
        FilledButton(style: bigButton(kOrange, kPurple), onPressed: () => _act('preparing'), child: const Text('Accept')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => _act('cancelled'), child: const Text('Cancel')),
      ];
    }
    if (st == 'preparing') {
      return [
        FilledButton(style: bigButton(kPurple, kCream), onPressed: () => _act('ready'), child: const Text('Ready')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => _act('new'), child: const Text('Back')),
      ];
    }
    return [
      Row(children: [
        Expanded(child: FilledButton(style: bigButton(kOk, Colors.white), onPressed: () => _act('done', payment: 'cash'), child: const Text('Paid cash'))),
        const SizedBox(width: 8),
        Expanded(child: FilledButton(style: bigButton(kPurple, kCream), onPressed: () => _act('done', payment: 'card'), child: const Text('Paid card'))),
      ]),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => _act('preparing'), child: const Text('Back')),
    ];
  }
}
