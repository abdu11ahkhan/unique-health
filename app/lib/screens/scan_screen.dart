import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io' show Platform;
import '../widgets/ui.dart';

/// Scans a QR code or barcode with the camera on phones/tablets. On other platforms (or if the camera
/// is unavailable) the user can type or paste the code instead. Pops with the scanned text.
class ScanScreen extends StatefulWidget {
  final String title, hint, manualLabel;
  final TextInputType keyboard;
  const ScanScreen({super.key, required this.title, required this.hint, this.manualLabel = 'Enter code manually', this.keyboard = TextInputType.text});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _ctl = TextEditingController();
  bool _done = false;
  static bool get cameraSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  void _finish(String v) {
    if (_done || v.trim().isEmpty) return;
    _done = true;
    Navigator.pop(context, v.trim());
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GScaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
        if (cameraSupported)
          AppCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 320,
                child: MobileScanner(
                  onDetect: (cap) {
                    final v = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                    if (v != null) _finish(v);
                  },
                  errorBuilder: (c, e) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Camera unavailable (${e.errorCode.name}). Enter the code below instead.', textAlign: TextAlign.center))),
                ),
              ),
            ),
          )
        else
          const AppCard(child: Row(children: [Icon(Icons.info_outline, color: brandBlue), SizedBox(width: 12), Expanded(child: Text('The camera is only available on a phone or tablet build. Type or paste the code instead.'))])),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.manualLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(widget.hint, style: const TextStyle(fontSize: 12, color: mutedColor)),
            const SizedBox(height: 10),
            TextField(controller: _ctl, keyboardType: widget.keyboard, onSubmitted: _finish, decoration: const InputDecoration(hintText: 'Code')),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => _finish(_ctl.text), child: const Text('Continue'))),
          ]),
        ),
      ]),
    );
  }
}
