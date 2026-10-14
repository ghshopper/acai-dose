import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets.dart';

/// Menu prices, loyalty rule, app commissions and staff accounts, all in the app.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic>? _s;
  String? _err;

  // loyalty
  bool _loyOn = true;
  int _need = 6;
  String _unit = 'cup';
  bool _loyDirty = false;

  final _wa = TextEditingController();

  // commissions
  final Map<String, TextEditingController> _comm = {for (final k in kChannelNames.keys) k: TextEditingController()};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _comm.values) {
      c.dispose();
    }
    _wa.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = Map<String, dynamic>.from(await Api.I.get('settings') as Map);
      final l = Map<String, dynamic>.from((r['loyalty'] as Map?) ?? {});
      final c = Map<String, dynamic>.from((r['commissions'] as Map?) ?? {});
      setState(() {
        _s = r;
        _err = null;
        _loyOn = l['on'] == true;
        _need = ((l['need'] as num?) ?? 6).toInt();
        _unit = '${l['unit'] ?? 'cup'}';
        _loyDirty = false;
        _wa.text = '${r['whatsapp'] ?? ''}'.replaceFirst('+968', '');
        for (final k in _comm.keys) {
          final v = ((c[k] as num?) ?? 0).toDouble();
          _comm[k]!.text = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
        }
      });
    } catch (e) {
      setState(() => _err = errText(e));
    }
  }

  Future<void> _post(String action, Map<String, dynamic> body, String done) async {
    try {
      await Api.I.post(action, body);
      HapticFeedback.mediumImpact();
      if (mounted) toast(context, done);
      _load();
    } catch (e) {
      if (mounted) toast(context, errText(e), ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      backgroundColor: kBg,
      body: Column(children: [
        const PageHead(title: 'الإعدادات'),
        Expanded(
          child: s == null
              ? Center(child: _err == null ? const CupertinoActivityIndicator() : Text(_err!))
              : RefreshIndicator.adaptive(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                    const SectionTitle('المنيو والأسعار', note: 'اللي تطفيه يختفي من الموقع والكاشير'),
                    for (final p in (s['products'] as List)) _ProductRow(product: Map<String, dynamic>.from(p as Map), onSave: (body) => _post('save_product', body, 'انحفظ')),
                    const SectionTitle('إضافات اصنع أساي باولك', note: 'تنضاف على سعر الباول'),
                    for (final t in ((s['toppings'] as List?) ?? [])) _ToppingRow(topping: Map<String, dynamic>.from(t as Map), onSave: (body) => _post('save_topping', body, 'انحفظت الإضافة')),
                    const SectionTitle('واتساب المحل', note: 'يطلع زر للزبائن في صفحة الطلب'),
                    Panel(
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _wa,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(prefixText: '+968  ', hintText: '9XXXXXXX', isDense: true, fillColor: kField),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: () => _post('save_contact', {'whatsapp': _wa.text.trim()}, _wa.text.trim().isEmpty ? 'انشال زر الواتساب' : 'انحفظ، الزر طالع للزبائن'),
                          child: const Text('احفظ'),
                        ),
                      ]),
                    ),
                    const SectionTitle('بطاقة الولاء'),
                    _loyalty(),
                    const SectionTitle('عمولات التطبيقات', note: 'تنحسب على الطلبات الجديدة'),
                    _commissions(),
                    const SectionTitle('حسابات العمال'),
                    _staff((s['users'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()),
                  ]),
                ),
        ),
      ]),
    );
  }

  Widget _loyalty() => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchRow(
            title: 'نظام الولاء شغال',
            value: _loyOn,
            onChanged: (v) => setState(() {
              _loyOn = v;
              _loyDirty = true;
            }),
          ),
          const Divider(height: 20),
          const SizedBox(height: 4),
          Row(children: [
            const Expanded(child: Text('عدد الأختام', style: TextStyle(fontWeight: FontWeight.w600))),
            SizedBox(width: 44, child: Text('$_need', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kPurple))),
            IosStepper(
              onMinus: _need > 2
                  ? () => setState(() {
                        _need--;
                        _loyDirty = true;
                      })
                  : null,
              onPlus: _need < 30
                  ? () => setState(() {
                        _need++;
                        _loyDirty = true;
                      })
                  : null,
            ),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('$_need ${_unit == 'cup' ? 'أكواب' : 'طلبات'} والي بعده مجاناً (الـ ${_need + 1} علينا)',
                style: const TextStyle(color: kInk2, fontWeight: FontWeight.w700)),
          ),
          StampRow(filled: (_need / 2).floor(), need: _need, size: _need > 8 ? 22 : 28),
          const SizedBox(height: 12),
          Seg<String>(
            value: _unit,
            items: const {'cup': 'ختم لكل كوب', 'order': 'ختم لكل طلب'},
            onChanged: (v) => setState(() {
              _unit = v;
              _loyDirty = true;
            }),
          ),
          if (_loyDirty) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _post('save_loyalty', {'on': _loyOn, 'need': _need, 'unit': _unit}, 'انحفظ، والبطاقات اللي في المحافظ بتتحدث'),
              child: const Text('احفظ نظام الولاء'),
            ),
          ],
        ]),
      );

  Widget _commissions() => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final e in kChannelNames.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(child: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _comm[e.key],
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(suffixText: '%', isDense: true, fillColor: kField),
                  ),
                ),
              ]),
            ),
          OutlinedButton(
            onPressed: () {
              final body = <String, dynamic>{};
              for (final k in _comm.keys) {
                body[k] = double.tryParse(_comm[k]!.text.trim()) ?? 0;
              }
              _post('save_commissions', body, 'انحفظت العمولات');
            },
            child: const Text('احفظ العمولات'),
          ),
        ]),
      );

  Widget _staff(List<Map<String, dynamic>> users) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final u in users)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: u['role'] == 'owner' ? kPurple : kCream2, shape: BoxShape.circle),
                  child: Icon(u['role'] == 'owner' ? CupertinoIcons.star_fill : CupertinoIcons.person_fill, size: 18, color: u['role'] == 'owner' ? kCream : kPurple),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${u['username']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: kInk)),
                    Text(u['role'] == 'owner' ? 'صاحب المحل' : (u['active'] == 1 ? 'عامل · شغال' : 'عامل · موقوف'), style: const TextStyle(color: kInk2, fontSize: 13)),
                  ]),
                ),
                if (u['role'] != 'owner') ...[
                  BarButton(icon: CupertinoIcons.lock_fill, size: 20, onPressed: () => _password(u)),
                  IosSwitch(value: u['active'] == 1, onChanged: (v) => _post('user_update', {'id': u['id'], 'active': v}, v ? 'رجع الحساب يشتغل' : 'انوقف الحساب')),
                ],
              ]),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(onPressed: _addUser, icon: const Icon(CupertinoIcons.person_badge_plus), label: const Text('حساب عامل جديد')),
        ]),
      );

  Future<void> _password(Map<String, dynamic> u) async {
    final ctl = TextEditingController();
    final v = await showIos<String>(context, title: 'كلمة سر جديدة لـ ${u['username']}', body: alertField(ctl, placeholder: '٦ حروف أو أكثر', autofocus: true, ltr: true), actions: [
      const IosAct('إلغاء'),
      IosAct('احفظ', get: () => ctl.text, main: true),
    ]);
    if (v != null && v.isNotEmpty) _post('user_update', {'id': u['id'], 'password': v}, 'تغيرت كلمة السر');
  }

  Future<void> _addUser() async {
    final un = TextEditingController();
    final pw = TextEditingController();
    final ok = await showIos<bool>(context,
        title: 'حساب عامل جديد',
        body: Column(children: [
          alertField(un, placeholder: 'اسم المستخدم (إنجليزي)', autofocus: true, ltr: true),
          alertField(pw, placeholder: 'كلمة السر', ltr: true),
        ]),
        actions: const [IosAct('إلغاء', value: false), IosAct('أضف', value: true, main: true)]);
    if (ok == true) _post('add_user', {'username': un.text.trim(), 'password': pw.text}, 'انضاف الحساب');
  }
}

