import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'theme.dart';
import 'whatsapp.dart';

/// Two tabs: orders in progress (live) and today's handed-over orders.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.me, required this.onLogout});
  final Map<String, dynamic> me;
  final VoidCallback onLogout;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _done = [];
  bool _online = true;
  bool _first = true;
  int _tab = 0;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _poll();
  }

  List<Map<String, dynamic>> _list(dynamic r) => (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final res = await Future.wait([Api.I.get('active_orders'), Api.I.get('web_today')]);
      final active = _list(res[0]);
      final before = _active.where((o) => o['status'] == 'new').map((o) => o['id']).toSet();
      if (!_first && active.any((o) => o['status'] == 'new' && !before.contains(o['id']))) HapticFeedback.heavyImpact();
      _active = active;
      _done = _list(res[1]);
      _online = true;
      _first = false;
    } on ApiError catch (e) {
      _online = false;
      if (e.code == 'login_required') {
        widget.onLogout();
        return;
      }
    } finally {
      _busy = false;
    }
    if (mounted) setState(() {});
  }

  static int _rank(Map<String, dynamic> o) {
    final arrived = '${o['arrived_at'] ?? ''}'.isNotEmpty;
    if (arrived && o['status'] != 'new') return 0;
    switch (o['status']) {
      case 'new':
        return 1;
      case 'ready':
        return 2;
      default:
        return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = [..._active]..sort((a, b) {
        final r = _rank(a).compareTo(_rank(b));
        return r != 0 ? r : ((a['id'] as num).compareTo(b['id'] as num));
      });
    final newCount = _active.where((o) => o['status'] == 'new').length;
    final doneOk = _done.where((o) => o['status'] == 'done').toList();
    final doneSum = doneOk.fold(0.0, (s, o) => s + ((o['total'] as num?) ?? 0).toDouble());

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Row(children: [
          Image.asset('assets/logo-cream.png', height: 30),
          const SizedBox(width: 10),
          Icon(Icons.circle, size: 11, color: _online ? const Color(0xFF7BD389) : const Color(0xFFE06C6C)),
        ]),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _poll, icon: const Icon(Icons.refresh)),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text('Log out ${widget.me['username'] ?? ''}?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Log out')),
                  ],
                ),
              );
              if (ok == true) widget.onLogout();
            },
          ),
        ],
      ),
      body: _first
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _poll,
              child: _tab == 0
                  ? (active.isEmpty
                      ? ListView(children: const [_Empty('No orders right now', Icons.local_drink_outlined)])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
                          itemCount: active.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => OrderCard(key: ValueKey(active[i]['id']), order: active[i], onChanged: _poll),
                        ))
                  : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 30), children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(18)),
                        child: Row(children: [
                          Text('${doneOk.length} handed over today', style: const TextStyle(color: kCream, fontWeight: FontWeight.w800, fontSize: 16)),
                          const Spacer(),
                          Text('${money(doneSum)} OMR', style: const TextStyle(color: kCream, fontWeight: FontWeight.w900, fontSize: 18)),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      if (_done.isEmpty) const _Empty('Nothing handed over yet today', Icons.check_circle_outline),
                      for (final o in _done) Padding(padding: const EdgeInsets.only(bottom: 8), child: _DoneTile(order: o)),
                    ]),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: kOrange.withAlpha(80),
        destinations: [
          NavigationDestination(
            icon: Badge(isLabelVisible: newCount > 0, label: Text('$newCount'), child: const Icon(Icons.receipt_long_outlined)),
            selectedIcon: Badge(isLabelVisible: newCount > 0, label: Text('$newCount'), child: const Icon(Icons.receipt_long)),
            label: 'Orders (${_active.length})',
          ),
          NavigationDestination(icon: const Icon(Icons.check_circle_outline), selectedIcon: const Icon(Icons.check_circle), label: 'Done today (${doneOk.length})'),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text, this.icon);
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(children: [
          Icon(icon, size: 56, color: Colors.black26),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black45, fontSize: 16)),
        ]),
      );
}

String _pickup(dynamic v) {
  if (v == null || v == '' || v == 'ASAP') return 'ASAP';
  final p = '$v'.split(':');
  if (p.length != 2) return '$v';
  final h = int.tryParse(p[0]) ?? 0;
  return '${((h + 11) % 12) + 1}:${p[1]} ${h < 12 ? 'AM' : 'PM'}';
}

String _age(dynamic created) {
  final t = DateTime.tryParse('${created ?? ''}'.replaceFirst(' ', 'T'));
  if (t == null) return '';
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${m % 60} min';
}

/// One live order with contact and status buttons.
class OrderCard extends StatefulWidget {
  const OrderCard({super.key, required this.order, required this.onChanged});
  final Map<String, dynamic> order;
  final Future<void> Function() onChanged;
  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  bool _busy = false;

  static const _labels = {'new': 'NEW', 'preparing': 'PREPARING', 'ready': 'READY'};

