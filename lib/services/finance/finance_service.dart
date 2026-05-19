import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/device/device_controller.dart';
import '../../shared/providers/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Finance service — live currency / crypto tracker
//
// Polls CoinGecko's free /coins/markets endpoint, which returns the current
// price, the ticker symbol, 24h change %, and a 7-day hourly sparkline in a
// single request and requires no API key.
//
//   https://api.coingecko.com/api/v3/coins/markets
//     ?vs_currency=usd&ids=bitcoin&sparkline=true&price_change_percentage=24h
//
// The ticker (e.g. "BTC", "ETH") is taken directly from the API response and
// stored in FinanceData.ticker — the UI never has to ask the user for it.
//
// After every successful price refresh the service automatically syncs the
// updated data to the connected device (same pattern as SpotifyServiceNotifier).
// ─────────────────────────────────────────────────────────────────────────────

// ── Public state ────────────────────────────────────────────────────────────

enum FinanceStatus { loading, ok, error }

class FinanceData {
  final FinanceStatus status;
  final String        symbol;       // CoinGecko id, e.g. "bitcoin"
  final String        vsCurrency;   // e.g. "usd"
  final String        ticker;       // Display ticker, e.g. "BTC" (from API)
  final double        price;
  final double        previous;
  final double        change24hPct;
  final List<double>  sparkline;
  final DateTime?     updatedAt;
  final String?       errorMessage;

  const FinanceData({
    required this.status,
    required this.symbol,
    required this.vsCurrency,
    required this.ticker,
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
    String?        ticker,
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
      ticker:       ticker       ?? this.ticker,
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
      ticker:       _deriveTicker(symbol),
      price:        pts.last,
      previous:     pts[pts.length - 2],
      change24hPct: first == 0 ? 0 : ((pts.last - first) / first) * 100,
      sparkline:    pts,
      updatedAt:    DateTime.now(),
    );
  }

  // Best-effort ticker derivation used only before the first API response.
  // Once /coins/markets returns, FinanceData.ticker is overwritten with the
  // authoritative `symbol` field from the JSON.
  static String _deriveTicker(String coinId) {
    const common = <String, String>{
      'bitcoin':        'BTC',
      'ethereum':       'ETH',
      'tether':         'USDT',
      'binancecoin':    'BNB',
      'solana':         'SOL',
      'ripple':         'XRP',
      'usd-coin':       'USDC',
      'cardano':        'ADA',
      'dogecoin':       'DOGE',
      'tron':           'TRX',
      'polkadot':       'DOT',
      'avalanche-2':    'AVAX',
      'chainlink':      'LINK',
      'matic-network':  'MATIC',
      'polygon':        'MATIC',
      'polygon-pos':    'MATIC',
      'litecoin':       'LTC',
      'shiba-inu':      'SHIB',
      'uniswap':        'UNI',
      'monero':         'XMR',
      'cosmos':         'ATOM',
      'stellar':        'XLM',
      'bitcoin-cash':   'BCH',
      'near':           'NEAR',
      'aptos':          'APT',
      'arbitrum':       'ARB',
      'optimism':       'OP',
      'pepe':           'PEPE',
      'wrapped-bitcoin':'WBTC',
      'dai':            'DAI',
    };
    final mapped = common[coinId.toLowerCase()];
    if (mapped != null) return mapped;

    // Fallback: uppercase first 4 letters of the slug, stripping punctuation.
    final cleaned = coinId.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (cleaned.isEmpty) return '?';
    return cleaned.substring(0, math.min(cleaned.length, 4)).toUpperCase();
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

class FinanceServiceNotifier extends Notifier<FinanceData> {
  FinanceServiceNotifier(this.key);

  final FinanceKey key;

  Timer? _pollTimer;
  bool   _disposed = false;

  // Poll every 5 minutes — respects CoinGecko free-tier rate limits and
  // keeps the device display always up to date on a regular cycle.
  static const Duration pollInterval    = Duration(minutes: 5);
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

    scheduleMicrotask(() {
      if (!_disposed) refresh();
    });

    _pollTimer = Timer.periodic(pollInterval, (_) {
      if (!_disposed) refresh();
    });

    return FinanceData.mock(key.symbol, key.vsCurrency);
  }

  // ── Auto-sync ─────────────────────────────────────────────────────────────

  /// Pushes the freshly rendered timeline to the device after a successful
  /// price update — mirrors SpotifyServiceNotifier._autoSyncToDevice().
  void _autoSyncToDevice() {
    ref.invalidate(timelineProvider);
    final device = ref.read(deviceConnectionProvider);
    if (device.isConnected && !device.isSending) {
      ref.read(deviceConnectionProvider.notifier).sendToDevice();
    }
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    if (_disposed) return;

    final symbol     = key.symbol.trim();
    final vsCurrency = key.vsCurrency.trim();

    if (symbol.isEmpty || vsCurrency.isEmpty) {
      state = state.copyWith(
        status:       FinanceStatus.error,
        errorMessage: 'Symbol or vsCurrency is empty',
        updatedAt:    DateTime.now(),
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
          updatedAt:    DateTime.now(),
        );
        return;
      }

      final body    = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);

      if (decoded is! List || decoded.isEmpty) {
        state = state.copyWith(
          status:       FinanceStatus.error,
          errorMessage: 'Coin not found: $symbol',
          updatedAt:    DateTime.now(),
        );
        return;
      }

      final entry    = decoded.first as Map<String, dynamic>;
      final priceRaw = entry['current_price'];
      final double newPrice =
          priceRaw is num ? priceRaw.toDouble() : state.price;

      // CoinGecko returns the ticker as "symbol", e.g. "btc"); uppercase it.
      final tickerRaw = entry['symbol'];
      final String newTicker = tickerRaw is String && tickerRaw.isNotEmpty
          ? tickerRaw.toUpperCase()
          : state.ticker;

      final changeRaw = entry['price_change_percentage_24h'];
      final double change =
          changeRaw is num ? changeRaw.toDouble() : state.change24hPct;

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
        ticker:       newTicker,
        previous:     state.price,
        price:        newPrice,
        change24hPct: change,
        sparkline:    spark,
        updatedAt:    DateTime.now(),
        clearError:   true,
      );

      // Push the updated price data to the device automatically.
      _autoSyncToDevice();

    } on SocketException catch (e) {
      state = state.copyWith(
        status:       FinanceStatus.error,
        errorMessage: 'Network error: ${e.message}',
        updatedAt:    DateTime.now(),
      );
    } on TimeoutException {
      state = state.copyWith(
        status:       FinanceStatus.error,
        errorMessage: 'Request timed out',
        updatedAt:    DateTime.now(),
      );
    } on FormatException catch (e) {
      state = state.copyWith(
        status:       FinanceStatus.error,
        errorMessage: 'Bad JSON: ${e.message}',
        updatedAt:    DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        status:       FinanceStatus.error,
        errorMessage: e.toString(),
        updatedAt:    DateTime.now(),
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