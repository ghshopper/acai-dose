import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'customers_page.dart';
import 'expenses_page.dart';
import 'login_page.dart';
import 'more_page.dart';
import 'orders_page.dart';
import 'period.dart';
import 'summary_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.I.load();
  runApp(const OwnerApp());
}

class OwnerApp extends StatelessWidget {
  const OwnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Açaí Dose',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Gate(),
    );
  }
}

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  bool _loading = true;
  bool _in = false;
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
      _in = r is Map && r['role'] == 'owner';
    } on ApiError catch (e) {
      _in = false;
      if (e.code == 'network') _error = errText(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _logout() async {
    try {
      await Api.I.post('logout', {});
    } catch (_) {}
    await Api.I.clearSession();
    if (mounted) setState(() => _in = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: kPurple, body: Center(child: CupertinoActivityIndicator(color: kCream, radius: 14)));
    if (_error != null) {
      return Scaffold(
        backgroundColor: kPurple,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, style: const TextStyle(color: kCream, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            FilledButton(style: bigButton(kOrange, kPurple), onPressed: _check, child: const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('حاول مرة ثانية'))),
          ]),
        ),
      );
    }
    if (!_in) return LoginPage(onLogin: () => setState(() => _in = true));
    return HomePage(onLogout: _logout);
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onLogout});
  final VoidCallback onLogout;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final period = PeriodController();
  int _tab = 0;

  @override
  void dispose() {
    period.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      SummaryPage(period: period, onLoggedOut: widget.onLogout),
      OrdersPage(period: period, onLoggedOut: widget.onLogout),
      CustomersPage(onLoggedOut: widget.onLogout),
      ExpensesPage(period: period, onLoggedOut: widget.onLogout),
      MorePage(onLogout: widget.onLogout),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: _tab,
        onTap: (i) {
          HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
        activeColor: kPurple,
        inactiveColor: const Color(0xFF8E8E93),
        backgroundColor: const Color(0xF7FBFAF8),
        iconSize: 26,
        items: const [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.chart_pie), activeIcon: Icon(CupertinoIcons.chart_pie_fill), label: 'الملخص'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.doc_text), activeIcon: Icon(CupertinoIcons.doc_text_fill), label: 'الطلبات'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.person_2), activeIcon: Icon(CupertinoIcons.person_2_fill), label: 'العملاء'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.creditcard), activeIcon: Icon(CupertinoIcons.creditcard_fill), label: 'المصاريف'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.ellipsis_circle), activeIcon: Icon(CupertinoIcons.ellipsis_circle_fill), label: 'المزيد'),
        ],
      ),
    );
  }
}
