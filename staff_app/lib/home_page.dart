import 'package:flutter/material.dart';

import 'orders_controller.dart';
import 'orders_page.dart';
import 'pos_page.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.me, required this.onLogout});
  final Map<String, dynamic> me;
  final VoidCallback onLogout;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final OrdersController _orders;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _orders = OrdersController(onLoggedOut: widget.onLogout)..start();
  }

  @override
  void dispose() {
    _orders.dispose();
    super.dispose();
  }

  Widget _tabButton(int i, String label, IconData icon, int badge) {
    final on = _tab == i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: () => setState(() => _tab = i),
        style: TextButton.styleFrom(
          backgroundColor: on ? kCream : Colors.transparent,
          foregroundColor: on ? kPurple : kCream,
          minimumSize: const Size(120, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: const BorderSide(color: kCream, width: 2)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        icon: Icon(icon, size: 20),
        label: Text(badge > 0 ? '$label ($badge)' : label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _orders,
      builder: (context, _) {
        final wide = MediaQuery.of(context).size.width >= 700;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 68,
            titleSpacing: 12,
            title: Row(children: [
              Image.asset('assets/logo-cream.png', height: 34),
              const SizedBox(width: 10),
              Icon(Icons.circle, size: 12, color: _orders.online ? const Color(0xFF7BD389) : const Color(0xFFE06C6C)),
            ]),
            actions: [
              _tabButton(0, 'Orders', Icons.receipt_long, _orders.newCount),
              _tabButton(1, 'POS', Icons.point_of_sale, 0),
              if (wide) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text('${widget.me['username']}', style: const TextStyle(color: kLilac, fontWeight: FontWeight.w700)))),
              IconButton(
                tooltip: 'Log out',
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Log out?'),
                      content: const Text('The order alarm stops until someone logs in again.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Log out')),
                      ],
                    ),
                  );
                  if (ok == true) widget.onLogout();
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(children: [
            if (_tab == 1 && (_orders.newCount > 0 || _orders.arrivedCount > 0))
              Material(
                color: kOrange,
                child: InkWell(
                  onTap: () => setState(() => _tab = 0),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _orders.newCount > 0
                          ? 'New website order (${_orders.newCount}) — tap to open Orders and Accept'
                          : 'A customer is waiting outside — tap to open Orders',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kPurple, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(index: _tab, children: [
                OrdersPage(controller: _orders),
                PosPage(onLoggedOut: widget.onLogout),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
