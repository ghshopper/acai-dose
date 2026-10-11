import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'stats.dart';
import 'theme.dart';
import 'widgets.dart';

const Map<String, String> kStatusNames = {'new': 'جديد', 'preparing': 'يتحضر', 'ready': 'جاهز', 'done': 'مستلم', 'cancelled': 'ملغي'};
const Map<String, String> kPayNames = {'cash': 'نقد', 'card': 'بطاقة', 'talabat': 'طلبات', 'snoonu': 'سنونو', 'khedmah': 'خدمة'};

/// One order in full, with a cancel button. Pops true when the order changed.
class OrderSheet extends StatefulWidget {
  const OrderSheet({super.key, required this.order});
  final Map<String, dynamic> order;
  @override
  State<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<OrderSheet> {
  bool _busy = false;

  Future<void> _cancel() async {
    final o = widget.order;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('تلغي الطلب #${o['ref']}؟'),
        content: const Text('ينشال من المبيعات، وإذا كان له رقم تنشال أختامه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('لا')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: kBad), onPressed: () => Navigator.pop(d, true), child: const Text('ألغِ الطلب')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await Api.I.post('order_status', {'id': o['id'], 'status': 'cancelled'});
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        toast(context, errText(e), ok: false);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final web = o['source'] != 'pos';
    final cancelled = o['status'] == 'cancelled';
    final items = ((o['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final phone = '${o['phone'] ?? ''}';
    final when = '${o['created_at'] ?? ''}';
    final comm = numOf(o['commission']);
    final imported = o['customer_name'] == 'Imported';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTop('طلب #${o['ref']}'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            Pill(web ? 'الموقع' : (imported ? 'مستورد' : 'المحل'), bg: web ? const Color(0xFFFDE9C8) : Colors.white),
            Pill(kStatusNames['${o['status']}'] ?? '${o['status']}',
                bg: o['status'] == 'done' ? const Color(0xFFDDF0E3) : cancelled ? const Color(0xFFF6D6D6) : Colors.white),
            if (when.length >= 16) Pill(when.substring(0, 16), bg: Colors.white, icon: Icons.schedule),
          ]),
          const SizedBox(height: 14),
          if (web || phone.isNotEmpty)
            Panel(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(Icons.person_outline, color: kPurple),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${o['customer_name'] ?? ''}'.trim().isEmpty ? 'عميل' : '${o['customer_name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    if (phone.isNotEmpty) Text(phone, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                    if ('${o['car_plate'] ?? ''}'.isNotEmpty) Text('السيارة: ${o['car_plate']}', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                  ]),
                ),
                if (phone.isNotEmpty) ...[
                  IconButton(onPressed: () => launchUrl(Uri.parse('https://wa.me/${phone.replaceAll('+', '')}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.chat, color: kOk)),
                  IconButton(onPressed: () => launchUrl(Uri.parse('tel:$phone')), icon: const Icon(Icons.call, color: kPurple)),
                ],
              ]),
            ),
          const SizedBox(height: 10),
          Panel(
            child: Column(children: [
              for (final i in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: kCream2, borderRadius: BorderRadius.circular(9)),
                      child: Text('${i['qty']}', style: const TextStyle(fontWeight: FontWeight.w900, color: kPurple)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${i['name_ar'] ?? i['name_en'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800))),
                    if (i['price'] != null)
                      Text(money(numOf(i['price']) * ((i['qty'] as num?) ?? 1)), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
                  ]),
                ),
              const Divider(height: 22),
              if (numOf(o['discount']) > 0) _line('كوب مجاني (ولاء)', '-${money(o['discount'])}'),
              if (comm > 0) _line('عمولة التطبيق', '-${money(comm)}'),
              Row(children: [
                const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const Spacer(),
                Text('${money(o['total'])} ر.ع',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: kPurple, decoration: cancelled ? TextDecoration.lineThrough : null)),
              ]),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  o['payment'] == null || '${o['payment']}' == '' ? 'ما انستلم للحين' : 'الدفع: ${kPayNames['${o['payment']}'] ?? o['payment']}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54),
                ),
              ),
            ]),
          ),
          if (!cancelled && !imported) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: kBad, side: const BorderSide(color: kBad, width: 2)),
              onPressed: _busy ? null : _cancel,
              icon: const Icon(Icons.block),
              label: Text(_busy ? 'لحظة…' : 'إلغاء الطلب'),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _line(String a, String b) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text(a, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
          const Spacer(),
          Text(b, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54)),
        ]),
      );
}
