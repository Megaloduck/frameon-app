import 'package:flutter/material.dart';

import '../../../../engine/renderer/font_organizer.dart';
import '../../../../engine/scene/layer.dart';
import '../../../../shared/providers/providers.dart';
import 'toolbox_shared.dart';
import '../ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ClockToolboxLeft — font + element colors (colors are layout-style-aware)
// ─────────────────────────────────────────────────────────────────────────────

class ClockToolboxLeft extends StatelessWidget {
  final ClockLayer layer;
  final SceneNotifier n;
  const ClockToolboxLeft({super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TbLabel('Font Style'),
          const SizedBox(height: 4),
          TbDropdown<LedFontId>(
            values: LedFontId.values,
            current: layer.fontId,
            onChange: (v) => n.updateLayer(layer.copyWith(fontId: v)),
            labelFor: (v) => LedFontLibrary.get(v).name,
          ),
          const SizedBox(height: 10),
          const TbLabel('Element Colors'),
          const SizedBox(height: 8),
          ..._colorRowsForStyle(),
        ],
      );

  // Per-style color row sets. Each row reuses an existing color field on the
  // layer but is labeled to match the layout it appears in.
  List<Widget> _colorRowsForStyle() {
    switch (layer.layoutStyle) {
      case ClockLayoutStyle.classic:       return _classic();
      case ClockLayoutStyle.analog:        return _analog();
      case ClockLayoutStyle.weekdayPrefix: return _weekday();
      case ClockLayoutStyle.stacked:       return _stacked();
      case ClockLayoutStyle.secondsBar:    return _secondsBar();
      case ClockLayoutStyle.dualTimezone:  return _dualTz();
    }
  }

  Widget _gap() => const SizedBox(height: 6);

  _ColorRow _row(String label, Color color, ClockLayer Function(Color) apply) =>
      _ColorRow(
        label: label,
        color: color,
        onChanged: (c) => n.updateLayer(apply(c)),
      );

  List<Widget> _classic() => [
        _row('Hours',   layer.hoursColor,   (c) => layer.copyWith(hoursColor: c)),
        _gap(),
        _row('Minutes', layer.minutesColor, (c) => layer.copyWith(minutesColor: c)),
        _gap(),
        if (layer.showSeconds) ...[
          _row('Seconds', layer.secondsColor, (c) => layer.copyWith(secondsColor: c)),
          _gap(),
        ],
        if (layer.showDate) ...[
          _row('Date', layer.dateColor, (c) => layer.copyWith(dateColor: c)),
          _gap(),
        ],
        if (layer.format == ClockFormat.h12) ...[
          _row('AM / PM', layer.ampmColor, (c) => layer.copyWith(ampmColor: c)),
          _gap(),
        ],
        _row('Colon', layer.colonColor, (c) => layer.copyWith(colonColor: c)),
      ];

  List<Widget> _analog() => [
        _row('Hour hand',   layer.hoursColor,   (c) => layer.copyWith(hoursColor: c)),
        _gap(),
        _row('Minute hand', layer.minutesColor, (c) => layer.copyWith(minutesColor: c)),
        _gap(),
        if (layer.showSecondHand) ...[
          _row('Second hand', layer.secondsColor, (c) => layer.copyWith(secondsColor: c)),
          _gap(),
        ],
        _row('Face / rim',  layer.dateColor, (c) => layer.copyWith(dateColor: c)),
        if (layer.analogShowDigital) ...[
          _gap(),
          _row('Digital colon', layer.colonColor, (c) => layer.copyWith(colonColor: c)),
        ],
      ];

  List<Widget> _weekday() => [
        _row('Weekday', layer.ampmColor,    (c) => layer.copyWith(ampmColor: c)),
        _gap(),
        _row('Hours',   layer.hoursColor,   (c) => layer.copyWith(hoursColor: c)),
        _gap(),
        _row('Minutes', layer.minutesColor, (c) => layer.copyWith(minutesColor: c)),
        _gap(),
        _row('Colon',   layer.colonColor,   (c) => layer.copyWith(colonColor: c)),
      ];