class _ProductRow extends StatefulWidget {
  const _ProductRow({required this.product, required this.onSave});
  final Map<String, dynamic> product;
  final Future<void> Function(Map<String, dynamic> body) onSave;
  @override
  State<_ProductRow> createState() => _ProductRowState();
}

class _ProductRowState extends State<_ProductRow> {
  late final _price = TextEditingController(text: money(widget.product['price']));
  late bool _active = widget.product['active'] == 1;
  bool _dirty = false;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _editDesc() async {
    final ar = TextEditingController(text: '${widget.product['desc_ar'] ?? ''}');
    final en = TextEditingController(text: '${widget.product['desc_en'] ?? ''}');
    final ok = await showIos<bool>(context,
        title: 'وصف ${widget.product['name_ar']}',
        body: Column(children: [
          alertField(ar, placeholder: 'بالعربي', maxLines: 3),
          alertField(en, placeholder: 'English', maxLines: 3, ltr: true),
        ]),
        actions: const [IosAct('إلغاء', value: false), IosAct('احفظ', value: true, main: true)]);
    if (ok != true) return;
    final p = double.tryParse(_price.text.trim()) ?? 0;
    await widget.onSave({'id': widget.product['id'], 'price': p, 'active': _active, 'desc_ar': ar.text.trim(), 'desc_en': en.text.trim()});
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${widget.product['name_ar']}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: _active ? kInk : kInk3, decoration: _active ? null : TextDecoration.lineThrough)),
                  if (widget.product['kind'] == 'build') const Text('سعر الباول بدون الإضافات', style: TextStyle(fontSize: 11, color: kInk2, fontWeight: FontWeight.w700)),
                  GestureDetector(
                    onTap: _editDesc,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(('${widget.product['desc_ar'] ?? ''}').isEmpty ? '+ أضف وصف' : '${widget.product['desc_ar']}',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kPurple, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _price,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(isDense: true, suffixText: 'ر.ع', fillColor: kField),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
              ),
              const SizedBox(width: 8),
              IosSwitch(value: _active, onChanged: (v) => setState(() {
                    _active = v;
                    _dirty = true;
                  })),
            ]),
            if (_dirty)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () async {
                    final p = double.tryParse(_price.text.trim());
                    if (p == null || p < 0) {
                      toast(context, 'السعر غلط', ok: false);
                      return;
                    }
                    await widget.onSave({'id': widget.product['id'], 'price': p, 'active': _active});
                    if (mounted) setState(() => _dirty = false);
                  },
                  icon: const Icon(CupertinoIcons.checkmark),
                  label: const Text('احفظ'),
                ),
              ),
          ]),
        ),
      );
}

