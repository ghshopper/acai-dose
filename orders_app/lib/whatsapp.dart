import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// Opens a WhatsApp chat with the customer, with an optional ready-made message.
Future<bool> openWhatsApp(String phone, [String text = '']) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  final url = 'https://wa.me/$digits${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}';
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

Future<bool> callPhone(String phone) => launchUrl(Uri.parse('tel:$phone'));

class WaTemplate {
  const WaTemplate(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const kTemplates = [
  WaTemplate('ready', 'Order is ready', Icons.check_circle),
  WaTemplate('coming', 'Coming to your car', Icons.directions_walk),
  WaTemplate('where', "Can't find your car", Icons.search),
  WaTemplate('delay', 'Few more minutes', Icons.schedule),
  WaTemplate('thanks', 'Thank you', Icons.favorite),
];

/// The message for one template, filled with the order's details.
String waText(String key, Map<String, dynamic> o) {
  final name = '${o['customer_name'] ?? ''}'.trim();
  final hi = name.isEmpty ? 'Hi 👋' : 'Hi $name 👋';
  final ref = '${o['ref'] ?? ''}';
  final plate = '${o['car_plate'] ?? ''}'.trim();
  switch (key) {
    case 'ready':
      return '$hi\nYour Açaí Dose order #$ref is ready ✅\nWhen you arrive, tap "I\'m here" on your order page and we\'ll bring it to your car 💜';
    case 'coming':
      return '$hi\nWe\'re coming out with your order now 🚶${plate.isEmpty ? '' : '\nIs your car $plate?'}';
    case 'where':
      return '$hi\nWe\'re outside with your order but can\'t find your car 🙏\nCould you send us its colour or exactly where you parked?';
    case 'delay':
      return '$hi\nYour order #$ref needs a few more minutes, sorry for the wait 🙏';
    case 'thanks':
      return 'Thank you${name.isEmpty ? '' : ' $name'} 💜\nHope you enjoyed your açaí! Don\'t forget your loyalty card, see you soon 😊\n@acaidose.om';
    default:
      return '';
  }
}

/// Bottom sheet with the ready-made messages plus an empty chat.
Future<void> showWhatsAppSheet(BuildContext context, Map<String, dynamic> o) {
  final phone = '${o['phone'] ?? ''}';
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    backgroundColor: kCream,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('WhatsApp · #${o['ref']} · ${o['customer_name'] ?? ''}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kPurple)),
          const SizedBox(height: 10),
          for (final t in kTemplates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: Icon(t.icon, color: const Color(0xFF25D366)),
                  title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(waText(t.key, o), maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(c);
                    openWhatsApp(phone, waText(t.key, o));
                  },
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(c);
              openWhatsApp(phone);
            },
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Open chat (no message)'),
          ),
        ]),
      ),
    ),
  );
}
