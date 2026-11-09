import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/scale_transport.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

/// Light colour, brightness and language of the scale's display. Values are remembered per device
/// and re-sent whenever the scale is connected.
class DisplaySettingsCard extends StatefulWidget {
  final Device device;
  const DisplaySettingsCard({super.key, required this.device});
  @override
  State<DisplaySettingsCard> createState() => _DisplaySettingsCardState();
}

const displayColors = ['#4F8CFF', '#3DB88B', '#F5A623', '#F43F31', '#B452FF', '#FFFFFF'];
const scaleLanguages = {'en': 'English', 'es': 'Español', 'fr': 'Français', 'de': 'Deutsch', 'it': 'Italiano', 'pt': 'Português', 'ru': 'Русский', 'tr': 'Türkçe', 'ar': 'العربية', 'hi': 'हिन्दी', 'zh': '中文', 'ja': '日本語', 'ko': '한국어'};

Color hexColor(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

class _DisplaySettingsCardState extends State<DisplaySettingsCard> {
  String get _p => 'dev:${widget.device.id}:';
  late String _color;
  late double _brightness;
  late String _lang;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().prefs;
    _color = p.getString('${_p}light') ?? displayColors.first;
    _brightness = (p.getInt('${_p}brightness') ?? 80).toDouble();
    _lang = p.getString('${_p}lang') ?? 'en';
  }

  bool get _connected {
    final s = context.read<AppState>();
    return s.scale.state == LinkState.connected && s.scale.device?.mac == widget.device.mac;
  }

  Future<void> _send(String cmd, Map<String, dynamic> data) async {
    final s = context.read<AppState>();
    if (!_connected) return toast(context, 'Saved. It will be applied the next time the scale is connected.');
    s.scale.command({'cmd': cmd, ...data});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Section(
      title: 'Display',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Light colour', style: TextStyle(color: mutedColor, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, children: [
          for (final c in displayColors)
            GestureDetector(
              onTap: () async {
                setState(() => _color = c);
                await s.prefs.setString('${_p}light', c);
                _send('light', {'color': c});
              },
              child: Container(width: 34, height: 34, decoration: BoxDecoration(color: hexColor(c), shape: BoxShape.circle, border: Border.all(color: _color == c ? brandBlue : Colors.black26, width: _color == c ? 3 : 1))),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          const Text('Brightness', style: TextStyle(color: mutedColor, fontSize: 13)),
          Expanded(
            child: Slider(
              value: _brightness,
              min: 10,
              max: 100,
              divisions: 9,
              label: '${_brightness.round()}%',
              onChanged: (v) => setState(() => _brightness = v),
              onChangeEnd: (v) async {
                await s.prefs.setInt('${_p}brightness', v.round());
                _send('brightness', {'value': v.round()});
              },
            ),
          ),
        ]),
        Row(children: [
          const Text('Scale language', style: TextStyle(color: mutedColor, fontSize: 13)),
          const Spacer(),
          DropdownButton<String>(
            value: _lang,
            items: [for (final e in scaleLanguages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _lang = v);
              await s.prefs.setString('${_p}lang', v);
              _send('language', {'value': v});
            },
          ),
        ]),
      ]),
    );
  }
}

/// Firmware check and over-the-air style update: the image is downloaded from the backend,
/// verified with SHA-256 and streamed to the scale in chunks.
class FirmwareScreen extends StatefulWidget {
  final Device device;
  const FirmwareScreen({super.key, required this.device});
  @override
  State<FirmwareScreen> createState() => _FirmwareScreenState();
}

