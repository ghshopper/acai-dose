import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';

/// One line on the receipt.
class ReceiptItem {
  ReceiptItem({required this.qty, required this.nameEn, required this.nameAr, required this.price});
  final int qty;
  final String nameEn;
  final String nameAr;
  final double price;
}

/// Everything printed on a customer receipt.
class ReceiptData {
  ReceiptData({
    required this.ref,
    required this.time,
    required this.source,
    required this.items,
    required this.total,
    this.discount = 0,
    this.payment = '',
    this.customer = '',
    this.carPlate = '',
    this.pickup = '',
    this.notes = '',
    this.stamps = '',
  });

  final String ref;
  final DateTime time;
  final String source; // web | pos
  final List<ReceiptItem> items;
  final double total;
  final double discount;
  final String payment; // cash | card | talabat | snoonu | khedmah | '' (not paid yet)
  final String customer;
  final String carPlate;
  final String pickup;
  final String notes;
  final String stamps; // e.g. "3/6", empty when unknown

  double get subtotal => items.fold(0.0, (s, i) => s + i.qty * i.price);

  /// Builds a receipt from an order as the API returns it (active_orders / pos_today).
  factory ReceiptData.fromOrder(Map<String, dynamic> o, {String stamps = ''}) {
    final items = ((o['items'] as List?) ?? []).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return ReceiptItem(
        qty: ((m['qty'] as num?) ?? 1).toInt(),
        nameEn: '${m['name_en'] ?? ''}',
        nameAr: '${m['name_ar'] ?? ''}',
        price: ((m['price'] as num?) ?? 0).toDouble(),
      );
    }).toList();
    return ReceiptData(
      ref: '${o['ref'] ?? ''}',
      time: DateTime.tryParse('${o['created_at'] ?? ''}'.replaceFirst(' ', 'T')) ?? DateTime.now(),
      source: '${o['source'] ?? 'web'}',
      items: items,
      total: ((o['total'] as num?) ?? 0).toDouble(),
      discount: ((o['discount'] as num?) ?? 0).toDouble(),
      payment: '${o['payment'] ?? ''}',
      customer: '${o['customer_name'] ?? ''}',
      carPlate: '${o['car_plate'] ?? ''}',
      pickup: '${o['pickup_time'] ?? ''}',
      notes: '${o['notes'] ?? ''}'.trim(),
      stamps: stamps,
    );
  }
}

const _payNames = {
  'cash': 'Cash · نقد',
  'card': 'Card · بطاقة',
  'talabat': 'Talabat · طلبات',
  'snoonu': 'Snoonu · سنونو',
  'khedmah': 'Khedmah · خدمة',
};

