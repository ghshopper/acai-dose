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
              Image.asset('assets/logo-cream.png', height: 80),
              const SizedBox(height: 28),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('الداش بورد', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kPurple)),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _user,
                        autocorrect: false,
                        textDirection: TextDirection.ltr,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pass,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(labelText: 'كلمة السر'),
                        onSubmitted: (_) => _busy ? null : _go(),
                      ),
                      const SizedBox(height: 8),
                      Text(_err, style: const TextStyle(color: kBad, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _busy ? null : _go, child: Text(_busy ? 'لحظة…' : 'دخول')),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
