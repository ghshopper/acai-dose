import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'settings_page.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.onLogout});
  final VoidCallback onLogout;

  Widget _item(BuildContext context, IconData icon, String title, String sub, VoidCallback onTap, {Color color = kPurple, bool external = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          onTap: onTap,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color == kBad ? const Color(0xFFF6D6D6) : kCream2, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 16)),
                Text(sub, style: const TextStyle(color: Colors.black45, fontWeight: FontWeight.w600, fontSize: 12)),
              ]),
            ),
            Icon(external ? Icons.open_in_new : Icons.chevron_left, color: Colors.black26),
          ]),
        ),
      );

  void _open(String path) => launchUrl(Uri.parse('$kSite/$path'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const PageHead(title: 'المزيد'),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 30), children: [
          _item(context, Icons.tune, 'الإعدادات', 'الأسعار، الولاء، العمولات، حسابات العمال',
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()))),
          _item(context, Icons.delivery_dining, 'مبيعات التطبيقات', 'أدخل مبيعات طلبات وسنونو وخدمة من الكشف', () async {
            final ok = await openSheet<bool>(context, const AppSaleSheet());
            if (ok == true && context.mounted) toast(context, 'انحفظت المبيعات');
          }),
          _item(context, Icons.wallet, 'المحفظة والموقع', 'إعداد Apple و Google Wallet وموقع المحل', () => _open('dashboard'), external: true),
          _item(context, Icons.upload_file, 'استيراد وتصفير', 'المبيعات القديمة من إكسل', () => _open('dashboard'), external: true),
          _item(context, Icons.storefront, 'صفحة الطلب', 'order.acaiee.com', () => _open(''), external: true),
          const SizedBox(height: 10),
          _item(context, Icons.logout, 'خروج', 'تسجيل الخروج من التطبيق', () async {
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
          const SizedBox(height: 16),
          Center(child: Image.asset('assets/logo-purple.png', height: 34, color: Colors.black26, colorBlendMode: BlendMode.srcIn)),
          const SizedBox(height: 6),
          const Center(child: Text('Açaí Dose · Owner', style: TextStyle(color: Colors.black26, fontWeight: FontWeight.w700, fontSize: 12))),
        ]),
      ),
    ]);
  }
}
