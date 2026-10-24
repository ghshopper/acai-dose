import 'package:flutter/material.dart';

import 'api.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'native.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.I.load();
  runApp(const AcaiApp());
}

class AcaiApp extends StatelessWidget {
  const AcaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Api.I.shop.isKarak ? 'Karak Dose Staff' : 'Açaí Dose Staff',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: const Gate(),
    );
  }
}

/// Shows the login screen until there is a valid session, then the app.
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
    if (_me != null) await ShopConfig.load();
    if (_me != null && Api.I.cookie != null) Native.startWatch(Api.I.cookie!, Api.I.shop);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loggedIn(Map<String, dynamic> me) async {
    await ShopConfig.load();
    if (Api.I.cookie != null) Native.startWatch(Api.I.cookie!, Api.I.shop);
    if (mounted) setState(() => _me = me);
  }

  Future<void> _logout() async {
    try {
      await Api.I.post('logout', {});
    } catch (_) {}
    await Api.I.clearSession();
    await Native.stopWatch();
    if (mounted) setState(() => _me = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: kPurple, body: Center(child: CircularProgressIndicator(color: kCream)));
    }
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
    if (_me == null) return LoginPage(onLogin: _loggedIn);
    return HomePage(me: _me!, onLogout: _logout);
  }
}
