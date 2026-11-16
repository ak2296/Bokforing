import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../app/pin_lock.dart';
import '../domain/company_pair.dart';

class CloudException implements Exception {
  final String message;
  const CloudException(this.message);
  @override
  String toString() => message;
}

/// The owner's answer to an order, as the customer's phone sees it.
class OrderAnswer {
  /// 'ny', 'betald', 'skickad' or 'avslagen'.
  final String status;
  final String code;
  const OrderAnswer(this.status, this.code);
}

/// Sends an activation order to the owner and collects the code that comes
/// back. It talks to Firestore over its REST interface (no extra Android
/// libraries); the customer signs in anonymously. Only the company name, the
/// org number and a hash of the pair leave the phone.
class ActivationCloud {
  /// A public identifier, not a secret: what the customer may do is decided by
  /// the rules published in Firebase (firestore.rules).
  static const apiKey = 'AIzaSyCwc-pOVdt7QD_XK04_m8DjGyxOdzZvJ-g';
  static const _project = 'quee-aktivering';
  static const _root = 'projects/$_project/databases/(default)/documents';
  static const _docs = 'https://firestore.googleapis.com/v1/$_root';
  static const trialDays = 7;
  static const keepDays = 30;
  static const _kRefresh = 'cloud_refresh';
  static const _kUid = 'cloud_uid';

  final http.Client _http;
  final LockStore _store;
  final DateTime Function() _now;
  String? _idToken;
  DateTime? _expires;

  ActivationCloud(this._store, {http.Client? client, DateTime Function()? now})
      : _http = client ?? http.Client(),
        _now = now ?? DateTime.now;

  Future<Map<String, dynamic>> _send(String method, String url, {Object? body, String? token}) async {
    final req = http.Request(method, Uri.parse(url))
      ..headers['content-type'] = 'application/json'
      ..headers['accept-charset'] = 'utf-8';
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
    } catch (_) {
      throw const CloudException('Ingen kontakt med servern. Kontrollera nätet och försök igen.');
    }
    final text = utf8.decode(res.bodyBytes);
    final json = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    if (res.statusCode >= 200 && res.statusCode < 300) return json is Map<String, dynamic> ? json : {'list': json};
    throw _CloudHttp(res.statusCode);
  }

  Future<void> _signIn() async {
    final refresh = await _store.read(_kRefresh);
    if (refresh != null) {
      try {
        final r = await _http
            .post(Uri.parse('https://securetoken.googleapis.com/v1/token?key=$apiKey'),
                headers: {'content-type': 'application/x-www-form-urlencoded'}, body: 'grant_type=refresh_token&refresh_token=$refresh')
            .timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) {
          final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          _remember(j['id_token'] as String, j['expires_in'] as String);
          await _store.write(_kRefresh, j['refresh_token'] as String);
          await _store.write(_kUid, j['user_id'] as String);
          return;
        }
      } catch (_) {
        throw const CloudException('Ingen kontakt med servern. Kontrollera nätet och försök igen.');
      }
    }
    try {
      final j = await _send('POST', 'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey', body: {'returnSecureToken': true});
      _remember(j['idToken'] as String, j['expiresIn'] as String);
      await _store.write(_kRefresh, j['refreshToken'] as String);
      await _store.write(_kUid, j['localId'] as String);
    } on _CloudHttp {
      throw const CloudException('Servern tog inte emot inloggningen. Försök igen senare.');
    }
  }

  void _remember(String token, String expiresInSeconds) {
    _idToken = token;
    _expires = _now().add(Duration(seconds: (int.tryParse(expiresInSeconds) ?? 3600) - 60));
  }

  Future<String> _token() async {
    if (_idToken == null || _expires == null || !_expires!.isAfter(_now())) await _signIn();
    return _idToken!;
  }

  Future<String> _uid() async {
    await _token();
    return (await _store.read(_kUid))!;
  }

  static String _newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static Map<String, dynamic> _s(String v) => {'stringValue': v};

  /// Sends the order. The trial starts at once when this company name and org
  /// number pair has not had one: [trialStart] is the server's time then.
  Future<({String id, DateTime? trialStart})> order(String name, String org) async {
    final pair = await CompanyPair.hash(name, org);
    final uid = await _uid();
    final id = _newId();
    final now = _now().toUtc();
    try {
      await _send('POST', '$_docs:commit', token: await _token(), body: {
        'writes': [
          {
            'update': {
              'name': '$_root/requests/$id',
              'fields': {
                'uid': _s(uid),
                'name': _s(name.trim()),
                'org': _s(org.trim()),
                'pair': _s(pair),
                'deleteAt': {'timestampValue': now.add(const Duration(days: keepDays)).toIso8601String()},
                'status': _s('ny'),
              },
            },
            'updateTransforms': [
              {'fieldPath': 'createdAt', 'setToServerValue': 'REQUEST_TIME'},
            ],
            'currentDocument': {'exists': false},
          },
        ],
      });
    } on _CloudHttp {
      throw const CloudException('Beställningen kunde inte skickas. Försök igen senare.');
    }
    return (id: id, trialStart: await _startTrial(pair, uid));
  }

  /// A second try for the same pair is refused by the rules; the phone that got
  /// the trial can still read its own start time, so a retry keeps it.
  Future<DateTime?> _startTrial(String pair, String uid) async {
    try {
      final j = await _send('POST', '$_docs:commit', token: await _token(), body: {
        'writes': [
          {
            'update': {'name': '$_root/trials/$pair', 'fields': {'uid': _s(uid)}},
            'updateTransforms': [
              {'fieldPath': 'created', 'setToServerValue': 'REQUEST_TIME'},
            ],
            'currentDocument': {'exists': false},
          },
        ],
      });
      return DateTime.tryParse(j['commitTime'] as String? ?? '')?.toLocal();
    } on _CloudHttp {
      try {
        final d = await _send('GET', '$_docs/trials/$pair', token: await _token());
        return DateTime.tryParse(((d['fields'] as Map?)?['created'] as Map?)?['timestampValue'] as String? ?? '')?.toLocal();
      } on _CloudHttp {
        return null;
      }
    }
  }

  /// What the owner has done with the order; null when it cannot be read.
  Future<OrderAnswer?> answer(String id) async {
    try {
      final d = await _send('GET', '$_docs/requests/$id', token: await _token());
      final f = (d['fields'] as Map?) ?? const {};
      String v(String k) => ((f[k] as Map?)?['stringValue'] as String?) ?? '';
      return OrderAnswer(v('status'), v('code'));
    } on _CloudHttp {
      return null;
    }
  }
}

class _CloudHttp implements Exception {
  final int status;
  const _CloudHttp(this.status);
}
