import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'cost_page.dart';
import 'settings_page.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.onLogout});
  final VoidCallback onLogout;

  void _open(String path) => launchUrl(Uri.parse('$kSite/$path'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const PageHead(title: 'المزيد'),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 30), children: [
          NavRow(
            tint: const Color(0xFF8E8E93),
            icon: CupertinoIcons.gear_alt_fill,
            title: 'الإعدادات',
            sub: 'الأسعار، الولاء، العمولات، حسابات العمال',
            onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const SettingsPage())),
          ),
          NavRow(
            tint: kOk,
            icon: CupertinoIcons.cube_box_fill,
            title: 'التكلفة والمخزون',
            sub: 'تكلفة كل كوب، الجرد، المشتريات، أسعار المكونات',
            onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const CostPage())),
          ),
          NavRow(
            tint: kOrange,
            icon: CupertinoIcons.bag_fill,
            title: 'مبيعات التطبيقات',
            sub: 'أدخل مبيعات طلبات وسنونو وخدمة من الكشف',
            onTap: () async {
              final ok = await openSheet<bool>(context, const AppSaleSheet());
              if (ok == true && context.mounted) toast(context, 'انحفظت المبيعات');
            },
          ),
          const SectionTitle('على الموقع', top: 14),
          NavRow(tint: const Color(0xFF1C1C1E), icon: CupertinoIcons.creditcard_fill, title: 'المحفظة والموقع', sub: 'إعداد Apple و Google Wallet وموقع المحل', onTap: () => _open('dashboard'), external: true),
          NavRow(tint: const Color(0xFF007AFF), icon: CupertinoIcons.arrow_up_doc_fill, title: 'استيراد وتصفير', sub: 'المبيعات القديمة من إكسل', onTap: () => _open('dashboard'), external: true),
          NavRow(tint: kPurple, icon: CupertinoIcons.link, title: 'صفحة الطلب', sub: 'order.acaiee.com', onTap: () => _open(''), external: true),
          NavRow(tint: const Color(0xFF5856D6), icon: CupertinoIcons.eye_fill, title: 'معاينة المنيو', sub: 'المنيو مع الباول قبل لا تطلقه (الطلب مقفل فيها)', onTap: () => _open('index.html?preview=1'), external: true),
          const SizedBox(height: 14),
          NavRow(
            danger: true,
            icon: CupertinoIcons.square_arrow_right,
            title: 'خروج',
            sub: 'تسجيل الخروج من التطبيق',
            onTap: () async {
              if (await confirm(context, 'تبي تطلع؟', yes: 'خروج')) onLogout();
            },
          ),
          const SizedBox(height: 16),
          Center(child: Image.asset('assets/logo-purple.png', height: 34, color: kInk3, colorBlendMode: BlendMode.srcIn)),
          const SizedBox(height: 6),
          const Center(child: Text('Açaí Dose · Owner', style: TextStyle(color: kInk3, fontWeight: FontWeight.w600, fontSize: 12))),
        ]),
      ),
    ]);
  }
}
