import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});
  final VoidCallback onLogin;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String _err = '';

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      final r = await Api.I.post('login', {'username': _user.text.trim(), 'password': _pass.text});
      if (r is Map && r['role'] == 'owner') {
        widget.onLogin();
        return;
      }
      await Api.I.post('logout', {});
      await Api.I.clearSession();
      setState(() => _err = errText(ApiError('forbidden')));
    } catch (e) {
      setState(() => _err = errText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPurple,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Image.asset('assets/logo-cream.png', height: 72),
              const SizedBox(height: 26),
              const Text('الداش بورد', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: kCream)),
              const SizedBox(height: 4),
              const Text('سجّل دخول بحساب صاحب المحل', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: kLilac)),
              const SizedBox(height: 24),
              AutofillGroup(
                child: Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Column(children: [
                    TextField(
                      controller: _user,
                      autocorrect: false,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(hintText: 'اسم المستخدم', floatingLabelBehavior: FloatingLabelBehavior.never),
                    ),
                    const Divider(indent: 16),
                    TextField(
                      controller: _pass,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(hintText: 'كلمة السر', floatingLabelBehavior: FloatingLabelBehavior.never),
                      onSubmitted: (_) => _busy ? null : _go(),
                    ),
                  ]),
                ),
              ),
              if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFB4B4), fontWeight: FontWeight.w600))),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(style: bigButton(kOrange, kPurple), onPressed: _busy ? null : _go, child: _busy ? const CupertinoActivityIndicator(color: kPurple) : const Text('دخول')),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
