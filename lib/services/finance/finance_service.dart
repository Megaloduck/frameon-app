import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Finance service — live currency / crypto tracker
//
// Polls CoinGecko's free /coins/markets endpoint, which returns the current
// price, 24h change %, and a 7-day hourly sparkline in a single request and
// requires no API key.
//
//   https://api.coingecko.com/api/v3/coins/markets
//     ?vs_currency=usd&ids=bitcoin&sparkline=true&price_change_percentage=24h
//
// The service is a Riverpod family keyed by (symbol, vsCurrency) so multiple
// FinanceLayers pointing at different coins each get their own notifier and
// poll timer. The family argument is passed to the notifier's constructor.
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
    this.sparkline    = const <double>[],
    this.updatedAt,
    this.errorMessage,
  });

  bool get isUp    => change24hPct >= 0;
  bool get hasData => sparkline.length >= 2 && price > 0;

  FinanceData copyWith({
    FinanceStatus? status,
    double?        price,
    double?        previous,
    double?        change24hPct,
    List<double>?  sparkline,
    DateTime?      updatedAt,
    String?        errorMessage,
    bool           clearError = false,
  }) {
    return FinanceData(
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
  }

  /// Seeded mock data so the preview/editor always renders something even
  /// before the first network response or while offline.
  factory FinanceData.mock(String symbol, String vsCurrency) {
    final rng  = math.Random(symbol.hashCode);
    final base = 100 + rng.nextDouble() * 80000;
    final pts  = <double>[];
    double v   = base;
    for (int i = 0; i < 64; i++) {
      v += (rng.nextDouble() - 0.48) * base * 0.012;
      pts.add(v);
    }
    final first = pts.first;
    return FinanceData(
      status:       FinanceStatus.loading,
      symbol:       symbol,
      vsCurrency:   vsCurrency,
      price:        pts.last,
      previous:     pts[pts.length - 2],
      change24hPct: first == 0 ? 0 : ((pts.last - first) / first) * 100,
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
      identical(this, other) ||
      (other is FinanceKey &&
          other.symbol == symbol &&
          other.vsCurrency == vsCurrency);

  @override
  int get hashCode => Object.hash(symbol, vsCurrency);

  @override
  String toString() => 'FinanceKey($symbol/$vsCurrency)';
}

// ── Notifier ────────────────────────────────────────────────────────────────
//
// The family argument arrives via the constructor. Riverpod calls
// FinanceServiceNotifier.new(key) for each unique FinanceKey watched.

class FinanceServiceNotifier extends Notifier<FinanceData> {
  FinanceServiceNotifier(this.key);

  final FinanceKey key;

  Timer? _pollTimer;
  bool   _disposed = false;

  static const Duration _pollInterval   = Duration(seconds: 60);
  static const Duration _connectTimeout = Duration(seconds: 8);

  @override
  FinanceData build() {
    _pollTimer?.cancel();
    _disposed = false;

    ref.onDispose(() {
      _disposed = true;
      _pollTimer?.cancel();
      _pollTimer = null;
    });

    // First fetch on next microtask so [state] is set when refresh() runs.
    scheduleMicrotask(() {
      if (!_disposed) refresh();
    });

    // Periodic poll afterwards.
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!_disposed) refresh();
    });

    return FinanceData.mock(key.symbol, key.vsCurrency);
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// Manually re-fetch the latest price + sparkline.
  Future<void> refresh() async {
    if (_disposed) return;

    final symbol     = key.symbol.trim();
    final vsCurrency = key.vsCurrency.trim();

    if (symbol.isEmpty || vsCurrency.isEmpty) {
      state = state.copyWith(
        status:       FinanceStatus.error,
        errorMessage: 'Symbol or vsCurrency is empty',
      );
      return;
    }

    final url = Uri.parse(
      'https://api.coingecko.com/api/v3/coins/markets'
      '?vs_currency=$vsCurrency'
      '&ids=$symbol'
      '&sparkline=true'
      '&price_change_percentage=24h',
    );

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _connectTimeout;

      final req = await client.getUrl(url);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'Frameon/1.0');

      final res = await req.close();

      if (res.statusCode != 200) {
        state = state.copyWith(
          status:       FinanceStatus.error,
          errorMessage: 'HTTP ${res.statusCode}',
        );
        return;
      }

      final body    = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);

      if (decoded is! List || decoded.isEmpty) {
        state = state.copyWith(
          status:       FinanceStatus.error,
          errorMessage: 'No market data for "$symbol"',
        );
        return;
      }

      final entry = decoded.first;
      if (entry is! Map) {
        state = state.copyWith(
          status:       FinanceStatus.error,
          errorMessage: 'Unexpected response shape',
        );
        return;
      }

      // Current price — required.
      final priceRaw = entry['current_price'];
      if (priceRaw is! num) {
        state = state.copyWith(
          status:       FinanceStatus.error,
          errorMessage: 'Missing current_price',
        );
        return;
      }
      final double newPrice = priceRaw.toDouble();

      // 24h change — optional.
      final changeRaw = entry['price_change_percentage_24h'];
      final double change =
          changeRaw is num ? changeRaw.toDouble() : state.change24hPct;

      // Sparkline — optional, may be a Map { "price": [...] } or absent.
      List<double> spark = state.sparkline;
      final sparkObj = entry['sparkline_in_7d'];
      if (sparkObj is Map) {
        final priceList = sparkObj['price'];
        if (priceList is List) {
          final parsed = priceList
              .whereType<num>()
              .map((e) => e.toDouble())
              .toList(growable: false);
          if (parsed.length >= 2) spark = parsed;
        }
      }

      if (_disposed) return;

      state = state.copyWith(
        status:       FinanceStatus.ok,
        previous:     state.price,
        price:        newPrice,
        change24hPct: change,
        sparkline:    spark,
        updatedAt:    DateTime.now(),
        clearError:   true,
      );
    } on SocketException catch (e) {
      state = state.copyWith(
        status:       FinanceStatus.error,
        errorMessage: 'Network error: ${e.message}',
      );
    } on TimeoutException {
      state = state.copyWith(
        status:       FinanceStatus.error,
        errorMessage: 'Request timed out',
      );
    } on FormatException catch (e) {
      state = state.copyWith(
        status:       FinanceStatus.error,
        errorMessage: 'Bad JSON: ${e.message}',
      );
    } catch (e) {
      state = state.copyWith(
        status:       FinanceStatus.error,
        errorMessage: e.toString(),
      );
    } finally {
      client?.close(force: true);
    }
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

final financeServiceProvider =
    NotifierProvider.family<FinanceServiceNotifier, FinanceData, FinanceKey>(
  FinanceServiceNotifier.new,
);