  import 'package:flutter/material.dart';

  import '../../../../engine/renderer/font_organizer.dart';
  import '../../../../engine/scene/layer.dart';
  import '../../../../shared/providers/providers.dart';
  import 'toolbox_shared.dart';
  import '../ui_primitives.dart';

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
          _ColorRow(
              label: 'Hours',
              color: layer.hoursColor,
              onChanged: (c) =>
                  n.updateLayer(layer.copyWith(hoursColor: c))),
          const SizedBox(height: 6),
          _ColorRow(
              label: 'Minutes',
              color: layer.minutesColor,
              onChanged: (c) =>
                  n.updateLayer(layer.copyWith(minutesColor: c))),
          const SizedBox(height: 6),
          if (layer.showSeconds) ...[
            _ColorRow(
                label: 'Seconds',
                color: layer.secondsColor,
                onChanged: (c) =>
                    n.updateLayer(layer.copyWith(secondsColor: c))),
            const SizedBox(height: 6),
          ],
          if (layer.showDate) ...[
            _ColorRow(
                label: 'Date',
                color: layer.dateColor,
                onChanged: (c) =>
                    n.updateLayer(layer.copyWith(dateColor: c))),
            const SizedBox(height: 6),
          ],
          if (layer.format == ClockFormat.h12) ...[
            _ColorRow(
                label: 'AM / PM',
                color: layer.ampmColor,
                onChanged: (c) =>
                    n.updateLayer(layer.copyWith(ampmColor: c))),
            const SizedBox(height: 6),
          ],
          _ColorRow(
              label: 'Colon',
              color: layer.colonColor,
              onChanged: (c) =>
                  n.updateLayer(layer.copyWith(colonColor: c))),
        ],
      );
} 

  class ClockToolboxRight extends StatelessWidget {
    final ClockLayer layer;
    final SceneNotifier n;
    const ClockToolboxRight({super.key, required this.layer, required this.n});

    @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TbLabel('Timezone'),
          const SizedBox(height: 4),
          _TzDropdown(
            current: layer.timezone,
            onChanged: (tz) => n.updateLayer(layer.copyWith(timezone: tz)),
          ),
          const SizedBox(height: 10),
          TbToggleRow(
              label: '12-hour format',
              value: layer.format == ClockFormat.h12,
              onChanged: (v) => n.updateLayer(layer.copyWith(
                  format: v ? ClockFormat.h12 : ClockFormat.h24))),
          TbToggleRow(
              label: 'Show date',
              value: layer.showDate,
              onChanged: (v) =>
                  n.updateLayer(layer.copyWith(showDate: v))),
          TbToggleRow(
              label: 'Show seconds',
              value: layer.showSeconds,
              onChanged: (v) =>
                  n.updateLayer(layer.copyWith(showSeconds: v))),
          TbToggleRow(
              label: 'Blink colon',
              value: layer.blinkColon,
              onChanged: (v) =>
                  n.updateLayer(layer.copyWith(blinkColon: v))),
        ],
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
  // Private helpers
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
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11, color: context.tTextMuted))),
            tbColorBtn(context, color, onChanged),
          ],
        );
  }