  Future<void> _set(String status, {String? payment}) async {
    final o = widget.order;
    if (status == 'cancelled') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Cancel order #${o['ref']}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: kBad), onPressed: () => Navigator.pop(c, true), child: const Text('Cancel order')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{'id': o['id'], 'status': status};
      if (payment != null) body['payment'] = payment;
      await Api.I.post('order_status', body);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final phone = '${o['phone'] ?? ''}';
      if (status == 'ready' && phone.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('#${o['ref']} is ready'),
          action: SnackBarAction(label: 'Send WhatsApp', onPressed: () => openWhatsApp(phone, waText('ready', o))),
        ));
      }
      await widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: kBad, content: Text(errText(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final st = '${o['status']}';
    final arrived = '${o['arrived_at'] ?? ''}'.isNotEmpty;
    final items = ((o['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final notes = '${o['notes'] ?? ''}'.trim();
    final carDesc = '${o['car_desc'] ?? ''}'.trim();
    final phone = '${o['phone'] ?? ''}';
    final free = ((o['free_cups'] as num?) ?? 0) > 0;
    final stColor = st == 'new' ? kOrange : st == 'ready' ? kOk : kPurple;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: arrived ? kOk : (st == 'new' ? kOrange : Colors.transparent), width: 3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('#${o['ref']}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kPurple)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: stColor, borderRadius: BorderRadius.circular(99)),
              child: Text(_labels[st] ?? st.toUpperCase(), style: TextStyle(color: st == 'new' ? kPurple : Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
            const Spacer(),
            Text(_age(o['created_at']), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black45)),
          ]),
          if (arrived) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: kOk, borderRadius: BorderRadius.circular(12)),
              child: const Row(children: [
                Icon(Icons.directions_car, color: Colors.white),
                SizedBox(width: 8),
                Text('Customer is outside', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: kCream, border: Border.all(color: kPurple, width: 2), borderRadius: BorderRadius.circular(10)),
              child: Text('${o['car_plate'] ?? ''}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1, color: kPurple)),
            ),
            const SizedBox(width: 10),
            if (carDesc.isNotEmpty) Expanded(child: Text(carDesc, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          Text('${o['customer_name'] ?? ''}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text('Pickup: ${_pickup(o['pickup_time'])}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
          const Divider(height: 18),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('${i['qty']} ×  ${i['name_en'] ?? i['name_ar'] ?? ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: kOrange, borderRadius: BorderRadius.circular(10)),
              child: Text('Loyalty: 1 cup FREE (−${money(o['discount'])})', style: const TextStyle(color: kPurple, fontWeight: FontWeight.w800)),
            ),
          const SizedBox(height: 8),
          Text('Collect: ${money(o['total'])} OMR', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),

          // Contact
          if (phone.isNotEmpty)
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: bigButton(const Color(0xFF25D366), Colors.white),
                  onPressed: () => showWhatsAppSheet(context, o),
                  icon: const Icon(Icons.chat),
                  label: const Text('WhatsApp'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(56, 58)),
                  onPressed: () => callPhone(phone),
                  child: const Icon(Icons.call),
                ),
              ),
            ]),
          const SizedBox(height: 8),

          // Status
          if (_busy)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else ..._buttons(st),
        ]),
      ),
    );
  }

  List<Widget> _buttons(String st) {
    if (st == 'new') {
      return [
        FilledButton(style: bigButton(kOrange, kPurple), onPressed: () => _set('preparing'), child: const Text('Accept')),
        TextButton(onPressed: () => _set('cancelled'), child: const Text('Cancel order', style: TextStyle(color: kBad))),
      ];
    }
    if (st == 'preparing') {
      return [
        FilledButton(style: bigButton(kPurple, kCream), onPressed: () => _set('ready'), child: const Text('Ready')),
        TextButton(onPressed: () => _set('new'), child: const Text('Back')),
      ];
    }
    return [
      Row(children: [
        Expanded(child: FilledButton(style: bigButton(kOk, Colors.white), onPressed: () => _set('done', payment: 'cash'), child: const Text('Paid cash'))),
        const SizedBox(width: 8),
        Expanded(child: FilledButton(style: bigButton(kPurple, kCream), onPressed: () => _set('done', payment: 'card'), child: const Text('Paid card'))),
      ]),
      TextButton(onPressed: () => _set('preparing'), child: const Text('Back')),
    ];
  }
}

/// A handed-over (or cancelled) order from today, with a thank-you message button.
class _DoneTile extends StatelessWidget {
  const _DoneTile({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final cancelled = o['status'] == 'cancelled';
    final phone = '${o['phone'] ?? ''}';
    final when = '${o['updated_at'] ?? o['created_at'] ?? ''}';
    final items = ((o['items'] as List?) ?? []).map((e) => '${(e as Map)['qty']}× ${e['name_en'] ?? e['name_ar']}').join(', ');
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(children: [
          Expanded(
            child: Opacity(
              opacity: cancelled ? 0.5 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('#${o['ref']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: kPurple)),
                  const SizedBox(width: 8),
                  Text(cancelled ? 'Cancelled' : (o['payment'] == 'card' ? 'Card' : 'Cash'),
                      style: TextStyle(fontWeight: FontWeight.w800, color: cancelled ? kBad : kOk, fontSize: 13)),
                  const Spacer(),
                  Text(when.length >= 16 ? when.substring(11, 16) : '', style: const TextStyle(color: Colors.black45, fontWeight: FontWeight.w700)),
                ]),
                Text('${o['customer_name'] ?? ''} · ${o['car_plate'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('$items · ${money(o['total'])}', style: const TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          if (phone.isNotEmpty && !cancelled)
            IconButton(
              tooltip: 'Send thank you',
              onPressed: () => openWhatsApp(phone, waText('thanks', o)),
              icon: const Icon(Icons.favorite, color: Color(0xFF25D366)),
            ),
          if (phone.isNotEmpty)
            IconButton(tooltip: 'WhatsApp', onPressed: () => showWhatsAppSheet(context, o), icon: const Icon(Icons.chat, color: Color(0xFF25D366))),
        ]),
      ),
    );
  }
}
