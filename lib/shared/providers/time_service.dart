import 'dart:async';
import 'package:ntp/ntp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TimeService extends Notifier<DateTime> {
  Timer? _syncTimer;
  static const _syncInterval = Duration(seconds: 30);

  @override
  DateTime build() => DateTime.now();

  Future<void> initialize() async {
    await syncWithNtp();
    _syncTimer = Timer.periodic(_syncInterval, (_) => syncWithNtp());
  }

  Future<void> syncWithNtp() async {
    try {
      final ntpTime = await NTP.now();
      state = ntpTime;
    } catch (e) {
      // Fallback to system time with drift tracking
      state = DateTime.now();
    }
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}

final timeServiceProvider = NotifierProvider<TimeService, DateTime>(
  TimeService.new,
);