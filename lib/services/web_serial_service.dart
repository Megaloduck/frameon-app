import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'package:flutter/foundation.dart';

@JS('serialBridge.isAvailable')        external bool                  _jsIsAvailable();
@JS('serialBridge.requestPort')        external JSPromise<JSBoolean>  _jsRequestPort();
@JS('serialBridge.openPort')           external JSPromise<JSAny?>     _jsOpenPort(int baud);
@JS('serialBridge.write')              external JSPromise<JSAny?>     _jsWrite(JSString data);
@JS('serialBridge.close')              external JSPromise<JSAny?>     _jsClose();
@JS('serialBridge.addLineListener')    external void _jsAddLineListener(JSFunction cb);
@JS('serialBridge.removeLineListener') external void _jsRemoveLineListener(JSFunction cb);

enum WebSerialStatus { unavailable, idle, requestingPort, connecting, connected, error }

class WebSerialMessage {
  final String text;
  final bool isOutgoing;
  final DateTime timestamp;
  const WebSerialMessage({
      required this.text, required this.isOutgoing, required this.timestamp});
}

class WebSerialService extends ChangeNotifier {
  WebSerialStatus _status = WebSerialStatus.idle;
  final List<WebSerialMessage> _log = [];
  JSFunction? _jsListenerRef;
  StreamController<String>? _lineCtrl;

  WebSerialStatus get status => _status;
  List<WebSerialMessage> get log => List.unmodifiable(_log);

  /// Broadcast stream — every subscriber gets every line simultaneously.
  Stream<String> get lineStream => _lineCtrl?.stream ?? const Stream.empty();

  bool get isAvailable {
    if (!kIsWeb) return false;
    try { return _jsIsAvailable(); } catch (_) { return false; }
  }

  Future<bool> requestPort() async {
    if (!isAvailable) { _status = WebSerialStatus.unavailable; notifyListeners(); return false; }
    _status = WebSerialStatus.requestingPort; notifyListeners();
    try {
      final granted = (await _jsRequestPort().toDart).toDart;
      if (!granted) { _status = WebSerialStatus.idle; notifyListeners(); return false; }
      _status = WebSerialStatus.connecting; notifyListeners();
      await _openPort();
      return true;
    } catch (e) {
      _status = WebSerialStatus.error;
      _addLog('Error: $e', isOutgoing: false);
      notifyListeners();
      return false;
    }
  }

  /// Sends Wi-Fi credentials using the USB command protocol WITH "id" and "data" wrapper.
  ///
  /// OLD (broken): {"cmd":"wifi","ssid":"x","password":"y"}
  ///   → usb_api.cpp reads d["data"]["ssid"] → gets nothing → "missing ssid" error
  ///   → no "id" field → response can't be matched
  ///
  /// NEW (correct): {"id":"abc123","cmd":"wifi","data":{"ssid":"x","password":"y"}}
  ///   → usb_api.cpp reads d["data"]["ssid"] → works
  ///   → response {"id":"abc123","ok":true,"data":{"ip":"..."}} is matchable
  Future<String> sendWifiCredentials(String ssid, String password) async {
    final id = _newId();
    final payload = jsonEncode({
      'id': id,
      'cmd': 'wifi',
      'data': {'ssid': ssid, 'password': password},
    });
    await _send('$payload\n');
    _addLog('→ Sent Wi-Fi credentials (SSID: $ssid)', isOutgoing: true);
    return id;
  }

  /// Requests device IP using the USB command protocol WITH "id".
  /// Waits for either:
  ///   - New JSON response: {"id":"...","ok":true,"data":{"ip":"x.x.x.x"}}
  ///   - Legacy line: "IP:x.x.x.x" (emitted by usb_api.cpp for backward compat)
  Future<String?> requestDeviceIp() async {
    final id = _newId();
    final payload = jsonEncode({
      'id': id,
      'cmd': 'get_ip',
      'data': <String, dynamic>{},
    });
    await _send('$payload\n');
    _addLog('→ Requested device IP', isOutgoing: true);
    try {
      final response = await lineStream.firstWhere((line) {
        if (line.startsWith('IP:')) return true;
        try {
          final m = jsonDecode(line) as Map<String, dynamic>;
          return m['id'] == id && m['ok'] == true;
        } catch (_) { return false; }
      }).timeout(const Duration(seconds: 20));

      String? ip;
      if (response.startsWith('IP:')) {
        ip = response.replaceFirst('IP:', '').trim();
      } else {
        try {
          final m = jsonDecode(response) as Map<String, dynamic>;
          final data = m['data'];
          if (data is Map) ip = data['ip'] as String?;
        } catch (_) {}
      }
      if (ip != null && ip.isNotEmpty) {
        _addLog('← Device IP: $ip', isOutgoing: false);
        return ip;
      }
    } catch (_) {
      _addLog('✗ Timed out waiting for IP', isOutgoing: false);
    }
    return null;
  }

  Future<void> disconnect() async {
    _removeJsListener();
    await _closeStream();
    if (kIsWeb) { try { await _jsClose().toDart; } catch (_) {} }
    _status = WebSerialStatus.idle;
    notifyListeners();
  }

  /// Public raw send — called by UsbApiService for all normal commands.
  Future<void> rawSend(String data) => _send(data);

  Future<void> _openPort() async {
    await _closeStream();
    _lineCtrl = StreamController<String>.broadcast();
    await _jsOpenPort(115200).toDart;
    _jsListenerRef = ((JSString jsLine) {
      final line = jsLine.toDart;
      final ctrl = _lineCtrl;
      if (ctrl != null && !ctrl.isClosed) ctrl.add(line);
      _addLog(line, isOutgoing: false);
    }).toJS;
    _jsAddLineListener(_jsListenerRef!);
    _status = WebSerialStatus.connected;
    _addLog('Port opened at 115200 baud', isOutgoing: false);
    notifyListeners();
  }

  Future<void> _closeStream() async {
    final ctrl = _lineCtrl;
    _lineCtrl = null;
    if (ctrl != null && !ctrl.isClosed) await ctrl.close();
  }

  Future<void> _send(String data) async {
    if (_status != WebSerialStatus.connected) throw StateError('Serial port not open');
    await _jsWrite(data.toJS).toDart;
  }

  void _removeJsListener() {
    if (_jsListenerRef != null) {
      try { _jsRemoveLineListener(_jsListenerRef!); } catch (_) {}
      _jsListenerRef = null;
    }
  }

  void _addLog(String text, {required bool isOutgoing}) {
    _log.add(WebSerialMessage(
        text: text, isOutgoing: isOutgoing, timestamp: DateTime.now()));
    if (_log.length > 300) _log.removeAt(0);
    notifyListeners();
  }

  static final _rng = Random.secure();
  static String _newId() => List.generate(6, (_) => _rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  void dispose() { disconnect(); super.dispose(); }
}
