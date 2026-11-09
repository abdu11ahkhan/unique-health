import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final String message;
  final int code;
  ApiException(this.message, [this.code = 1]);
  @override
  String toString() => message;
}

/// Thin REST client for the local backend. Handles the {code,msg,data}
/// envelope, token storage and one automatic refresh on 401.
class Api {
  final SharedPreferences prefs;
  String baseUrl;
  String? _access;
  String? _refresh;
  void Function()? onSessionExpired;

  Api(this.prefs, this.baseUrl) {
    _access = prefs.getString('access');
    _refresh = prefs.getString('refresh');
  }

  bool get hasSession => _refresh != null;

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString('baseUrl', baseUrl);
  }

  Future<void> saveTokens(String access, String refresh) async {
    _access = access;
    _refresh = refresh;
    await prefs.setString('access', access);
    await prefs.setString('refresh', refresh);
  }

  Future<void> clearTokens() async {
    _access = null;
    _refresh = null;
    await prefs.remove('access');
    await prefs.remove('refresh');
  }

  Uri _uri(String path, Map<String, dynamic>? query) => Uri.parse('$baseUrl$path').replace(
        queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
      );

  Future<dynamic> get(String path, {Map<String, dynamic>? query, bool auth = true}) =>
      _send('GET', path, null, query, auth);

  Future<dynamic> post(String path, [Map<String, dynamic>? body, bool auth = true]) =>
      _send('POST', path, body ?? {}, null, auth);

  Future<dynamic> _send(String method, String path, Map<String, dynamic>? body,
      Map<String, dynamic>? query, bool auth,
      {bool retried = false}) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (auth && _access != null) headers['Access-Token'] = _access!;
    http.Response res;
    try {
      final uri = _uri(path, query);
      final req = method == 'GET'
          ? http.get(uri, headers: headers)
          : http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      res = await req.timeout(const Duration(seconds: 10));
    } catch (_) {
      throw ApiException('Cannot reach server at $baseUrl. Is the backend running?', -1);
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Bad response from server (${res.statusCode})', res.statusCode);
    }
    final code = (j['code'] as num?)?.toInt() ?? -1;
    if (code == 401 && auth && !retried && _refresh != null) {
      if (await _tryRefresh()) {
        return _send(method, path, body, query, auth, retried: true);
      }
      onSessionExpired?.call();
      throw ApiException('Session expired, please sign in again', 401);
    }
    if (code != 0) {
      if (code == 401) onSessionExpired?.call();
      throw ApiException((j['msg'] ?? 'Request failed').toString(), code);
    }
    return j['data'];
  }

  Future<bool> _tryRefresh() async {
    try {
      final res = await http
          .post(_uri('/app/user/refreshToken', null),
              headers: {'content-type': 'application/json'}, body: jsonEncode({'refreshToken': _refresh}))
          .timeout(const Duration(seconds: 10));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['code'] != 0) return false;
      await saveTokens(j['data']['accessToken'], j['data']['refreshToken']);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// WebSocket URL of the virtual-scale hub on the same server.
  String get wsUrl => baseUrl.replaceFirst(RegExp(r'^http'), 'ws') + '/ws';
}
