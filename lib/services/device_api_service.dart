import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/device_state.dart';

/// Communicates with the ESP32 over Wi-Fi.
/// REST for commands, WebSocket for live state updates.
class DeviceApiService extends ChangeNotifier {
  String? _baseUrl;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;
  DeviceState _deviceState = const DeviceState();
  Timer? _pingTimer;

  DeviceState get deviceState => _deviceState;

  // ── Connection ────────────────────────────────────────────────────────────

  Future<bool> connect(String ip) async {
    _baseUrl = 'http://$ip';
    _updateState(_deviceState.copyWith(
      connectionStatus: ConnectionStatus.connecting,
      deviceIp: ip,
    ));

    try {
      // Ping the device
      final res = await http
          .get(Uri.parse('$_baseUrl/api/info'))
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final info = jsonDecode(res.body) as Map<String, dynamic>;
        _updateState(_deviceState.copyWith(
          connectionStatus: ConnectionStatus.connected,
          deviceName: info['name'] as String? ?? 'Matrix Panel',
          activeMode: _parseModeFromString(info['mode'] as String? ?? 'clock'),
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
    _baseUrl = null;
    _updateState(const DeviceState());
  }

  // ── Mode switching ────────────────────────────────────────────────────────

  Future<void> setMode(AppMode mode) async {
    await _post('/api/mode', {'mode': mode.name});
    _updateState(_deviceState.copyWith(activeMode: mode));
  }

  // ── Brightness ────────────────────────────────────────────────────────────

  Future<void> setBrightness(int value) async {
    await _post('/api/brightness', {'value': value});
  }

  // ── Clock ─────────────────────────────────────────────────────────────────

  Future<void> setClockFormat(bool is24h) async {
    await _post('/api/clock/config', {'format24h': is24h});
  }

  Future<void> setClockTimezone(String tz) async {
    await _post('/api/clock/config', {'timezone': tz});
  }

  // ── Spotify ───────────────────────────────────────────────────────────────

  Future<void> pushSpotifyState({
    required String trackName,
    required String artistName,
    required bool isPlaying,
    Uint8List? albumArtJpeg, // 32x64 pixels, sent as base64
  }) async {
    final body = <String, dynamic>{
      'track': trackName,
      'artist': artistName,
      'playing': isPlaying,
    };
    if (albumArtJpeg != null) {
      body['art'] = base64Encode(albumArtJpeg);
    }
    await _post('/api/spotify/state', body);
  }

  Future<void> spotifyCommand(String cmd) async {
    // cmd: 'play' | 'pause' | 'next' | 'prev'
    await _post('/api/spotify/cmd', {'cmd': cmd});
  }

  // ── Pomodoro ──────────────────────────────────────────────────────────────

  Future<void> pomodoroCommand(String cmd) async {
    // cmd: 'start' | 'pause' | 'reset'
    await _post('/api/pomodoro/cmd', {'cmd': cmd});
  }

  Future<void> setPomodoroConfig({
    required int workMinutes,
    required int breakMinutes,
  }) async {
    await _post('/api/pomodoro/config', {
      'work': workMinutes,
      'break': breakMinutes,
    });
  }

  // ── GIF ───────────────────────────────────────────────────────────────────

  Future<void> uploadGif(Uint8List bytes, String filename) async {
    if (_baseUrl == null) return;
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/gif/upload'),
    );
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    ));
    await request.send();
  }

  Future<List<String>> listGifs() async {
    final res = await _get('/api/gif/list');
    if (res == null) return [];
    return (res['files'] as List).cast<String>();
  }

  Future<void> selectGif(String filename) async {
    await _post('/api/gif/select', {'file': filename});
  }

  // ── WebSocket ─────────────────────────────────────────────────────────────

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
      if (msg['mode'] != null) {
        _updateState(_deviceState.copyWith(
          activeMode: _parseModeFromString(msg['mode'] as String),
        ));
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

  // ── Ping ──────────────────────────────────────────────────────────────────

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

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _get(String path) async {
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

  Future<void> _post(String path, Map<String, dynamic> body) async {
    if (_baseUrl == null) return;
    try {
      await http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('POST $path error: $e');
    }
  }

  AppMode _parseModeFromString(String s) {
    return AppMode.values.firstWhere(
      (m) => m.name == s,
      orElse: () => AppMode.clock,
    );
  }

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
