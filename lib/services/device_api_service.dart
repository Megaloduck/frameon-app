import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/device_state.dart';

/// Communicates with the ESP32 over Wi-Fi.
/// REST for commands, WebSocket for live state updates.
class DeviceApiService extends ChangeNotifier {
  String?             _baseUrl;
  WebSocketChannel?   _wsChannel;
  StreamSubscription? _wsSub;
  DeviceState         _deviceState = const DeviceState();
  Timer?              _pingTimer;

  DeviceState get deviceState => _deviceState;
  String?     get baseUrl     => _baseUrl;

  // ── Connection ────────────────────────────────────────────────────────

  Future<bool> connect(String ip) async {
    _baseUrl = 'http://$ip';
    _updateState(_deviceState.copyWith(
      connectionStatus: ConnectionStatus.connecting,
      deviceIp: ip,
    ));

    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/info'))
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final info = jsonDecode(res.body) as Map<String, dynamic>;

        final rawMode = info['mode'];
        final AppMode mode;
        if (rawMode is int) {
          mode = AppMode.values[rawMode.clamp(0, AppMode.values.length - 1)];
        } else {
          mode = _parseModeFromString(rawMode as String? ?? 'clock');
        }

        _updateState(_deviceState.copyWith(
          connectionStatus: ConnectionStatus.connected,
          deviceName: info['name'] as String? ?? 'Matrix Panel',
          activeMode: mode,
        ));
        _connectWebSocket(ip);
        _startPingTimer();
        return true;
      }
    } catch (e) {
      debugPrint('DeviceApiService.connect error: $e');
    }

    _updateState(_deviceState.copyWith(
      connectionStatus: ConnectionStatus.disconnected,
      errorMessage: 'Could not reach device at $ip',
    ));
    return false;
  }

  void disconnect() {
    _pingTimer?.cancel();
    _wsSub?.cancel();
    _wsChannel?.sink.close();
    _wsChannel = null;
    _baseUrl   = null;
    _updateState(const DeviceState());
  }

  // ── Core commands ─────────────────────────────────────────────────────

  Future<void> setMode(AppMode mode) async {
    await postJson('/api/mode', {'mode': mode.name});
    _updateState(_deviceState.copyWith(activeMode: mode));
  }

  Future<void> setBrightness(int value) async =>
      postJson('/api/brightness', {'value': value});

  Future<void> pushSpotifyState({
    required String trackName,
    required String artistName,
    required bool isPlaying,
    Uint8List? albumArtJpeg,
  }) async {
    final body = <String, dynamic>{
      'track': trackName, 'artist': artistName, 'playing': isPlaying,
    };
    if (albumArtJpeg != null) body['art'] = base64Encode(albumArtJpeg);
    await postJson('/api/spotify/state', body);
  }

  Future<void> pomodoroCommand(String cmd) async =>
      postJson('/api/pomodoro/cmd', {'cmd': cmd});

  Future<void> selectGif(String filename) async =>
      postJson('/api/gif/select', {'file': filename});

  // ── WebSocket ─────────────────────────────────────────────────────────

  void _connectWebSocket(String ip) {
    _wsChannel = WebSocketChannel.connect(Uri.parse('ws://$ip/ws'));
    _wsSub = _wsChannel!.stream.listen(
      (data) => _handleWsMessage(data as String),
      onError: (_) => _handleWsDisconnect(),
      onDone: _handleWsDisconnect,
    );
  }

  void _handleWsMessage(String raw) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final rawMode = msg['mode'];
      if (rawMode != null) {
        final AppMode mode;
        if (rawMode is int) {
          mode = AppMode.values[rawMode.clamp(0, AppMode.values.length - 1)];
        } else {
          mode = _parseModeFromString(rawMode as String);
        }
        _updateState(_deviceState.copyWith(activeMode: mode));
      }
    } catch (_) {}
  }

  void _handleWsDisconnect() {
    if (_deviceState.isConnected) {
      _updateState(_deviceState.copyWith(
        connectionStatus: ConnectionStatus.disconnected,
        errorMessage: 'Lost connection to device',
      ));
    }
  }

  // ── Ping ──────────────────────────────────────────────────────────────

  void _startPingTimer() {
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_baseUrl == null) return;
      try {
        await http
            .get(Uri.parse('$_baseUrl/api/ping'))
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        _handleWsDisconnect();
        _pingTimer?.cancel();
      }
    });
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getJson(String path) async {
    if (_baseUrl == null) return null;
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl$path'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('GET $path error: $e');
    }
    return null;
  }

  /// Posts JSON and returns true on HTTP 200.
  /// Returns false (never throws) on network error or non-200 response.
  /// TransportService._run() depends on this not throwing.
  Future<bool> postJson(String path, Map<String, dynamic> body) async {
    if (_baseUrl == null) return false;
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('POST $path error: $e');
      return false; // never rethrow — callers check the bool
    }
  }

  AppMode _parseModeFromString(String s) => AppMode.values.firstWhere(
        (m) => m.name == s,
        orElse: () => AppMode.clock,
      );

  void _updateState(DeviceState newState) {
    _deviceState = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
