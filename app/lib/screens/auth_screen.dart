import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import '../widgets/ui.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _nick = TextEditingController();
  bool _register = false, _busy = false, _show = false;

  Future<void> _submit() async {
    final s = context.read<AppState>();
    final email = _email.text.trim(), pw = _pw.text;
    if (email.isEmpty || pw.isEmpty) return toast(context, 'Enter email and password', error: true);
    setState(() => _busy = true);
    await guarded(context, () => _register ? s.signUp(email, pw, _nick.text.trim()) : s.login(email, pw));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _server() async {
    final s = context.read<AppState>();
    final v = await askText(context, 'Server address', initial: s.api.baseUrl, hint: 'http://192.168.1.10:3000');
    if (v != null && v.isNotEmpty) {
      await s.api.setBaseUrl(v);
      if (mounted) toast(context, 'Server set to ${s.api.baseUrl}');
    }
  }

  Future<void> _forgot() async {
    final s = context.read<AppState>();
    final email = await askText(context, 'Reset password', initial: _email.text, hint: 'Your account email', type: TextInputType.emailAddress);
    if (email == null || email.isEmpty || !mounted) return;
    String? code;
    final ok = await guarded(context, () async {
      final r = await s.api.post('/app/user/sendForgotPasswordEmail', {'email': email}, false);
      code = r?['devCode'];
    });
    if (!ok || !mounted) return;
    if (code == null) return toast(context, 'If that account exists, a code was sent.');
    // No email service in the test build: the code is shown here.
    final entered = await askText(context, 'Enter the code', hint: 'Test code: $code', type: TextInputType.number);
    if (entered == null || !mounted) return;
    final np = await askText(context, 'New password', obscure: true);
    if (np == null || !mounted) return;
    await guarded(context, () => s.api.post('/app/user/resetPassword', {'email': email, 'code': entered, 'newPassword': np}, false), success: 'Password changed. Sign in with the new password.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(Icons.monitor_weight_outlined, size: 64, color: scheme.primary),
                const SizedBox(height: 8),
                Text('Unique Health', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text('Clone · local test build', textAlign: TextAlign.center, style: TextStyle(color: scheme.outline)),
                const SizedBox(height: 28),
                if (_register) ...[
                  TextField(controller: _nick, decoration: const InputDecoration(labelText: 'Nickname', prefixIcon: Icon(Icons.person_outline))),
                  const SizedBox(height: 12),
                ],
                TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline))),
                const SizedBox(height: 12),
                TextField(
                  controller: _pw,
                  obscureText: !_show,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show))),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _submit, child: Padding(padding: const EdgeInsets.all(12), child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_register ? 'Create account' : 'Sign in'))),
                TextButton(onPressed: () => setState(() => _register = !_register), child: Text(_register ? 'I already have an account' : 'Create an account')),
                if (!_register) TextButton(onPressed: _forgot, child: const Text('Forgot password?')),
                const Divider(height: 32),
                OutlinedButton.icon(
                  onPressed: () {
                    _email.text = 'demo@unique.test';
                    _pw.text = 'demo1234';
                    _submit();
                  },
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Use demo account'),
                ),
                TextButton.icon(onPressed: _server, icon: const Icon(Icons.dns_outlined, size: 18), label: Text('Server: ${context.watch<AppState>().api.baseUrl}')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
