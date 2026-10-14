import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'customer_sheet.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets.dart';

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

    return Scaffold(
      backgroundColor: kBg,
      body: Column(children: [
      PageHead(
        title: 'العملاء',
        subtitle: 'الولاء والعروض',
        loading: _loading,
        trailing: BarButton(icon: CupertinoIcons.person_badge_plus, onPressed: () async {
          final ok = await openSheet<bool>(context, const AddCustomerSheet());
          if (ok == true) {
            _load();
            if (context.mounted) toast(context, 'انضاف العميل وصارت له بطاقة');
          }
        }),
      ),
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
        child: CupertinoSearchTextField(
          placeholder: 'بحث بالاسم أو الرقم أو السيارة',
          backgroundColor: kFill,
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5), children: [
          for (final o in const [['last', 'آخر زيارة'], ['orders', 'الأكثر طلبات'], ['spent', 'الأكثر صرف'], ['away', 'غايبين من زمان']])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Capsule(o[1], selected: _sort == o[0], onTap: () => setState(() => _sort = o[0])),
            ),
          Capsule('يبون العروض', icon: CupertinoIcons.checkmark_alt, selected: _offersOnly, onTap: () => setState(() => _offersOnly = !_offersOnly)),
        ]),
      ),
      Expanded(
        child: RefreshIndicator.adaptive(
          onRefresh: _load,
          child: list.isEmpty
              ? ListView(children: const [EmptyNote('ما فيه عملاء', icon: CupertinoIcons.person_2)])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _tile(list[i]),
                ),
        ),
      ),
    ]),
    );
  }

  Widget _kpi(String v, String l) => Expanded(
        child: Panel(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kPurple)),
            Text(l, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk2)),
          ]),
        ),
      );

  Widget _tile(Map<String, dynamic> c) {
    final name = '${c['name'] ?? ''}'.trim();
    final phone = '${c['phone'] ?? ''}';
    final free = ((c['free'] as num?) ?? 0).toInt();
    final need = ((c['need'] as num?) ?? 5).toInt();
    final stamps = ((c['stamps'] as num?) ?? 0).toInt();
    return Panel(
      padding: const EdgeInsets.all(14),
      onTap: () async {
        await openSheet(context, CustomerSheet(customer: c));
        _load();
      },
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: kBg,
          child: Text(name.isEmpty ? '؟' : name.characters.first, style: const TextStyle(fontWeight: FontWeight.w700, color: kPurple, fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name.isEmpty ? 'بدون اسم' : name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              if (((c['orders'] as num?) ?? 0) >= 5) ...[const SizedBox(width: 6), _chip('دائم', kCream2)],
              if (free > 0) ...[const SizedBox(width: 6), _chip('$free مجاني', kOrange)],
            ]),
            const SizedBox(height: 2),
            Text(phone, textDirection: TextDirection.ltr, style: const TextStyle(color: kInk2, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              '${c['orders']} طلب · ${money(c['spent'])} ر.ع · ${_ago(c['last_at'])}',
              style: const TextStyle(color: kInk2, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Bar(value: need > 0 ? stamps / need : 0.0, height: 6, color: kOrange, bg: kCream2),
              ),
              const SizedBox(width: 8),
              Text('$stamps/$need', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kPurple)),
            ]),
          ]),
        ),
        BarButton(
          icon: CupertinoIcons.chat_bubble_fill,
          color: kOk,
          size: 22,
          onPressed: phone.isEmpty ? null : () => launchUrl(Uri.parse('https://wa.me/${phone.replaceAll('+', '')}'), mode: LaunchMode.externalApplication),
        ),
        const Icon(CupertinoIcons.forward, color: kInk3, size: 18),
      ]),
    );
  }

  Widget _chip(String t, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kPurple)),
      );
}