class _ToppingRow extends StatefulWidget {
  const _ToppingRow({required this.topping, required this.onSave});
  final Map<String, dynamic> topping;
  final Future<void> Function(Map<String, dynamic> body) onSave;
  @override
  State<_ToppingRow> createState() => _ToppingRowState();
}

class _ToppingRowState extends State<_ToppingRow> {
  late final _price = TextEditingController(text: money(widget.topping['price']));
  late bool _active = widget.topping['active'] == 1;
  bool _dirty = false;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(children: [
            Expanded(child: Text('${widget.topping['name_ar']}', style: TextStyle(fontWeight: FontWeight.w600, color: _active ? kInk : kInk3))),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _price,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(isDense: true, prefixText: '+', fillColor: kField),
                onChanged: (_) => setState(() => _dirty = true),
              ),
            ),
            const SizedBox(width: 8),
            IosSwitch(value: _active, onChanged: (v) => setState(() {
                  _active = v;
                  _dirty = true;
                })),
            if (_dirty)
              BarButton(
                icon: CupertinoIcons.checkmark_alt_circle_fill,
                color: kOk,
                onPressed: () async {
                  final p = double.tryParse(_price.text.trim());
                  if (p == null || p < 0) {
                    toast(context, 'السعر غلط', ok: false);
                    return;
                  }
                  await widget.onSave({'id': widget.topping['id'], 'price': p, 'active': _active});
                  if (mounted) setState(() => _dirty = false);
                },
              ),
          ]),
        ),
      );
}
