import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Everything about one customer: loyalty card with stamp buttons, contact, notes and order history.
class CustomerSheet extends StatefulWidget {
  const CustomerSheet({super.key, required this.customer});
  final Map<String, dynamic> customer;
  @override
  State<CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<CustomerSheet> {
  late Map<String, dynamic> c = Map<String, dynamic>.from(widget.customer);
  late final _note = TextEditingController(text: '${c['note'] ?? ''}');
  List<Map<String, dynamic>>? _orders;
  bool _busy = false;

  static const _pay = {'cash': 'نقد', 'card': 'بطاقة', 'talabat': 'طلبات', 'snoonu': 'سنونو', 'khedmah': 'خدمة'};

  int get _need => ((c['need'] as num?) ?? 5).toInt();
  int get _stamps => ((c['stamps'] as num?) ?? 0).toInt();
  int get _free => ((c['free'] as num?) ?? 0).toInt();
  String get _phone => '${c['phone'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    try {
      final r = await Api.I.get('customer_orders', {'phone': _phone});
      if (mounted) setState(() => _orders = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (_) {
      if (mounted) setState(() => _orders = []);
    }
  }

  Future<void> _stamp(int delta) async {
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await Api.I.post('customer_stamps', {'id': c['id'], 'delta': delta}) as Map);
      HapticFeedback.mediumImpact();
      setState(() {
        c['stamps'] = r['stamps'];
        c['free'] = r['free'];
        c['need'] = r['need'];
      });
      if (mounted) {
        final freeNow = ((r['free'] as num?) ?? 0).toInt();
        toast(context, delta > 0 ? (freeNow > _freeBefore ? 'صار عنده كوب مجاني 🎉' : 'انضاف $delta ختم') : 'انشال ختم');
      }
    } catch (e) {
      if (mounted) toast(context, errText(e), ok: false);
    }
    _freeBefore = _free;
    if (mounted) setState(() => _busy = false);
  }

  late int _freeBefore = _free;

  Future<void> _update(Map<String, dynamic> body) async {
    try {
      await Api.I.post('customer_update', {'id': c['id'], ...body});
      setState(() {
        c.addAll(body);
      });
      if (mounted) toast(context, 'انحفظ');
    } catch (e) {
      if (mounted) toast(context, errText(e), ok: false);
    }
  }

  Future<void> _rename() async {
    final ctl = TextEditingController(text: '${c['name'] ?? ''}');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('اسم العميل'),
        content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: 'الاسم')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('احفظ')),
        ],
      ),
    );
    if (v != null) _update({'name': v});
  }

  void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  void _sendCard() {
    final link = '$kSite/card.html?c=${c['card_token']}';
    final name = '${c['name'] ?? ''}'.trim();
    final msg = 'هلا${name.isEmpty ? '' : ' $name'} 👋\nهذي بطاقة الولاء حقك في أساي دوز ($_stamps/$_need ختم):\n$link\nتقدر تضيفها لمحفظة جوالك 💜';
    _open('https://wa.me/${_phone.replaceAll('+', '')}?text=${Uri.encodeComponent(msg)}');
  }

  @override
  Widget build(BuildContext context) {
    final name = '${c['name'] ?? ''}'.trim();
    final orders = ((c['orders'] as num?) ?? 0).toInt();
    return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        maxChildSize: 0.96,
        minChildSize: 0.5,
        builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(18, 12, 18, 40), children: [
          SheetTop(
            name.isEmpty ? 'بدون اسم' : name,
            trailing: IconButton(tooltip: 'تعديل الاسم', onPressed: _rename, icon: const Icon(Icons.edit_outlined, color: kPurple)),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(_phone, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54, fontSize: 15)),
          ),
          const SizedBox(height: 14),

          // Loyalty card
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(24)),
            child: Column(children: [
              Row(children: [
                const Text('بطاقة الولاء', style: TextStyle(color: kLilac, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('$_stamps / $_need', textDirection: TextDirection.ltr, style: const TextStyle(color: kCream, fontWeight: FontWeight.w900, fontSize: 18)),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(color: kCream, borderRadius: BorderRadius.circular(18)),
                child: StampRow(filled: _stamps, need: _need, size: _need > 7 ? 26 : 32),
              ),
              if (_free > 0) ...[
                const SizedBox(height: 10),
                Pill('$_free كوب مجاني جاهز', bg: kOrange, icon: Icons.card_giftcard),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: kCream, side: const BorderSide(color: kLilac, width: 2)),
                    onPressed: _busy ? null : () => _stamp(-1),
                    icon: const Icon(Icons.remove),
                    label: const Text('ختم'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: bigButton(kOrange, kPurple),
                    onPressed: _busy ? null : () => _stamp(1),
                    icon: const Icon(Icons.add),
                    label: const Text('أضف ختم'),
                  ),
                ),
              ]),
              TextButton(
                onPressed: _busy ? null : () => _stamp(_need - _stamps),
                child: Text('كمّل البطاقة وعطه كوب مجاني (+${_need - _stamps})', style: const TextStyle(color: kLilac, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // Contact
          Row(children: [
            _action(Icons.chat, 'واتساب', kOk, () => _open('https://wa.me/${_phone.replaceAll('+', '')}')),
            const SizedBox(width: 8),
            _action(Icons.call, 'اتصال', kPurple, () => _open('tel:$_phone')),
            const SizedBox(width: 8),
            _action(Icons.wallet, 'أرسل البطاقة', kOrange, c['card_token'] == null ? null : _sendCard),
          ]),
          const SizedBox(height: 12),

          // Numbers
          Row(children: [
            _num('$orders', 'طلب'),
            const SizedBox(width: 8),
            _num(money(c['spent']), 'ر.ع صرف'),
            const SizedBox(width: 8),
            _num(orders > 0 ? money(((c['spent'] as num?) ?? 0) / orders) : '-', 'متوسط الطلب'),
          ]),
          const SizedBox(height: 12),

          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: SwitchListTile(
              value: c['offers'] == 1,
              onChanged: (v) => _update({'offers': v ? 1 : 0}),
              title: const Text('يبي يوصله العروض', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'ملاحظة (مثلاً: يحب زيادة زبدة)',
              suffixIcon: IconButton(icon: const Icon(Icons.check_circle, color: kPurple), onPressed: () => _update({'note': _note.text.trim()})),
            ),
          ),

          const SectionTitle('الطلبات', top: 22),
          if (_orders == null)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (_orders!.isEmpty)
            const EmptyNote('ما طلب للحين', icon: Icons.receipt_long_outlined)
          else
            for (final o in _orders!) _orderRow(o),
        ]),
    );
  }

  Widget _action(IconData icon, String label, Color color, VoidCallback? onTap) => Expanded(
        child: Panel(
          padding: const EdgeInsets.symmetric(vertical: 12),
          onTap: onTap,
          child: Column(children: [
            Icon(icon, color: onTap == null ? Colors.black26 : color),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
        ),
      );

  Widget _num(String v, String l) => Expanded(
        child: Panel(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(children: [
            FittedBox(child: Text(v, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kPurple))),
            Text(l, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black45)),
          ]),
        ),
      );

  Widget _orderRow(Map<String, dynamic> o) {
    final cancelled = o['status'] == 'cancelled';
    final items = ((o['items'] as List?) ?? []).map((e) => '${(e as Map)['qty']}× ${e['name_ar'] ?? e['name_en']}').join('، ');
    final when = '${o['created_at'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: const EdgeInsets.all(12),
        child: Opacity(
          opacity: cancelled ? 0.5 : 1,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(when.length >= 16 ? when.substring(0, 16) : when, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54, fontSize: 12)),
              const SizedBox(width: 8),
              Pill(o['source'] == 'pos' ? 'المحل' : 'الموقع'),
              if (((o['free_cups'] as num?) ?? 0) > 0) ...[const SizedBox(width: 6), const Pill('مجاني', bg: kOrange)],
              const Spacer(),
              Text(money(o['total']), textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w900, decoration: cancelled ? TextDecoration.lineThrough : null)),
            ]),
            const SizedBox(height: 4),
            Text(items, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (o['payment'] != null && '${o['payment']}' != '')
              Text(_pay['${o['payment']}'] ?? '${o['payment']}', style: const TextStyle(color: Colors.black45, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
