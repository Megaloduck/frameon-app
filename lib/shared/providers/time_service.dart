import 'dart:async';
import 'package:ntp/ntp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TimeService extends Notifier<DateTime> {
  Timer? _tickTimer;
  Timer? _syncTimer;
  Duration _ntpOffset = Duration.zero;

  static const _syncInterval = Duration(minutes: 5);
  static const _tickInterval = Duration(seconds: 1);

  @override
  DateTime build() => DateTime.now();

  Future<void> initialize() async {
    // Start ticking immediately with system time so the clock shows something
    _startTicking();
    // Sync with NTP to get the offset
    await _syncWithNtp();
    // Re-sync periodically to correct drift
    _syncTimer = Timer.periodic(_syncInterval, (_) => _syncWithNtp());
  }

  void _startTicking() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(_tickInterval, (_) {
      state = DateTime.now().add(_ntpOffset);
    });
  }

  Future<void> _syncWithNtp() async {
    try {
      final int offsetMs = await NTP.getNtpOffset();
      _ntpOffset = Duration(milliseconds: offsetMs);
      state = DateTime.now().add(_ntpOffset);
    } catch (_) {
      // NTP unavailable — keep using system time
      _ntpOffset = Duration.zero;
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _syncTimer?.cancel();
  }
}

final timeServiceProvider = NotifierProvider<TimeService, DateTime>(
  TimeService.new,
);