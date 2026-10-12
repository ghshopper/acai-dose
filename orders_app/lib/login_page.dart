import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});
  final void Function(Map<String, dynamic> me) onLogin;

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
      widget.onLogin(Map<String, dynamic>.from(r as Map));
    } catch (e) {
      setState(() {
        _err = errText(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPurple,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: AutofillGroup(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Image.asset('assets/logo-purple.png', height: 70),
                    const SizedBox(height: 14),
                    const Text('Orders · Staff login', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kPurple)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _user,
                      autofillHints: const [AutofillHints.username],
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Username'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Password'),
                      onSubmitted: (_) => _busy ? null : _go(),
                    ),
                    const SizedBox(height: 10),
                    Text(_err, style: const TextStyle(color: kBad, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    FilledButton(onPressed: _busy ? null : _go, child: Text(_busy ? 'Logging in…' : 'Log in')),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
