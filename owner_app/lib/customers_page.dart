import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'summary_page.dart';
import 'theme.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key, required this.onLoggedOut});
  final VoidCallback onLoggedOut;
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = false;
  String _q = '';
  String _sort = 'last';
  bool _offersOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Api.I.get('customers');
      _all = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on ApiError catch (e) {
      if (e.code == 'login_required' || e.code == 'forbidden') {
        widget.onLoggedOut();
        return;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  int _daysAgo(dynamic t) {
    final d = DateTime.tryParse('${t ?? ''}'.replaceFirst(' ', 'T'));
    return d == null ? 99999 : DateTime.now().difference(d).inDays;
  }

  String _ago(dynamic t) {
    final n = _daysAgo(t);
    if (n == 99999) return '-';
    if (n == 0) return 'اليوم';
    if (n == 1) return 'أمس';
    return 'قبل $n يوم';
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = _all.where((c) {
      if (_offersOnly && c['offers'] != 1) return false;
      if (q.isEmpty) return true;
      return [c['name'], c['phone'], c['car_plate'], c['car_desc'], c['note']].any((v) => '${v ?? ''}'.toLowerCase().contains(q));
    }).toList();
    int byNum(String k, Map a, Map b) => ((b[k] as num?) ?? 0).compareTo((a[k] as num?) ?? 0);
    list.sort((a, b) {
      switch (_sort) {
        case 'orders':
          return byNum('orders', a, b);
        case 'spent':
          return byNum('spent', a, b);
        case 'away':
          return _daysAgo(b['last_at']).compareTo(_daysAgo(a['last_at']));
        default:
          return _daysAgo(a['last_at']).compareTo(_daysAgo(b['last_at']));
      }
    });
    final repeat = _all.where((c) => ((c['orders'] as num?) ?? 0) > 1).length;

    return Column(children: [
      const PageHead(title: 'العملاء'),
      if (_loading) const LinearProgressIndicator(minHeight: 3, color: kOrange, backgroundColor: kCream2),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          _kpi('${_all.length}', 'عميل'),
          const SizedBox(width: 8),
          _kpi('$repeat', 'رجعوا'),
          const SizedBox(width: 8),
          _kpi('${_all.where((c) => c['offers'] == 1).length}', 'يبون العروض'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو الرقم أو السيارة'),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      SizedBox(
        height: 46,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), children: [
          for (final o in const [['last', 'آخر زيارة'], ['orders', 'الأكثر طلبات'], ['spent', 'الأكثر صرف'], ['away', 'غايبين من زمان']])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(
                label: Text(o[1]),
                selected: _sort == o[0],
                showCheckmark: false,
                selectedColor: kPurple,
                labelStyle: TextStyle(color: _sort == o[0] ? kCream : kPurple, fontWeight: FontWeight.w800, fontSize: 13),
                backgroundColor: Colors.white,
                side: BorderSide.none,
                onSelected: (_) => setState(() => _sort = o[0]),
              ),
            ),
          FilterChip(
            label: const Text('يبون العروض'),
            selected: _offersOnly,
            onSelected: (v) => setState(() => _offersOnly = v),
            backgroundColor: Colors.white,
            side: BorderSide.none,
          ),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: list.isEmpty
              ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('ما فيه عملاء', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black45))))])
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

  Widget _kpi(String v, String l) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kPurple)),
            Text(l, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black45)),
          ]),
        ),
      );

  Widget _tile(Map<String, dynamic> c) {
    final name = '${c['name'] ?? ''}'.trim();
    final phone = '${c['phone'] ?? ''}';
    final free = ((c['free'] as num?) ?? 0).toInt();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: kCream2,
          child: Text(name.isEmpty ? '؟' : name.characters.first, style: const TextStyle(fontWeight: FontWeight.w900, color: kPurple, fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name.isEmpty ? 'بدون اسم' : name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
              if (((c['orders'] as num?) ?? 0) >= 5) ...[const SizedBox(width: 6), _chip('دائم', kCream2)],
              if (free > 0) ...[const SizedBox(width: 6), _chip('$free مجاني', kOrange)],
            ]),
            const SizedBox(height: 2),
            Text(phone, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              '${c['orders']} طلب · ${money(c['spent'])} ر.ع · الأختام ${c['stamps'] ?? 0} · ${_ago(c['last_at'])}',
              style: const TextStyle(color: Colors.black45, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
        IconButton(
          tooltip: 'واتساب',
          icon: const Icon(Icons.chat, color: kOk),
          onPressed: phone.isEmpty ? null : () => launchUrl(Uri.parse('https://wa.me/${phone.replaceAll('+', '')}'), mode: LaunchMode.externalApplication),
        ),
      ]),
    );
  }

  Widget _chip(String t, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kPurple)),
      );
}
