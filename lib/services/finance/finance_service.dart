import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Finance service — live currency / crypto tracker
//
// Polls the public CoinGecko endpoint /coins/markets, which returns the
// current price, 24h change %, and a 7-day hourly sparkline in a single
// request and requires no API key.
//
//   https://api.coingecko.com/api/v3/coins/markets
//     ?vs_currency=usd&ids=bitcoin&sparkline=true
//
// The service is keyed by (symbol, vsCurrency) so multiple FinanceLayers
// pointing at different coins share one notifier each via a family.
// The renderer reads [FinanceData] from this provider every frame.
// ─────────────────────────────────────────────────────────────────────────────

// ── Public state ────────────────────────────────────────────────────────────

enum FinanceStatus { loading, ok, error }

class FinanceData {
  final FinanceStatus status;
  final String        symbol;       // CoinGecko id, e.g. "bitcoin"
  final String        vsCurrency;   // e.g. "usd"
  final double        price;        // current price
  final double        previous;     // last polled price (for tick direction)
  final double        change24hPct; // signed % over 24h
  final List<double>  sparkline;    // historical points, oldest → newest
  final DateTime?     updatedAt;
  final String?       errorMessage;

  const FinanceData({
    required this.status,
    required this.symbol,
    required this.vsCurrency,
    this.price        = 0,
    this.previous     = 0,
    this.change24hPct = 0,
    this.sparkline    = const [],
    this.updatedAt,
    this.errorMessage,
  });

  bool get isUp   => change24hPct >= 0;
  bool get hasData => sparkline.isNotEmpty && price > 0;

  FinanceData copyWith({
    FinanceStatus? status,
    double?        price,
    double?        previous,
    double?        change24hPct,
    List<double>?  sparkline,
    DateTime?      updatedAt,
    String?        errorMessage,
    bool           clearError = false,
  }) =>
      FinanceData(
        status:       status       ?? this.status,
        symbol:       symbol,
        vsCurrency:   vsCurrency,
        price:        price        ?? this.price,
        previous:     previous     ?? this.previous,
        change24hPct: change24hPct ?? this.change24hPct,
        sparkline:    sparkline    ?? this.sparkline,
        updatedAt:    updatedAt    ?? this.updatedAt,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );

  /// Seeded mock data so the preview/editor always renders something even
  /// before the first network response or while offline.
  factory FinanceData.mock(String symbol, String vsCurrency) {
    final rng = math.Random(symbol.hashCode);
    final base = 60000 + rng.nextDouble() * 8000;
    final pts = <double>[];
    double v = base;
    for (int i = 0; i < 64; i++) {
      v += (rng.nextDouble() - 0.48) * base * 0.012;
      pts.add(v);
    }
    return FinanceData(
      status:       FinanceStatus.loading,
      symbol:       symbol,
      vsCurrency:   vsCurrency,
      price:        pts.last,
      previous:     pts[pts.length - 2],
      change24hPct: ((pts.last - pts.first) / pts.first) * 100,
      sparkline:    pts,
      updatedAt:    DateTime.now(),
    );
  }
}

// ── Provider key ────────────────────────────────────────────────────────────

class FinanceKey {
  final String symbol;
  final String vsCurrency;
  const FinanceKey(this.symbol, this.vsCurrency);

  @override
  bool operator ==(Object other) =>
      other is FinanceKey &&
      other.symbol == symbol &&
      other.vsCurrency == vsCurrency;

  @override
  int get hashCode => Object.hash(symbol, vsCurrency);
}

// ── Notifier ────────────────────────────────────────────────────────────────

class FinanceServiceNotifier
    extends FamilyNotifier<FinanceData, FinanceKey> {
  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 60);

  @override
  FinanceData build(FinanceKey arg) {
    _start(arg);
    ref.onDispose(() => _pollTimer?.cancel());
    return FinanceData.mock(arg.symbol, arg.vsCurrency);
  }

  void _start(FinanceKey key) {
    _pollTimer?.cancel();
    // Fire immediately, then poll on interval.
    Future<void>.microtask(() => refresh());
    _pollTimer = Timer.periodic(_pollInterval, (_) => refresh());
  }

  Future<void> refresh() async {
    final url = Uri.parse(
      'https://api.coingecko.com/api/v3/coins/markets'
      '?vs_currency=${state.vsCurrency}'
      '&ids=${state.symbol}'
      '&sparkline=true'
      '&price_change_percentage=24h',
    );

    HttpClient? http;
    try {
      http = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await http.getUrl(url);
      final res = await req.close();
      if (res.statusCode != 200) {
        state = state.copyWith(
          status:       FinanceStatus.error,
          errorMessage: 'HTTP ${res.statusCode}',
        );
        return;
      }
      final body = await res.transform(utf8.decoder).join();
      final List<dynamic> arr = jsonDecode(body) as List<dynamic>;
      if (arr.isEmpty) {
        state = state.copyWith(
          status:       FinanceStatus.error,
          errorMessage: 'No data for ${state.symbol}',
        );
        return;
      }
      final m = arr.first as Map<String, dynamic>;
      final price  = (m['current_price'] as num).toDouble();
      final change = ((m['price_change_percentage_24h'] as num?) ?? 0).toDouble();
      final spark  = ((m['sparkline_in_7d'] as Map?)?['price'] as List?)
              ?.cast<num>()
              .map((e) => e.toDouble())
              .toList() ??
          state.sparkline;

      state = state.copyWith(
        status:       FinanceStatus.ok,
        previous:     state.price == 0 ? price : state.price,
        price:        price,
        change24hPct: change,
        sparkline:    spark,
        updatedAt:    DateTime.now(),
        clearError:   true,
      );
    } catch (e) {
      state = state.copyWith(
        status:       FinanceStatus.error,
        errorMessage: e.toString(),
      );
    } finally {
      http?.close(force: true);
    }
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

final financeServiceProvider =
    NotifierProvider.family<FinanceServiceNotifier, FinanceData, FinanceKey>(
  FinanceServiceNotifier.new,
);