  List<Widget> _stacked() => [
        _row('Hours',   layer.hoursColor,   (c) => layer.copyWith(hoursColor: c)),
        _gap(),
        _row('Minutes', layer.minutesColor, (c) => layer.copyWith(minutesColor: c)),
      ];

  List<Widget> _secondsBar() => [
        _row('Hours',       layer.hoursColor,   (c) => layer.copyWith(hoursColor: c)),
        _gap(),
        _row('Minutes',     layer.minutesColor, (c) => layer.copyWith(minutesColor: c)),
        _gap(),
        _row('Colon',       layer.colonColor,   (c) => layer.copyWith(colonColor: c)),
        _gap(),
        _row('Seconds bar', layer.secondsColor, (c) => layer.copyWith(secondsColor: c)),
      ];

  List<Widget> _dualTz() => [
        _row('Zone labels', layer.ampmColor,    (c) => layer.copyWith(ampmColor: c)),
        _gap(),
        _row('Hours',       layer.hoursColor,   (c) => layer.copyWith(hoursColor: c)),
        _gap(),
        _row('Minutes',     layer.minutesColor, (c) => layer.copyWith(minutesColor: c)),
        _gap(),
        _row('Colon',       layer.colonColor,   (c) => layer.copyWith(colonColor: c)),
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// ClockToolboxRight — layout style + per-style controls
// ─────────────────────────────────────────────────────────────────────────────

class ClockToolboxRight extends StatelessWidget {
  final ClockLayer layer;
  final SceneNotifier n;
  const ClockToolboxRight({super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Layout style ───────────────────────────────────────────────
          const TbLabel('Layout style'),
          const SizedBox(height: 4),
          _ClockLayoutDropdown(
            current: layer.layoutStyle,
            onChanged: (v) => n.updateLayer(layer.copyWith(layoutStyle: v)),
          ),
          const SizedBox(height: 10),

          // ── Timezone (always shown) ────────────────────────────────────
          TbLabel(
            layer.layoutStyle == ClockLayoutStyle.dualTimezone
                ? 'First timezone'
                : 'Timezone',
          ),
          const SizedBox(height: 4),
          _TzDropdown(
            current: layer.timezone,
            onChanged: (tz) => n.updateLayer(layer.copyWith(timezone: tz)),
          ),
          const SizedBox(height: 10),

          // ── Per-style controls ─────────────────────────────────────────
          ..._controlsForStyle(),
        ],
      );

  List<Widget> _controlsForStyle() {
    switch (layer.layoutStyle) {
      case ClockLayoutStyle.classic:       return _classicControls();
      case ClockLayoutStyle.analog:        return _analogControls();
      case ClockLayoutStyle.weekdayPrefix: return _weekdayControls();
      case ClockLayoutStyle.stacked:       return _stackedControls();
      case ClockLayoutStyle.secondsBar:    return _secondsBarControls();
      case ClockLayoutStyle.dualTimezone:  return _dualTzControls();
    }
  }

  // Shared shortcuts
  TbToggleRow _h12Toggle() => TbToggleRow(
        label: '12-hour format',
        value: layer.format == ClockFormat.h12,
        onChanged: (v) => n.updateLayer(layer.copyWith(
            format: v ? ClockFormat.h12 : ClockFormat.h24)),
      );

  TbToggleRow _blinkToggle() => TbToggleRow(
        label: 'Blink colon',
        value: layer.blinkColon,
        onChanged: (v) => n.updateLayer(layer.copyWith(blinkColon: v)),
      );

  // ── Classic — original behavior ────────────────────────────────────────
  List<Widget> _classicControls() => [
        _h12Toggle(),
        TbToggleRow(
          label: 'Show date',
          value: layer.showDate,
          onChanged: (v) => n.updateLayer(layer.copyWith(showDate: v)),
        ),
        TbToggleRow(
          label: 'Show seconds',
          value: layer.showSeconds,
          onChanged: (v) => n.updateLayer(layer.copyWith(showSeconds: v)),
        ),
        _blinkToggle(),
      ];

  // ── Analog — face style + hand/digital toggles ─────────────────────────
  List<Widget> _analogControls() => [
        const TbLabel('Face style'),
        const SizedBox(height: 4),
        _AnalogFaceDropdown(
          current: layer.analogFaceStyle,
          onChanged: (v) => n.updateLayer(layer.copyWith(analogFaceStyle: v)),
        ),
        const SizedBox(height: 8),
        TbToggleRow(
          label: 'Second hand',
          value: layer.showSecondHand,
          onChanged: (v) => n.updateLayer(layer.copyWith(showSecondHand: v)),
        ),
        TbToggleRow(
          label: 'Show digital time',
          value: layer.analogShowDigital,
          onChanged: (v) => n.updateLayer(layer.copyWith(analogShowDigital: v)),
        ),
        if (layer.analogShowDigital) ...[
          _h12Toggle(),
          _blinkToggle(),
        ],
      ];

  // ── Weekday prefix ─────────────────────────────────────────────────────
  List<Widget> _weekdayControls() => [
        _h12Toggle(),
        _blinkToggle(),
      ];

  // ── Stacked (HH / MM) — no seconds, no AM/PM by design ─────────────────
  List<Widget> _stackedControls() => [
        _h12Toggle(),
      ];

  // ── Seconds bar ────────────────────────────────────────────────────────
  List<Widget> _secondsBarControls() => [
        _h12Toggle(),
        _blinkToggle(),
      ];

  // ── Dual timezone ──────────────────────────────────────────────────────
  List<Widget> _dualTzControls() {
    final autoFirst  = defaultZoneLabel(layer.timezone);
    final autoSecond = defaultZoneLabel(layer.secondTimezone);
    return [
      const TbLabel('Second timezone'),
      const SizedBox(height: 4),
      _TzDropdown(
        current: layer.secondTimezone,
        onChanged: (tz) => n.updateLayer(layer.copyWith(secondTimezone: tz)),
      ),
      const SizedBox(height: 10),
      const TbLabel('Zone labels'),
      const SizedBox(height: 4),
      _LabelOverrideField(
        hint: 'Auto: $autoFirst',
        value: layer.firstZoneLabel,
        onSubmitted: (v) =>
            n.updateLayer(layer.copyWith(firstZoneLabel: v.trim())),
      ),
      const SizedBox(height: 6),
      _LabelOverrideField(
        hint: 'Auto: $autoSecond',
        value: layer.secondZoneLabel,
        onSubmitted: (v) =>
            n.updateLayer(layer.copyWith(secondZoneLabel: v.trim())),
      ),
      const SizedBox(height: 10),
      _h12Toggle(),
      _blinkToggle(),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layout style dropdown (kGreen-themed, like _PomodoroLayoutDropdown)
// ─────────────────────────────────────────────────────────────────────────────

class _ClockLayoutDropdown extends StatelessWidget {
  final ClockLayoutStyle current;
  final ValueChanged<ClockLayoutStyle> onChanged;

  const _ClockLayoutDropdown({
    required this.current,
    required this.onChanged,
  });

  static String _label(ClockLayoutStyle v) => switch (v) {
        ClockLayoutStyle.classic       => 'Classic',
        ClockLayoutStyle.analog        => 'Analog',
        ClockLayoutStyle.weekdayPrefix => 'Weekday prefix',
        ClockLayoutStyle.stacked       => 'Stacked',
        ClockLayoutStyle.secondsBar    => 'Seconds bar',
        ClockLayoutStyle.dualTimezone  => 'Dual timezone',
      };

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: kGreen.withOpacity(0.1),
          border: Border.all(color: kGreen.withOpacity(0.5)),
          borderRadius: const BorderRadius.all(kRadiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<ClockLayoutStyle>(
            value: current,
            isExpanded: true,
            isDense: true,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: kGreen),
            dropdownColor: context.tSurface,
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: kGreen),
            items: ClockLayoutStyle.values
                .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(_label(v)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Analog face style dropdown
// ─────────────────────────────────────────────────────────────────────────────

class _AnalogFaceDropdown extends StatelessWidget {
  final AnalogFaceStyle current;
  final ValueChanged<AnalogFaceStyle> onChanged;

  const _AnalogFaceDropdown({
    required this.current,
    required this.onChanged,
  });

  static String _label(AnalogFaceStyle v) => switch (v) {
        AnalogFaceStyle.cardinalDots => '4 cardinal dots',
        AnalogFaceStyle.allDots      => '12 hour dots',
        AnalogFaceStyle.ticks        => '4 tick lines',
        AnalogFaceStyle.none         => 'No markers',
      };

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: kGreen.withOpacity(0.1),
          border: Border.all(color: kGreen.withOpacity(0.5)),
          borderRadius: const BorderRadius.all(kRadiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<AnalogFaceStyle>(
            value: current,
            isExpanded: true,
            isDense: true,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: kGreen),
            dropdownColor: context.tSurface,
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: kGreen),
            items: AnalogFaceStyle.values
                .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(_label(v)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Zone label override text field — small input with placeholder hint
// ─────────────────────────────────────────────────────────────────────────────

class _LabelOverrideField extends StatefulWidget {
  final String hint;
  final String value;
  final ValueChanged<String> onSubmitted;
  const _LabelOverrideField({
    required this.hint,
    required this.value,
    required this.onSubmitted,
  });

  @override
  State<_LabelOverrideField> createState() => _LabelOverrideFieldState();
}

class _LabelOverrideFieldState extends State<_LabelOverrideField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl  = TextEditingController(text: widget.value);
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) widget.onSubmitted(_ctrl.text);
  }

  @override
  void didUpdateWidget(_LabelOverrideField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        focusNode: _focus,
        maxLength: 4,
        textCapitalization: TextCapitalization.characters,
        style: TextStyle(fontSize: 11, color: context.tTextPrimary),
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          hintText: widget.hint,
          hintStyle: TextStyle(fontSize: 11, color: context.tTextDim),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: const BorderRadius.all(kRadiusSm),
            borderSide: BorderSide(color: context.tBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(kRadiusSm),
            borderSide: BorderSide(color: context.tBorder),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(kRadiusSm),
            borderSide: BorderSide(color: kGreen, width: 1.5),
          ),
        ),
        onSubmitted: widget.onSubmitted,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Timezone dropdown
// ─────────────────────────────────────────────────────────────────────────────

class _TzEntry {
  final String id;
  final String label;
  const _TzEntry(this.id, this.label);
}

const _kTimezones = <_TzEntry>[
  _TzEntry('local',               'Local (device time)'),
  _TzEntry('UTC',                 'UTC ±0'),
  _TzEntry('Europe/London',       'London  UTC+0/+1'),
  _TzEntry('Europe/Lisbon',       'Lisbon  UTC+0/+1'),
  _TzEntry('Europe/Paris',        'Paris  UTC+1/+2'),
  _TzEntry('Europe/Berlin',       'Berlin  UTC+1/+2'),
  _TzEntry('Europe/Rome',         'Rome  UTC+1/+2'),
  _TzEntry('Europe/Amsterdam',    'Amsterdam  UTC+1/+2'),
  _TzEntry('Europe/Madrid',       'Madrid  UTC+1/+2'),
  _TzEntry('Europe/Warsaw',       'Warsaw  UTC+1/+2'),
  _TzEntry('Europe/Athens',       'Athens  UTC+2/+3'),
  _TzEntry('Europe/Bucharest',    'Bucharest  UTC+2/+3'),
  _TzEntry('Europe/Helsinki',     'Helsinki  UTC+2/+3'),
  _TzEntry('Europe/Istanbul',     'Istanbul  UTC+3'),
  _TzEntry('Europe/Moscow',       'Moscow  UTC+3'),
  _TzEntry('Asia/Riyadh',         'Riyadh  UTC+3'),
  _TzEntry('Asia/Dubai',          'Dubai  UTC+4'),
  _TzEntry('Asia/Baku',           'Baku  UTC+4'),
  _TzEntry('Asia/Kabul',          'Kabul  UTC+4:30'),
  _TzEntry('Asia/Karachi',        'Karachi  UTC+5'),
  _TzEntry('Asia/Tashkent',       'Tashkent  UTC+5'),
  _TzEntry('Asia/Kolkata',        'Mumbai / Kolkata  UTC+5:30'),
  _TzEntry('Asia/Colombo',        'Sri Lanka  UTC+5:30'),
  _TzEntry('Asia/Kathmandu',      'Kathmandu  UTC+5:45'),
  _TzEntry('Asia/Dhaka',          'Dhaka  UTC+6'),
  _TzEntry('Asia/Almaty',         'Almaty  UTC+6'),
  _TzEntry('Asia/Rangoon',        'Yangon  UTC+6:30'),
  _TzEntry('Asia/Bangkok',        'Bangkok  UTC+7'),
  _TzEntry('Asia/Jakarta',        'Jakarta  UTC+7'),
  _TzEntry('Asia/Ho_Chi_Minh',    'Ho Chi Minh  UTC+7'),
  _TzEntry('Asia/Singapore',      'Singapore  UTC+8'),
  _TzEntry('Asia/Shanghai',       'Beijing / Shanghai  UTC+8'),
  _TzEntry('Asia/Taipei',         'Taipei  UTC+8'),
  _TzEntry('Asia/Kuala_Lumpur',   'Kuala Lumpur  UTC+8'),
  _TzEntry('Asia/Manila',         'Manila  UTC+8'),
  _TzEntry('Asia/Seoul',          'Seoul  UTC+9'),
  _TzEntry('Asia/Tokyo',          'Tokyo  UTC+9'),
  _TzEntry('Australia/Darwin',    'Darwin  UTC+9:30'),
  _TzEntry('Australia/Brisbane',  'Brisbane  UTC+10'),
  _TzEntry('Australia/Adelaide',  'Adelaide  UTC+9:30/+10:30'),
  _TzEntry('Australia/Sydney',    'Sydney  UTC+10/+11'),
  _TzEntry('Pacific/Auckland',    'Auckland  UTC+12/+13'),
  _TzEntry('Pacific/Fiji',        'Fiji  UTC+12'),
  _TzEntry('Pacific/Honolulu',    'Honolulu  UTC−10'),
  _TzEntry('America/Anchorage',   'Anchorage  UTC−9/−8'),
  _TzEntry('America/Los_Angeles', 'Los Angeles  UTC−8/−7'),
  _TzEntry('America/Denver',      'Denver  UTC−7/−6'),
  _TzEntry('America/Phoenix',     'Phoenix  UTC−7'),
  _TzEntry('America/Chicago',     'Chicago  UTC−6/−5'),
  _TzEntry('America/New_York',    'New York  UTC−5/−4'),
  _TzEntry('America/Toronto',     'Toronto  UTC−5/−4'),
  _TzEntry('America/Halifax',     'Halifax  UTC−4/−3'),
  _TzEntry('America/Sao_Paulo',   'São Paulo  UTC−3'),
  _TzEntry('America/Buenos_Aires','Buenos Aires  UTC−3'),
  _TzEntry('Atlantic/Azores',     'Azores  UTC−1/0'),
];

// Short labels used by dualTimezone style when the user hasn't typed an
// override. Roughly IATA airport codes — easy to recognize.
const Map<String, String> _kTzShortLabels = {
  'local':              'LCL',
  'UTC':                'UTC',
  'Europe/London':      'LON',
  'Europe/Lisbon':      'LIS',
  'Europe/Paris':       'PAR',
  'Europe/Berlin':      'BER',
  'Europe/Rome':        'ROM',
  'Europe/Amsterdam':   'AMS',
  'Europe/Madrid':      'MAD',
  'Europe/Warsaw':      'WAR',
  'Europe/Athens':      'ATH',
  'Europe/Bucharest':   'BUC',
  'Europe/Helsinki':    'HEL',
  'Europe/Istanbul':    'IST',
  'Europe/Moscow':      'MOW',
  'Asia/Riyadh':        'RUH',
  'Asia/Dubai':         'DXB',
  'Asia/Baku':          'BAK',
  'Asia/Kabul':         'KBL',
  'Asia/Karachi':       'KHI',
  'Asia/Tashkent':      'TAS',
  'Asia/Kolkata':       'BOM',
  'Asia/Colombo':       'CMB',
  'Asia/Kathmandu':     'KTM',
  'Asia/Dhaka':         'DAC',
  'Asia/Almaty':        'ALA',
  'Asia/Rangoon':       'RGN',
  'Asia/Bangkok':       'BKK',
  'Asia/Jakarta':       'JKT',
  'Asia/Ho_Chi_Minh':   'SGN',
  'Asia/Singapore':     'SIN',
  'Asia/Shanghai':      'SHA',
  'Asia/Taipei':        'TPE',
  'Asia/Kuala_Lumpur':  'KUL',
  'Asia/Manila':        'MNL',
  'Asia/Seoul':         'ICN',
  'Asia/Tokyo':         'TYO',
  'Australia/Darwin':   'DRW',
  'Australia/Brisbane': 'BNE',
  'Australia/Adelaide': 'ADL',
  'Australia/Sydney':   'SYD',
  'Pacific/Auckland':   'AKL',
  'Pacific/Fiji':       'NAN',
  'Pacific/Honolulu':   'HNL',
  'America/Anchorage':  'ANC',
  'America/Los_Angeles':'LAX',
  'America/Denver':     'DEN',
  'America/Phoenix':    'PHX',
  'America/Chicago':    'CHI',
  'America/New_York':   'NYC',
  'America/Toronto':    'YYZ',
  'America/Halifax':    'HFX',
  'America/Sao_Paulo':  'SAO',
  'America/Buenos_Aires':'BUE',
  'Atlantic/Azores':    'AZO',
};

/// Auto-derived 3-letter label for a timezone id. Falls back to the last
/// path segment uppercased and truncated to 3 chars.
String defaultZoneLabel(String tz) {
  final mapped = _kTzShortLabels[tz];
  if (mapped != null) return mapped;
  final segment = tz.contains('/') ? tz.split('/').last : tz;
  final clean   = segment.replaceAll('_', '');
  return clean.substring(0, clean.length < 3 ? clean.length : 3).toUpperCase();
}

class _TzDropdown extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _TzDropdown({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = _kTimezones.firstWhere(
      (e) => e.id == current,
      orElse: () => _kTimezones.first,
    );

    return DropdownButtonFormField<_TzEntry>(
      value: selected,
      isDense: true,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(kRadiusSm),
          borderSide: BorderSide(color: context.tBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(kRadiusSm),
          borderSide: BorderSide(color: context.tBorder),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(kRadiusSm),
          borderSide: BorderSide(color: kGreen, width: 1.5),
        ),
      ),
      style: TextStyle(fontSize: 11, color: context.tTextPrimary),
      items: _kTimezones
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e.label, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v.id);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ColorRow — internal row used by ClockToolboxLeft
// ─────────────────────────────────────────────────────────────────────────────

class _ColorRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;
  const _ColorRow({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: context.tTextMuted),
            ),
          ),
          tbColorBtn(context, color, onChanged),
        ],
      );
}