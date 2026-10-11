import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'summary_page.dart';
import 'theme.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.onLogout});
  final VoidCallback onLogout;

  Widget _item(IconData icon, String title, String sub, VoidCallback onTap, {Color color = kPurple}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_left),
          onTap: onTap,
        ),
      );

  void _open(String path) => launchUrl(Uri.parse('$kSite/$path'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const PageHead(title: 'المزيد'),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _item(Icons.settings_outlined, 'الإعدادات', 'العمولات والأسعار والعمال والولاء والمحفظة', () => _open('dashboard')),
          _item(Icons.upload_file, 'استيراد وتصفير', 'المبيعات القديمة من إكسل', () => _open('dashboard')),
          _item(Icons.edit_note, 'إدخال يدوي للتطبيقات', 'مبيعات طلبات وسنونو وخدمة', () => _open('dashboard')),
          _item(Icons.storefront, 'صفحة الطلب', 'order.acaiee.com', () => _open('')),
          const SizedBox(height: 10),
          _item(Icons.logout, 'خروج', 'تسجيل الخروج من التطبيق', () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('تبي تطلع؟'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لا')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('خروج')),
                ],
              ),
            );
            if (ok == true) onLogout();
          }, color: kBad),
        ]),
      ),
    ]);
  }
}