class _FirmwareScreenState extends State<FirmwareScreen> {
  String? _current, _error;
  Map<String, dynamic>? _latest;
  bool _busy = false, _done = false;
  double _progress = 0;
  String _step = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final s = context.read<AppState>();
    setState(() {
      _error = null;
      _done = false;
    });
    try {
      if (s.scale.state != LinkState.connected || s.scale.device?.mac != widget.device.mac) await s.scale.connect(widget.device.mac);
      final info = await s.deviceRequest('info', 'info');
      _current = '${info['fw']}';
      _latest = Map<String, dynamic>.from(await s.api.get('/app/xinmiaoProductHardwareVersion/judgeVersion', query: {'model': widget.device.name, 'version': _current}));
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _update() async {
    final s = context.read<AppState>();
    final l = _latest!;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _step = 'Downloading firmware…';
    });
    StreamSubscription? sub;
    try {
      final res = await http.get(Uri.parse('${s.api.baseUrl}${l['url']}')).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw ApiException('Download failed (${res.statusCode})');
      final bytes = res.bodyBytes;
      if (sha256.convert(bytes).toString() != l['sha256']) throw ApiException('The downloaded firmware is corrupted (checksum mismatch). Nothing was installed.');
      setState(() => _step = 'Sending to the scale…');
      sub = s.scale.events.listen((e) {
        if (e['event'] == 'fwProgress' && mounted) setState(() => _progress = ((e['data']['pct'] as num).toDouble() / 100));
      });
      final done = s.scale.events.firstWhere((e) => e['event'] == 'fwDone').timeout(const Duration(seconds: 30), onTimeout: () => throw ApiException('The scale did not confirm the update.'));
      s.scale.command({'cmd': 'fwStart', 'version': l['latest'], 'size': bytes.length});
      const chunk = 4096;
      for (var o = 0; o < bytes.length; o += chunk) {
        s.scale.command({'cmd': 'fwChunk', 'seq': o ~/ chunk, 'data': base64Encode(bytes.sublist(o, o + chunk > bytes.length ? bytes.length : o + chunk))});
        await Future.delayed(const Duration(milliseconds: 40));
      }
      setState(() => _step = 'Verifying and installing…');
      s.scale.command({'cmd': 'fwEnd', 'sha256': l['sha256']});
      final r = await done;
      if (r['data']['ok'] != true) throw ApiException('The scale rejected the update (${r['data']['reason']}).');
      _current = '${r['data']['version']}';
      _done = true;
      _progress = 1;
      _latest = {...l, 'upToDate': true};
    } catch (e) {
      _error = '$e';
    } finally {
      await sub?.cancel();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _latest;
    final upToDate = l?['upToDate'] == true;
    return GScaffold(
      appBar: AppBar(title: const Text('Firmware update')),
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
        AppCard(
          child: Column(children: [
            Icon(_done || upToDate ? Icons.verified : Icons.system_update, size: 56, color: _done || upToDate ? Colors.green : brandBlue),
            const SizedBox(height: 10),
            Text(_current == null ? (_error == null ? 'Checking…' : 'Could not read the scale') : 'Current version $_current', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (l != null) Text(upToDate ? 'Your scale is up to date.' : 'Version ${l['latest']} is available (${((l['size'] as num) / 1024).round()} KB)', style: const TextStyle(color: mutedColor)),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (_busy) ...[const SizedBox(height: 16), LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 8), const SizedBox(height: 6), Text('$_step ${(_progress * 100).round()}%', style: const TextStyle(fontSize: 12, color: mutedColor))],
            const SizedBox(height: 16),
            if (l != null && !upToDate) FilledButton.icon(onPressed: _busy ? null : _update, icon: const Icon(Icons.download), label: const Text('Update now')),
            if (l == null || upToDate || _error != null) TextButton(onPressed: _busy ? null : _check, child: const Text('Check again')),
          ]),
        ),
        if (l != null && !upToDate)
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("What's new", style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final n in (l['notes'] as List)) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• $n')),
              const SizedBox(height: 8),
              const Text('Keep the app open and the scale powered during the update.', style: TextStyle(fontSize: 12, color: mutedColor)),
            ]),
          ),
      ]),
    );
  }
}

