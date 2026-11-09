import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'scan_screen.dart';

/// Signs a web client in: scan the QR code shown on the web page (or type its code), then confirm.
Future<void> scanQrLogin(BuildContext context) async {
  final s = context.read<AppState>();
  final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanScreen(title: 'Scan QR to log in', hint: 'Open /web on the backend in a browser and scan the QR code. Without a camera, paste the code shown as "uhqr:…".', manualLabel: 'Enter the code from the web page')));
  if (code == null || !context.mounted) return;
  if (!code.startsWith('uhqr:')) return toast(context, 'That is not a login QR code', error: true);
  final scanned = await guarded(context, () => s.api.post('/app/user/qrCode/scan', {'id': code}));
  if (!scanned || !context.mounted) return;
  final ok = await confirm(context, 'Log in on the web?', 'Allow the web page to open your account (${s.user?.email ?? ''}). Only confirm if you started this login yourself.', ok: 'Log in');
  if (!context.mounted) return;
  if (!ok) {
    await guarded(context, () => s.api.post('/app/user/qrCode/cancel', {'id': code}));
    return;
  }
  await guarded(context, () => s.api.post('/app/user/qrCode/confirm', {'id': code}), success: 'Web login confirmed');
}
