import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../../../../engine/renderer/font_organizer.dart';
import '../../../../engine/scene/layer.dart';
import '../../../../services/finance/finance_service.dart';
import '../../../../shared/providers/providers.dart';
import 'toolbox_shared.dart';
import '../ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FinanceToolboxLeft — symbol, label, font, vs-currency, colors.
// ─────────────────────────────────────────────────────────────────────────────

class FinanceToolboxLeft extends ConsumerWidget {
  final FinanceLayer layer;
  final SceneNotifier n;
  const FinanceToolboxLeft({super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(
      financeServiceProvider(FinanceKey(layer.symbol, layer.vsCurrency)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status pill
        _StatusPill(data: data),
        const SizedBox(height: 10),

        const TbLabel('Coin (CoinGecko id)'),
        const SizedBox(height: 4),
        TbTextField(
          value: layer.symbol,
          onSubmitted: (v) =>
              n.updateLayer(layer.copyWith(symbol: v.trim().toLowerCase())),
        ),
        const SizedBox(height: 8),

        const TbLabel('Vs Currency'),
        const SizedBox(height: 4),
        _VsCurrencyDropdown(
          current: layer.vsCurrency,
          onChanged: (v) => n.updateLayer(layer.copyWith(vsCurrency: v)),
        ),
        const SizedBox(height: 10),

        const TbLabel('Font Style'),
        const SizedBox(height: 4),
        TbDropdown<LedFontId>(
          values: LedFontId.values,
          current: layer.fontId,
          onChange: (v) => n.updateLayer(layer.copyWith(fontId: v)),
          labelFor: (v) => LedFontLibrary.get(v).name,
        ),
        const SizedBox(height: 12),

        const TbLabel('Colors'),
        const SizedBox(height: 6),
        _ColorRow(
            label: 'Symbol',
            color: layer.symbolColor,
            onChanged: (c) => n.updateLayer(layer.copyWith(symbolColor: c))),
        const SizedBox(height: 6),
        _ColorRow(
            label: 'Up',
            color: layer.upColor,
            onChanged: (c) => n.updateLayer(layer.copyWith(upColor: c))),
        const SizedBox(height: 6),
        _ColorRow(
            label: 'Down',
            color: layer.downColor,
            onChanged: (c) => n.updateLayer(layer.copyWith(downColor: c))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FinanceToolboxRight — layout, toggles, decimals, refresh.
// ─────────────────────────────────────────────────────────────────────────────

class FinanceToolboxRight extends ConsumerWidget {
  final FinanceLayer layer;
  final SceneNotifier n;
  const FinanceToolboxRight({super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tbGreenDropdown<FinanceLayout>(
          context,
          FinanceLayout.values,
          layer.layout,
          (v) => n.updateLayer(layer.copyWith(layout: v)),
        ),
        const SizedBox(height: 12),

        TbToggleRow(
          label: 'Show symbol',
          value: layer.showSymbol,
          onChanged: (v) => n.updateLayer(layer.copyWith(showSymbol: v)),
        ),
        TbToggleRow(
          label: 'Show 24h %',
          value: layer.showChangePercent,
          onChanged: (v) => n.updateLayer(layer.copyWith(showChangePercent: v)),
        ),
        const SizedBox(height: 12),

        const TbLabel('Decimals'),
        Slider(
          value: layer.decimals.toDouble(),
          min: 0,
          max: 6,
          divisions: 6,
          label: '${layer.decimals}',
          onChanged: (v) =>
              n.updateLayer(layer.copyWith(decimals: v.round())),
        ),
        const SizedBox(height: 8),

        // Manual refresh
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Refresh now',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            onPressed: () => ref
                .read(financeServiceProvider(
                        FinanceKey(layer.symbol, layer.vsCurrency))
                    .notifier)
                .refresh(),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status pill
// ─────────────────────────────────────────────────────────────────────────────

class _StatusPill extends StatefulWidget {
  final FinanceData data;
  const _StatusPill({required this.data});

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Tick once per second so the countdown updates in real time.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Seconds remaining until the next scheduled refresh, or null if we don't
  /// yet have a reference timestamp.
  int? _countdownSeconds() {
    final updatedAt = widget.data.updatedAt;
    if (updatedAt == null) return null;
    final intervalSec = FinanceServiceNotifier.pollInterval.inSeconds;
    final elapsedSec  = DateTime.now().difference(updatedAt).inSeconds;
    final remaining   = intervalSec - elapsedSec;
    return remaining.clamp(0, intervalSec);
  }

  /// Format seconds as m:ss for intervals >= 60 s, plain Xs otherwise.
  static String _formatCountdown(int seconds) {
    if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final (label, color) = switch (data.status) {
      FinanceStatus.ok      => ('Live',      const Color(0xFF21C32C)),
      FinanceStatus.loading => ('Loading…',  const Color(0xFFEF9F27)),
      FinanceStatus.error   => ('Offline',   const Color(0xFFE05656)),
    };
    final priceStr = data.price > 0
        ? data.price.toStringAsFixed(data.price >= 100 ? 2 : 4)
        : '—';
    final changeStr = data.hasData
        ? '${data.isUp ? '+' : ''}${data.change24hPct.toStringAsFixed(2)}%'
        : '';
    final cd = _countdownSeconds();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: const BorderRadius.all(kRadiusMd),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (cd != null) ...[
            const SizedBox(width: 6),
            Text(
              // e.g. "· syncs in 4:32" or "· syncs in 8s"
              '· syncs in ${_formatCountdown(cd)}',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: color.withOpacity(0.75),
              ),
            ),
          ],
          const Spacer(),
          Text(
            '${data.vsCurrency.toUpperCase()} $priceStr',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (changeStr.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              changeStr,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: data.isUp
                    ? const Color(0xFF21C32C)
                    : const Color(0xFFE05656),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color row (mirrors clock_toolbox _ColorRow style)
// ─────────────────────────────────────────────────────────────────────────────

class _ColorRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;
  const _ColorRow(
      {required this.label, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          tbColorBtn(context, color, onChanged),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(fontSize: 11, color: context.tTextMuted)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Vs-currency dropdown (subset of common quote currencies)
// ─────────────────────────────────────────────────────────────────────────────

class _VsCurrencyDropdown extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _VsCurrencyDropdown({required this.current, required this.onChanged});

  static const _options = <String>[
    'usd', 'eur', 'gbp', 'jpy', 'cny', 'krw', 'inr', 'aud', 'cad', 'chf',
    'btc', 'eth',
  ];

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: kGreen.withOpacity(0.1),
          border: Border.all(color: kGreen.withOpacity(0.5)),
          borderRadius: const BorderRadius.all(kRadiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _options.contains(current) ? current : 'usd',
            isExpanded: true,
            isDense: true,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: kGreen),
            dropdownColor: context.tSurface,
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: kGreen),
            items: _options
                .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(v.toUpperCase()),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
}