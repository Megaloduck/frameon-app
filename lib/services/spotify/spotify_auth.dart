import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Spotify OAuth PKCE + Token Manager
// ─────────────────────────────────────────────────────────────────────────────

const String kSpotifyClientId   = 'f6ee19fca6a74377aa6f7f1d5c8bf22b';
const String kSpotifyRedirectUri = 'http://127.0.0.1:8888/callback';
const String kSpotifyScopes =
    'user-read-currently-playing user-read-playback-state user-modify-playback-state';

class SpotifyTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  const SpotifyTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 30)));
}

class SpotifyAuth {
  SpotifyTokens? _tokens;
  bool get isAuthorized => _tokens != null && !_tokens!.isExpired;

  // ── PKCE ─────────────────────────────────────────────────────────────────

  static String _verifier() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _challenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static String _state() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  // ── Authorize ─────────────────────────────────────────────────────────────

  Future<bool> authorize() async {
    final verifier  = _verifier();
    final challenge = _challenge(verifier);
    final state     = _state();

    final uri = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id':             kSpotifyClientId,
      'response_type':         'code',
      'redirect_uri':          kSpotifyRedirectUri,
      'code_challenge_method': 'S256',
      'code_challenge':        challenge,
      'state':                 state,
      'scope':                 kSpotifyScopes,
    });

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open browser for Spotify login');
    }

    final code = await _waitForCallback(expectedState: state);
    if (code == null) return false;
    return _exchangeCode(code, verifier);
  }

  Future<String?> _waitForCallback({required String expectedState}) async {
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
      final completer = Completer<String?>();

      server.listen((req) async {
        final params = req.uri.queryParameters;
        final html = params['error'] == null && params['state'] == expectedState
            ? _successHtml
            : _errorHtml;
        req.response
          ..statusCode  = 200
          ..headers.contentType = ContentType.html
          ..write(html);
        await req.response.close();

        if (params['error'] != null ||
            params['state'] != expectedState ||
            params['code'] == null) {
          if (!completer.isCompleted) completer.complete(null);
        } else {
          if (!completer.isCompleted) completer.complete(params['code']);
        }
      });

      return await completer.future
          .timeout(const Duration(minutes: 5), onTimeout: () => null);
    } finally {
      await server?.close(force: true);
    }
  }

  Future<bool> _exchangeCode(String code, String verifier) async {
    final resp = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type':    'authorization_code',
        'code':          code,
        'redirect_uri':  kSpotifyRedirectUri,
        'client_id':     kSpotifyClientId,
        'code_verifier': verifier,
      },
    );
    if (resp.statusCode != 200) return false;
    _storeTokens(jsonDecode(resp.body) as Map<String, dynamic>);
    return true;
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<bool> refreshIfNeeded() async {
    if (_tokens == null) return false;
    if (!_tokens!.isExpired) return true;
    final resp = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type':    'refresh_token',
        'refresh_token': _tokens!.refreshToken,
        'client_id':     kSpotifyClientId,
      },
    );
    if (resp.statusCode != 200) return false;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    // refresh_token may not be returned on every refresh — keep old one
    if (!json.containsKey('refresh_token')) {
      json['refresh_token'] = _tokens!.refreshToken;
    }
    _storeTokens(json);
    return true;
  }

  void _storeTokens(Map<String, dynamic> json) {
    _tokens = SpotifyTokens(
      accessToken:  json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt:
          DateTime.now().add(Duration(seconds: json['expires_in'] as int)),
    );
  }

  Future<String?> get validAccessToken async {
    if (_tokens == null) return null;
    final ok = await refreshIfNeeded();
    return ok ? _tokens!.accessToken : null;
  }

  void clear() => _tokens = null;
}

// ── HTML pages shown in the browser after OAuth ───────────────────────────

const _successHtml = '''<!DOCTYPE html>
<html>
<head><title>Frameon — Spotify Connected</title>
<style>
  body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;
       display:flex;align-items:center;justify-content:center;
       height:100vh;margin:0;background:#111;}
  .box{text-align:center;color:#fff;max-width:320px;}
  h1{color:#1DB954;font-size:2rem;margin-bottom:8px;}
  p{color:#aaa;margin:4px 0;}
  .badge{display:inline-block;background:#1DB954;color:#fff;
         border-radius:999px;padding:4px 14px;font-size:13px;margin-top:16px;}
</style></head>
<body><div class="box">
  <div style="font-size:3rem">🎵</div>
  <h1>Connected!</h1>
  <p>Spotify is now linked to Frameon.</p>
  <p style="color:#888;font-size:13px">You can close this tab.</p>
  <div class="badge">✓ Authorization complete</div>
</div></body></html>''';

const _errorHtml = '''<!DOCTYPE html>
<html>
<head><title>Frameon — Spotify Error</title>
<style>
  body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;
       display:flex;align-items:center;justify-content:center;
       height:100vh;margin:0;background:#111;}
  .box{text-align:center;color:#fff;}
  h1{color:#ff4444;}p{color:#aaa;}
</style></head>
<body><div class="box">
  <h1>Authorization Failed</h1>
  <p>Something went wrong. Please try again in Frameon.</p>
</div></body></html>''';