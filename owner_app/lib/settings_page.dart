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
      backgroundColor: kCream2,
      body: Column(children: [
        PageHead(
          title: 'الإعدادات',
          trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: kCream)),
        ),
        Expanded(
          child: s == null
              ? Center(child: _err == null ? const CircularProgressIndicator() : Text(_err!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                    const SectionTitle('المنيو والأسعار', note: 'اللي تطفيه يختفي من الموقع والكاشير'),
                    for (final p in (s['products'] as List)) _ProductRow(product: Map<String, dynamic>.from(p as Map), onSave: (body) => _post('save_product', body, 'انحفظ السعر')),
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _loyOn,
            onChanged: (v) => setState(() {
              _loyOn = v;
              _loyDirty = true;
            }),
            title: const Text('نظام الولاء شغال', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Row(children: [
            const Expanded(child: Text('عدد الأختام', style: TextStyle(fontWeight: FontWeight.w800))),
            IconButton.filledTonal(onPressed: _need > 2 ? () => setState(() {
                  _need--;
                  _loyDirty = true;
                }) : null, icon: const Icon(Icons.remove)),
            SizedBox(width: 44, child: Text('$_need', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kPurple))),
            IconButton.filledTonal(onPressed: _need < 30 ? () => setState(() {
                  _need++;
                  _loyDirty = true;
                }) : null, icon: const Icon(Icons.add)),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('$_need ${_unit == 'cup' ? 'أكواب' : 'طلبات'} والي بعده مجاناً (الـ ${_need + 1} علينا)',
                style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
          ),
          StampRow(filled: (_need / 2).floor(), need: _need, size: _need > 8 ? 22 : 28),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'cup', label: Text('ختم لكل كوب')), ButtonSegment(value: 'order', label: Text('ختم لكل طلب'))],
            selected: {_unit},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() {
              _unit = v.first;
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
                Expanded(child: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _comm[e.key],
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(suffixText: '%', isDense: true),
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: u['role'] == 'owner' ? kPurple : kCream2,
                child: Icon(u['role'] == 'owner' ? Icons.star : Icons.person, color: u['role'] == 'owner' ? kCream : kPurple),
              ),
              title: Text('${u['username']}', textDirection: TextDirection.ltr, textAlign: TextAlign.start, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(u['role'] == 'owner' ? 'صاحب المحل' : (u['active'] == 1 ? 'عامل · شغال' : 'عامل · موقوف')),
              trailing: u['role'] == 'owner'
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: 'كلمة سر جديدة', onPressed: () => _password(u), icon: const Icon(Icons.key, color: kPurple)),
                      Switch(value: u['active'] == 1, onChanged: (v) => _post('user_update', {'id': u['id'], 'active': v}, v ? 'رجع الحساب يشتغل' : 'انوقف الحساب')),
                    ]),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(onPressed: _addUser, icon: const Icon(Icons.person_add_alt_1), label: const Text('حساب عامل جديد')),
        ]),
      );

  Future<void> _password(Map<String, dynamic> u) async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('كلمة سر جديدة لـ ${u['username']}'),
        content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: '٦ حروف أو أكثر')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: const Text('احفظ')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) _post('user_update', {'id': u['id'], 'password': v}, 'تغيرت كلمة السر');
  }

  Future<void> _addUser() async {
    final un = TextEditingController();
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('حساب عامل جديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: un, autofocus: true, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(labelText: 'اسم المستخدم (إنجليزي)')),
          const SizedBox(height: 10),
          TextField(controller: pw, decoration: const InputDecoration(labelText: 'كلمة السر')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('أضف')),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Text('${widget.product['name_ar']}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: _active ? Colors.black87 : Colors.black38, decoration: _active ? null : TextDecoration.lineThrough)),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _price,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(isDense: true, suffixText: 'ر.ع'),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
              ),
              Switch(value: _active, onChanged: (v) => setState(() {
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
                  icon: const Icon(Icons.check),
                  label: const Text('احفظ'),
                ),
              ),
          ]),
        ),
      );
}
