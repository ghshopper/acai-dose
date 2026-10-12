import 'package:flutter/material.dart';

import 'api.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.I.load();
  runApp(const OrdersApp());
}

class OrdersApp extends StatelessWidget {
  const OrdersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Açaí Dose Orders',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: const Gate(),
    );
  }
}

/// Login screen until there is a valid session, then the orders.
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  Map<String, dynamic>? _me;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.I.get('me');
      _me = r is Map<String, dynamic> ? r : null;
    } on ApiError catch (e) {
      _me = null;
      if (e.code == 'network') _error = 'No internet connection';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _logout() async {
    try {
      await Api.I.post('logout', {});
    } catch (_) {}
    await Api.I.clearSession();
    if (mounted) setState(() => _me = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: kPurple, body: Center(child: CircularProgressIndicator(color: kCream)));
    if (_error != null) {
      return Scaffold(
        backgroundColor: kPurple,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, style: const TextStyle(color: kCream, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            FilledButton(style: bigButton(kOrange, kPurple), onPressed: _check, child: const Text('Retry')),
          ]),
        ),
      );
    }
    if (_me == null) return LoginPage(onLogin: (me) => setState(() => _me = me));
    return HomePage(me: _me!, onLogout: _logout);
  }
}