/// Wi-Fi setup for network scales: scan, choose, enter the password, watch the status.
class WifiSetupScreen extends StatefulWidget {
  final Device device;
  const WifiSetupScreen({super.key, required this.device});
  @override
  State<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

const wifiFailureText = {
  'wrong_password': ('Wrong password', 'Check the password and try again. Passwords are case sensitive.'),
  'unsupported_5ghz': ('5 GHz network', 'This scale only supports 2.4 GHz Wi-Fi. Pick a 2.4 GHz network or enable the 2.4 GHz band on your router.'),
  'not_found': ('Network not found', 'Move the scale closer to the router and scan again.'),
  'timeout': ('Timed out', 'The router did not answer in time. Try again.'),
};

class _WifiSetupScreenState extends State<WifiSetupScreen> {
  List<Map<String, dynamic>> _nets = [];
  bool _scanning = false, _connecting = false;
  String? _error, _connected, _failReason, _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    final s = context.read<AppState>();
    setState(() {
      _scanning = true;
      _error = null;
      _failReason = null;
    });
    try {
      if (s.scale.state != LinkState.connected || s.scale.device?.mac != widget.device.mac) await s.scale.connect(widget.device.mac);
      final info = await s.deviceRequest('info', 'info');
      _connected = info['wifi'] as String?;
      final r = await s.deviceRequest('wifiScan', 'wifiList', timeout: const Duration(seconds: 8));
      _nets = [for (final n in (r['networks'] as List)) Map<String, dynamic>.from(n)]..sort((a, b) => (b['rssi'] as num).compareTo(a['rssi'] as num));
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(Map<String, dynamic> n) async {
    final s = context.read<AppState>();
    String pw = '';
    if (n['secure'] == true) {
      final v = await askText(context, 'Password for ${n['ssid']}', obscure: true);
      if (v == null || !mounted) return;
      pw = v;
    }
    setState(() {
      _connecting = true;
      _selected = '${n['ssid']}';
      _failReason = null;
    });
    try {
      final done = s.scale.events.firstWhere((e) => e['event'] == 'wifiStatus' && e['data']['state'] != 'connecting').timeout(const Duration(seconds: 15), onTimeout: () => {'data': {'state': 'failed', 'reason': 'timeout'}});
      s.scale.command({'cmd': 'wifiConnect', 'ssid': n['ssid'], 'password': pw});
      final r = Map<String, dynamic>.from((await done)['data']);
      if (r['state'] == 'connected') {
        _connected = '${n['ssid']}';
        if (mounted) toast(context, 'Connected to ${n['ssid']}');
      } else {
        _failReason = '${r['reason']}';
      }
    } catch (e) {
      _failReason = 'timeout';
    }
    if (mounted) setState(() => _connecting = false);
  }

  @override
  Widget build(BuildContext context) {
    final fail = _failReason == null ? null : (wifiFailureText[_failReason] ?? ('Connection failed', 'Try again.'));
    return GScaffold(
      appBar: AppBar(title: const Text('Wi-Fi setup'), actions: [IconButton(onPressed: _scanning || _connecting ? null : _scan, icon: const Icon(Icons.refresh))]),
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
        if (_connected != null) AppCard(child: Row(children: [const Icon(Icons.wifi, color: Colors.green), const SizedBox(width: 12), Expanded(child: Text('Connected to $_connected', style: const TextStyle(fontWeight: FontWeight.w700)))])),
        if (fail != null)
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Icon(Icons.error_outline, color: Colors.red), const SizedBox(width: 10), Text('${fail.$1} · $_selected', style: const TextStyle(fontWeight: FontWeight.w800))]),
              const SizedBox(height: 6),
              Text(fail.$2),
            ]),
          ),
        if (_scanning) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (_error != null) AppCard(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_connecting) const AppCard(child: Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 14), Text('Connecting the scale…')])),
        if (_nets.isNotEmpty)
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              for (final n in _nets)
                MenuRow(
                  icon: n['secure'] == true ? Icons.wifi_lock : Icons.wifi,
                  title: '${n['ssid']}',
                  subtitle: '${n['band']} GHz · ${n['rssi']} dBm',
                  onTap: _connecting ? null : () => _connect(n),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// Users stored on a fingerprint scale. Each fingerprint slot is linked to a profile.
class FingerprintScreen extends StatefulWidget {
  final Device device;
  const FingerprintScreen({super.key, required this.device});
  @override
  State<FingerprintScreen> createState() => _FingerprintScreenState();
}

class _FingerprintScreenState extends State<FingerprintScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true, _enrolling = false;
  int _step = 0;
  String? _error;
  StreamSubscription? _sub;

  String get _key => 'finger:${widget.device.id}';

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _sub = s.scale.events.listen((e) {
      if (e['event'] == 'fingerProgress' && mounted) setState(() => _step = (e['data']['step'] as num).toInt());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _links(AppState s) => Map<String, dynamic>.from(jsonDecode(s.prefs.getString(_key) ?? '{}'));

  Future<void> _load() async {
    final s = context.read<AppState>();
    try {
      if (s.scale.state != LinkState.connected || s.scale.device?.mac != widget.device.mac) await s.scale.connect(widget.device.mac);
      final r = await s.deviceRequest('fingerList', 'fingerUsers');
      _users = [for (final u in (r['users'] as List)) Map<String, dynamic>.from(u)];
      _error = null;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final s = context.read<AppState>();
    final m = await showDialog<Member>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Who is this fingerprint for?'), children: [for (final x in s.members) SimpleDialogOption(onPressed: () => Navigator.pop(c, x), child: Text('${x.avatar}  ${x.name}'))]),
    );
    if (m == null || !mounted) return;
    setState(() {
      _enrolling = true;
      _step = 0;
      _error = null;
    });
    try {
      final r = await s.deviceRequest('fingerEnroll', 'fingerUsers', data: {'name': m.name}, timeout: const Duration(seconds: 12), failEvents: ['fingerError']);
      _users = [for (final u in (r['users'] as List)) Map<String, dynamic>.from(u)];
      final links = _links(s);
      links['${r['added']}'] = m.id;
      await s.prefs.setString(_key, jsonEncode(links));
      if (mounted) toast(context, 'Fingerprint added for ${m.name}');
    } catch (e) {
      _error = '$e'.contains('full') ? 'The scale already stores 5 fingerprints. Remove one first.' : '$e';
    }
    if (mounted) setState(() => _enrolling = false);
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    final s = context.read<AppState>();
    if (!await confirm(context, 'Remove fingerprint?', 'Remove ${u['name']} from the scale.', ok: 'Remove')) return;
    await guarded(context, () async {
      final r = await s.deviceRequest('fingerDelete', 'fingerUsers', data: {'id': u['id']});
      _users = [for (final x in (r['users'] as List)) Map<String, dynamic>.from(x)];
      final links = _links(s)..remove('${u['id']}');
      await s.prefs.setString(_key, jsonEncode(links));
    });
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final links = _links(s);
    return GScaffold(
      appBar: AppBar(title: const Text('Fingerprint users')),
      floatingActionButton: FloatingActionButton.extended(heroTag: null, onPressed: _enrolling || _loading ? null : _add, icon: const Icon(Icons.fingerprint), label: const Text('Add fingerprint')),
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 96), children: [
        if (_enrolling)
          AppCard(
            child: Column(children: [
              const Icon(Icons.fingerprint, size: 64, color: brandBlue),
              const SizedBox(height: 8),
              Text('Place your finger on the sensor ($_step/3)', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: _step / 3, minHeight: 8),
            ]),
          ),
        if (_error != null) AppCard(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (!_loading && _users.isEmpty && _error == null) const EmptyState(icon: Icons.fingerprint, text: 'No fingerprints stored yet.'),
        if (_users.isNotEmpty)
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              for (final u in _users)
                MenuRow(
                  icon: Icons.fingerprint,
                  title: '${u['name']}',
                  subtitle: () {
                    final mid = links['${u['id']}'];
                    final m = s.members.where((x) => x.id == mid).firstOrNull;
                    return m == null ? 'Slot ${u['id']} · not linked to a profile' : 'Slot ${u['id']} · ${m.avatar} ${m.name}';
                  }(),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(u)),
                ),
            ]),
          ),
      ]),
    );
  }
}
