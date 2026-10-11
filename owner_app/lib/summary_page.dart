import 'package:flutter/material.dart';

import 'api.dart';
import 'period.dart';
import 'sheets.dart';
import 'stats.dart';
import 'theme.dart';
import 'widgets.dart';

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key, required this.period, required this.onLoggedOut});
  final PeriodController period;
  final VoidCallback onLoggedOut;
  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  Stats? _s;
  Stats? _prev;
  String? _err;
  bool _loading = false;

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
      // The same number of days just before, to compare with
      final p = widget.period;
      final n = p.days.length;
      final pFrom = DateTime(p.from.year, p.from.month, p.from.day - n);
      final pTo = DateTime(p.from.year, p.from.month, p.from.day - 1);
      final res = await Future.wait([
        Api.I.get('range', {'from': p.fromStr, 'to': p.toStr}),
        Api.I.get('range', {'from': ymd(pFrom), 'to': ymd(pTo)}),
      ]);
      final prevDays = [for (var i = 0; i < n; i++) DateTime(pFrom.year, pFrom.month, pFrom.day + i)];
      _s = Stats(Map<String, dynamic>.from(res[0] as Map), p.days);
      _prev = Stats(Map<String, dynamic>.from(res[1] as Map), prevDays);
      _err = null;
    } on ApiError catch (e) {
      if (e.code == 'login_required' || e.code == 'forbidden') {
        widget.onLoggedOut();
        return;
      }
      _err = errText(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'صباح الخير ☀️';
    if (h < 18) return 'مساء الخير';
    return 'مساء الخير 🌙';
  }

  String get _vs {
    switch (widget.period.key) {
      case 'today':
        return 'مقارنة بأمس';
      case 'yest':
        return 'مقارنة باليوم اللي قبله';
      case 'month':
        return 'مقارنة بنفس عدد الأيام قبلها';
      default:
        return 'مقارنة بالفترة اللي قبلها';
    }
  }

  Future<void> _quick(Widget sheet, String done) async {
    final ok = await openSheet<bool>(context, sheet);
    if (ok == true) {
      _load();
      if (mounted) toast(context, done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Column(children: [
      PageHead(title: 'الملخص', subtitle: _greeting, period: widget.period),
      if (_loading) const LinearProgressIndicator(minHeight: 3, color: kOrange, backgroundColor: kCream2),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: s == null
              ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(_err ?? '')))])
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 30), children: [
                  if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_err!, style: const TextStyle(color: kBad))),
                  _hero(s),
                  const SizedBox(height: 12),
                  Row(children: [
                    _quickBtn(Icons.add_card, 'مصروف', () => _quick(const AddExpenseSheet(), 'انحفظ المصروف')),
                    const SizedBox(width: 8),
                    _quickBtn(Icons.delivery_dining, 'مبيعات تطبيق', () => _quick(const AppSaleSheet(), 'انحفظت المبيعات')),
                    const SizedBox(width: 8),
                    _quickBtn(Icons.person_add_alt_1, 'عميل جديد', () => _quick(const AddCustomerSheet(), 'انضاف العميل')),
                  ]),
                  const SizedBox(height: 12),
                  _grid([
                    _stat(Icons.trending_up, 'إجمالي المبيعات', s.sales, '${s.orderCount} طلب · متوسط ${money(s.avg)}', before: _prev?.sales),
                    _stat(Icons.payments_outlined, 'المصاريف', s.exp, '${s.expCount} مصروف', before: _prev?.exp, lowerIsBetter: true),
                    _stat(Icons.public, 'الموقع', s.site, '${s.siteOrders} طلب · ${s.siteCups} كوب', share: s.pct(s.site)),
                    _stat(Icons.storefront, 'المحل', s.shop, '${s.shopOrders} عملية · ${s.shopCups} كوب', share: s.pct(s.shop)),
                    _stat(Icons.delivery_dining, 'التطبيقات', s.appGross, 'طلبات وسنونو وخدمة', share: s.pct(s.appGross)),
                    _stat(Icons.percent, 'العمولات', s.comm, 'تخصمها التطبيقات'),
                  ]),
                  _sec('طرق الدفع والحسابات', 'المفروض يوصلك = المبيعات − العمولة'),
                  _grid([
                    for (final m in s.methods) _pay(m),
                    if (s.unpaidCount > 0) _unpaid(s),
                  ]),
                  if (s.daily.length > 1) ...[_sec('المبيعات اليومية', '${money(s.sales)} ر.ع'), _chart(s)],
                  _sec('الأكثر طلباً', 'عدد الأكواب'),
                  _products(s),
                ]),
        ),
      ),
    ]);
  }

  Widget _quickBtn(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: Panel(
          padding: const EdgeInsets.symmetric(vertical: 12),
          onTap: onTap,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: kCream2, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: kPurple, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
        ),
      );

  Widget _hero(Stats s) {
    final total = s.sales <= 0 ? 1.0 : s.sales;
    int flex(double v) => (v.clamp(0, total) / total * 1000).round();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kPurple, kPurple2], begin: Alignment.topRight, end: Alignment.bottomLeft),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x33470D43), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('صافي الربح', style: TextStyle(color: kLilac, fontWeight: FontWeight.w800, fontSize: 16)),
          const Spacer(),
          if (_prev != null) DeltaBadge(now: s.net, before: _prev!.net, onDark: true),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(money(s.net), textDirection: TextDirection.ltr, style: TextStyle(color: s.net < 0 ? const Color(0xFFFFB4B4) : kCream, fontSize: 42, fontWeight: FontWeight.w900)),
          const SizedBox(width: 8),
          const Text('ر.ع', style: TextStyle(color: kLilac, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 12,
            child: s.sales <= 0
                ? Container(color: kPurple2)
                : Row(children: [
                    if (s.net > 0) Expanded(flex: flex(s.net), child: Container(color: kCream)),
                    if (s.comm > 0) Expanded(flex: flex(s.comm), child: Container(color: kOrange)),
                    if (s.exp > 0) Expanded(flex: flex(s.exp), child: Container(color: const Color(0xFFC86A8A))),
                  ]),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, children: [
          _legend(kCream, 'الصافي'),
          _legend(kOrange, 'العمولات ${money(s.comm)}'),
          _legend(const Color(0xFFC86A8A), 'المصاريف ${money(s.exp)}'),
        ]),
        if (_prev != null) ...[
          const SizedBox(height: 8),
          Text('$_vs: ${money(_prev!.net)}', style: const TextStyle(color: kLilac, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(color: kCream, fontSize: 12, fontWeight: FontWeight.w700)),
      ]);

  Widget _grid(List<Widget> items) => LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final i in items) SizedBox(width: w, child: i)]);
      });

  Widget _box(Widget child) => Panel(padding: const EdgeInsets.all(14), child: child);

  Widget _stat(IconData icon, String label, double v, String sub, {int? share, double? before, bool lowerIsBetter = false}) => _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: Colors.black45),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54, fontSize: 13))),
          if (before != null) DeltaBadge(now: v, before: before, lowerIsBetter: lowerIsBetter),
        ]),
        const SizedBox(height: 6),
        Text(money(v), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kPurple)),
        const SizedBox(height: 2),
        Text(share == null ? sub : '$sub · $share%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black45)),
        if (share != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: share / 100, minHeight: 6, color: kOrange, backgroundColor: kCream2),
          ),
        ],
      ]));

  Widget _pay(Method m) => _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: m.isApp ? const Color(0xFFFDE9C8) : kCream2, borderRadius: BorderRadius.circular(99)),
            child: Text(m.isApp ? 'تحويل' : 'بالدرج', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(money(m.net), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kPurple)),
        _row('المبيعات', money(m.gross)),
        if (m.isApp) _row('العمولة', money(m.comm)),
        _row('الطلبات', '${m.n}'),
      ]));

  Widget _unpaid(Stats s) => _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('طلبات موقع غير مستلمة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 6),
        Text(money(s.unpaidTotal), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kPurple)),
        _row('الطلبات', '${s.unpaidCount}'),
      ]));

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(children: [
          Text(a, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black45)),
          const Spacer(),
          Text(b, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
        ]),
      );

  Widget _sec(String t, String sub) => SectionTitle(t, note: sub);

  Widget _chart(Stats s) {
    final max = s.daily.fold(0.0, (m, e) => e.value > m ? e.value : m);
    final today = DateTime.now();
    return _box(SizedBox(
      height: 190,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final e in s.daily)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (e.value > 0 && s.daily.length <= 10)
                  FittedBox(child: Text(e.value.toStringAsFixed(1), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black54))),
                const SizedBox(height: 2),
                Container(
                  height: max > 0 ? (e.value / max * 140).clamp(2, 140).toDouble() : 2,
                  decoration: BoxDecoration(
                    color: e.key.year == today.year && e.key.month == today.month && e.key.day == today.day ? kOrange : kPurple,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(child: Text('${e.key.day}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black45))),
              ]),
            ),
          ),
      ]),
    ));
  }

  Widget _products(Stats s) {
    if (s.products.isEmpty) return _box(const EmptyNote('ما فيه طلبات في هالفترة', icon: Icons.local_drink_outlined));
    final top = s.products.first.value;
    return _box(Column(children: [
      for (final p in s.products)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(flex: 5, child: Text(p.key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: top > 0 ? p.value / top : 0, minHeight: 10, color: kPurple, backgroundColor: kCream2),
              ),
            ),
            SizedBox(width: 40, child: Text('${p.value}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900))),
          ]),
        ),
    ]));
  }
}