/// Draws the receipt as a black-and-white picture [width] pixels wide
/// (384 for 58 mm paper, 576 for 80 mm) and returns it as PNG bytes.
/// Drawing it ourselves keeps the logo and the Arabic text looking right on any printer.
Future<Uint8List> renderReceipt(ReceiptData d, int width) async {
  final w = width.toDouble();
  final scale = width / 384.0;
  double s(double v) => v * scale;
  const pad = 14.0;
  final inner = w - s(pad) * 2;

  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w, 4000), Paint()..color = Colors.white);
  var y = s(10);

  TextPainter tp(String text, double size, {FontWeight weight = FontWeight.w600, TextAlign align = TextAlign.center, double? maxW, TextDirection? dir}) {
    final p = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: Colors.black, fontSize: s(size), fontWeight: weight, height: 1.25)),
      textAlign: align,
      textDirection: dir ?? (RegExp(r'^[؀-ۿ]').hasMatch(text) ? TextDirection.rtl : TextDirection.ltr),
    );
    p.layout(minWidth: maxW ?? inner, maxWidth: maxW ?? inner);
    return p;
  }

  void center(String text, double size, {FontWeight weight = FontWeight.w600, double gap = 4}) {
    final p = tp(text, size, weight: weight);
    p.paint(c, Offset(s(pad), y));
    y += p.height + s(gap);
  }

  void dashes() {
    y += s(6);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = s(2);
    for (var x = s(pad); x < w - s(pad); x += s(10)) {
      c.drawLine(Offset(x, y), Offset(x + s(5), y), paint);
    }
    y += s(12);
  }

  /// A row with text on the left and text on the right.
  void row(String left, String right, double size, {FontWeight weight = FontWeight.w700}) {
    final r = tp(right, size, weight: weight, align: TextAlign.right, maxW: inner * 0.42, dir: TextDirection.ltr);
    final l = tp(left, size, weight: weight, align: TextAlign.left, maxW: inner - r.width - s(8), dir: TextDirection.ltr);
    l.paint(c, Offset(s(pad), y));
    r.paint(c, Offset(w - s(pad) - r.width, y));
    y += (l.height > r.height ? l.height : r.height) + s(4);
  }

  // Logo
  try {
    final data = await rootBundle.load('assets/logo-black.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final img = (await codec.getNextFrame()).image;
    final lw = w * 0.62;
    final lh = lw * img.height / img.width;
    c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), Rect.fromLTWH((w - lw) / 2, y, lw, lh), Paint()..filterQuality = FilterQuality.high);
    y += lh + s(6);
  } catch (_) {
    center('AÇAÍ DOSE', 30, weight: FontWeight.w900);
  }
  center('Al Qurum 29, Muscat · القرم ٢٩، مسقط', 15, weight: FontWeight.w600);
  dashes();

  // Order number
  center('Order · رقم الطلب', 15);
  center('#${d.ref}', 44, weight: FontWeight.w900, gap: 2);
  final t = d.time;
  String two(int v) => v.toString().padLeft(2, '0');
  final h12 = ((t.hour + 11) % 12) + 1;
  final when = '${two(t.day)}/${two(t.month)}/${t.year}  $h12:${two(t.minute)} ${t.hour < 12 ? 'AM' : 'PM'}';
  center(when, 16);
  center(d.source == 'pos' ? 'In shop · في المحل' : d.source == 'curb' ? 'Car order · طلب من السيارة' : 'Online order · طلب من الموقع', 16, weight: FontWeight.w800);

  if (d.source != 'pos') {
    if (d.customer.isNotEmpty) center(d.customer, 18, weight: FontWeight.w800);
    if (d.carPlate.isNotEmpty) {
      final p = tp('Car  ${d.carPlate}', 22, weight: FontWeight.w900);
      final box = Rect.fromLTWH(s(pad), y, inner, p.height + s(12));
      c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(s(8))), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s(2.5)
        ..color = Colors.black);
      p.paint(c, Offset(s(pad), y + s(6)));
      y += box.height + s(6);
    }
    final pk = d.pickup.isEmpty || d.pickup == 'ASAP' ? 'ASAP · بأسرع وقت' : d.pickup;
    center('Pickup: $pk', 16, weight: FontWeight.w700);
  }
  dashes();

  // Items
  for (final i in d.items) {
    row('${i.qty} x  ${i.nameEn}', money(i.qty * i.price), 19);
    if (i.nameAr.isNotEmpty && i.nameAr != i.nameEn) {
      final p = tp(i.nameAr, 16, weight: FontWeight.w600, align: TextAlign.left, maxW: inner - s(34), dir: TextDirection.rtl);
      p.paint(c, Offset(s(pad) + s(34), y - s(2)));
      y += p.height + s(4);
    }
  }
  dashes();

  // Totals
  if (d.discount > 0) {
    row('Subtotal · المجموع', money(d.subtotal), 16, weight: FontWeight.w600);
    row('Free cup · كوب مجاني', '-${money(d.discount)}', 16, weight: FontWeight.w700);
  }
  row('TOTAL · الإجمالي', '${money(d.total)} OMR', 24, weight: FontWeight.w900);
  y += s(2);
  center(d.payment.isEmpty ? 'Not paid yet · لم يُدفع' : 'Paid: ${_payNames[d.payment] ?? d.payment}', 16, weight: FontWeight.w700);

  if (d.notes.isNotEmpty) {
    y += s(4);
    final p = tp(RegExp(r'^[؀-ۿ]').hasMatch(d.notes) ? 'ملاحظة: ${d.notes}' : 'Note: ${d.notes}', 16, weight: FontWeight.w700);
    final box = Rect.fromLTWH(s(pad), y, inner, p.height + s(12));
    c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(s(8))), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s(2)
      ..color = Colors.black);
    p.paint(c, Offset(s(pad), y + s(6)));
    y += box.height + s(4);
  }

  if (d.stamps.isNotEmpty) {
    y += s(4);
    center('Your stamps: ${d.stamps} · أختامك', 17, weight: FontWeight.w800);
  }
  dashes();

  // Footer
  center('Thank you! · شكراً لك', 19, weight: FontWeight.w900);
  center('order.acaiee.com', 16, weight: FontWeight.w700, gap: 2);
  center('@acaidose.om', 16, weight: FontWeight.w700);
  y += s(10);

  final pic = rec.endRecording();
  final img = await pic.toImage(width, y.ceil());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
