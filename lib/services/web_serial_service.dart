import 'dart:async';
import 'package:flutter/foundation.dart';

// Stub for non-web platforms — the web implementation uses JS interop
// On desktop we fall back to network scan / manual IP entry

enum WebSerialStatus {
  unavailable,  // Browser doesn't support Web Serial API
  idle,
  requestingPort,
  connecting,
  connected,
  error,
}

class WebSerialMessage {
  final String text;
  final bool isOutgoing;
  final DateTime timestamp;

  const WebSerialMessage({
    required this.text,
    required this.isOutgoing,
    required this.timestamp,
  });
}

/// Abstracts Web Serial communication for ESP32 Wi-Fi provisioning.
/// On web: uses window.navigator.serial (Web Serial API).
/// On desktop: returns [WebSerialStatus.unavailable] — user must enter IP manually.
class WebSerialService extends ChangeNotifier {
  WebSerialStatus _status = WebSerialStatus.idle;
  final List<WebSerialMessage> _log = [];
  StreamController<String>? _lineController;
  Stream<String>? _lines;

  WebSerialStatus get status => _status;
  List<WebSerialMessage> get log => List.unmodifiable(_log);
  bool get isAvailable => kIsWeb; // Web Serial only available in browser

  /// Request a serial port from the user (triggers browser permission dialog).
  Future<bool> requestPort() async {
    if (!kIsWeb) {
      _status = WebSerialStatus.unavailable;
      notifyListeners();
      return false;
    }

    _status = WebSerialStatus.requestingPort;
    notifyListeners();

    try {
      // JS interop call — implemented in web/serial_interop.js
      // Returns true if user selected a port
      final granted = await _jsRequestPort();
      if (granted) {
        _status = WebSerialStatus.connecting;
        notifyListeners();
        await _openPort();
        return true;
      } else {
        _status = WebSerialStatus.idle;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = WebSerialStatus.error;
      _addLog('Error: $e', isOutgoing: false);
      notifyListeners();
      return false;
    }
  }

  /// Send Wi-Fi credentials to ESP32 over serial.
  /// ESP32 firmware reads JSON: {"ssid":"...","password":"..."}
  Future<void> sendWifiCredentials(String ssid, String password) async {
    final payload = '{"cmd":"wifi","ssid":"$ssid","password":"$password"}\n';
    await _send(payload);
    _addLog('Sent Wi-Fi credentials for SSID: $ssid', isOutgoing: true);
  }

  /// Request the device IP from ESP32 after it connects.
  Future<String?> requestDeviceIp() async {
    await _send('{"cmd":"get_ip"}\n');
    // Listen for response line starting with "IP:"
    try {
      final response = await _lines!
          .firstWhere((l) => l.startsWith('IP:'))
          .timeout(const Duration(seconds: 15));
      return response.replaceFirst('IP:', '').trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> disconnect() async {
    if (!kIsWeb) return;
    await _jsClosePort();
    _status = WebSerialStatus.idle;
    _lineController?.close();
    _lineController = null;
    _lines = null;
    notifyListeners();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  Future<void> _openPort() async {
    // Baud rate 115200 — matches ESP32 Serial.begin(115200)
    await _jsOpenPort(115200);
    _lineController = StreamController<String>.broadcast();
    _lines = _lineController!.stream;
    _status = WebSerialStatus.connected;
    _startReading();
    notifyListeners();
  }

  void _startReading() {
    _jsReadLines().listen(
      (line) {
        _addLog(line, isOutgoing: false);
        _lineController?.add(line);
      },
      onError: (e) {
        _status = WebSerialStatus.error;
        notifyListeners();
      },
      onDone: () {
        _status = WebSerialStatus.idle;
        notifyListeners();
      },
    );
  }

  Future<void> _send(String data) async {
    if (_status != WebSerialStatus.connected) {
      throw StateError('Serial port not connected');
    }
    await _jsWriteSerial(data);
  }

  void _addLog(String text, {required bool isOutgoing}) {
    _log.add(WebSerialMessage(
      text: text,
      isOutgoing: isOutgoing,
      timestamp: DateTime.now(),
    ));
    if (_log.length > 200) _log.removeAt(0);
    notifyListeners();
  }

  // ── JS interop stubs (implemented in web/serial_interop.js) ─────────────
  // These are replaced by dart:js_interop calls on web.

  Future<bool> _jsRequestPort() async {
    // Replaced by JS interop — see web/serial_interop.js
    return false;
  }

  Future<void> _jsOpenPort(int baudRate) async {}

  Future<void> _jsClosePort() async {}

  Future<void> _jsWriteSerial(String data) async {}

  Stream<String> _jsReadLines() => const Stream.empty();
}
