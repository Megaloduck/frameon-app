import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/device/connection_state.dart';
import '../../features/device/device_controller.dart';
import '../../features/editor/toolkits/ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Settings state
// ─────────────────────────────────────────────────────────────────────────────

class SettingsState {
  final int baudRate;
  final bool autoReconnect;
  final bool runInBackground;
  final bool startOnStartup;
  final int connectionTimeoutSec;

  const SettingsState({
    this.baudRate = 115200,
    this.autoReconnect = true,
    this.runInBackground = false,
    this.startOnStartup = false,
    this.connectionTimeoutSec = 5,
  });

  SettingsState copyWith({
    int? baudRate,
    bool? autoReconnect,
    bool? runInBackground,
    bool? startOnStartup,
    int? connectionTimeoutSec,
  }) =>
      SettingsState(
        baudRate: baudRate ?? this.baudRate,
        autoReconnect: autoReconnect ?? this.autoReconnect,
        runInBackground: runInBackground ?? this.runInBackground,
        startOnStartup: startOnStartup ?? this.startOnStartup,
        connectionTimeoutSec:
            connectionTimeoutSec ?? this.connectionTimeoutSec,
      );
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  void update(SettingsState Function(SettingsState) fn) =>
      state = fn(state);
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showSettingsDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => const _SettingsDialog(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog shell
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsDialog extends ConsumerStatefulWidget {
  const _SettingsDialog();

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  int _selectedIndex = 0;

  static const _sections = [
    (icon: Icons.usb_rounded,          label: 'Device'),
    (icon: Icons.keyboard_rounded,     label: 'Shortcuts'),
    (icon: Icons.memory_rounded,       label: 'Hardware'),
    (icon: Icons.tune_rounded,         label: 'General'),
    (icon: Icons.info_outline_rounded, label: 'About'),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Container(
        width: 720,
        height: 520,
        decoration: BoxDecoration(
          color: context.tSurface,
          borderRadius: const BorderRadius.all(kRadiusLg),
          border: Border.all(color: context.tBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(kRadiusLg),
          child: Row(
            children: [
              // ── Sidebar ────────────────────────────────────────────────
              _Sidebar(
                sections: _sections,
                selectedIndex: _selectedIndex,
                onSelect: (i) => setState(() => _selectedIndex = i),
              ),
              // ── Content ────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ContentHeader(
                        title: _sections[_selectedIndex].label),
                    Expanded(
                      child: _buildContent(_selectedIndex),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(int index) {
    return switch (index) {
      0 => const _DeviceSection(),
      1 => const _ShortcutsSection(),
      2 => const _HardwareSection(),
      3 => const _GeneralSection(),
      4 => const _AboutSection(),
      _ => const SizedBox.shrink(),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final List<({IconData icon, String label})> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _Sidebar({
    required this.sections,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      decoration: BoxDecoration(
        color: context.tSurfaceLow,
        border: Border(right: BorderSide(color: context.tBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: kGreen,
                  borderRadius: BorderRadius.all(kRadiusSm),
                ),
                child: const Icon(Icons.grid_on_rounded,
                    size: 13, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.tTextPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ]),
          ),
          Container(height: 1, color: context.tBorder),
          const SizedBox(height: 8),
          // Nav items
          ...sections.asMap().entries.map((e) => _SidebarItem(
                icon: e.value.icon,
                label: e.value.label,
                selected: e.key == selectedIndex,
                onTap: () => onSelect(e.key),
              )),
          const Spacer(),
          // Version footer
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'v1.0.0',
              style: TextStyle(fontSize: 10, color: context.tTextDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? kGreen.withOpacity(0.12)
                : _hovered
                    ? context.tBorder.withOpacity(0.5)
                    : Colors.transparent,
            borderRadius: const BorderRadius.all(kRadiusSm),
          ),
          child: Row(children: [
            Icon(
              widget.icon,
              size: 15,
              color: active ? kGreen : context.tTextMuted,
            ),
            const SizedBox(width: 9),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.w400,
                color: active ? kGreen : context.tTextMuted,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Content header
// ─────────────────────────────────────────────────────────────────────────────

class _ContentHeader extends StatelessWidget {
  final String title;
  const _ContentHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.tBorder)),
      ),
      child: Row(children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: context.tTextPrimary,
          ),
        ),
        const Spacer(),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section: Device
// Now includes live connection status + connect/disconnect controls.
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceSection extends ConsumerWidget {
  const _DeviceSection();

  static const _baudRates = [9600, 19200, 38400, 57600, 115200, 230400, 460800];
  static const _timeouts = [2, 3, 5, 10, 15, 30];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s      = ref.watch(settingsProvider);
    final sn     = ref.read(settingsProvider.notifier);
    final device = ref.watch(deviceConnectionProvider);
    final portsAsync = ref.watch(availablePortsProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [

        // ── Live connection card ─────────────────────────────────────────
        _SettingsGroup(
          label: 'Connection',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status row
                  Row(children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _statusColor(device.status),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _statusLabel(device),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(device.status),
                      ),
                    ),
                    const Spacer(),
                    if (device.isConnected)
                      _SmallBtn(
                        label: 'Disconnect',
                        color: Colors.red.shade400,
                        onTap: () => ref
                            .read(deviceConnectionProvider.notifier)
                            .disconnect(),
                      ),
                  ]),
                  if (device.errorMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      device.errorMessage!,
                      style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                    ),
                  ],

                  // Port picker
                  const SizedBox(height: 12),
                  Row(children: [
                    Text(
                      'Serial Port',
                      style: TextStyle(fontSize: 12, color: context.tTextPrimary),
                    ),
                    const Spacer(),
                    _SmallBtn(
                      label: 'Scan',
                      color: kGreen,
                      icon: Icons.refresh_rounded,
                      onTap: () async {
                        await ref
                            .read(deviceConnectionProvider.notifier)
                            .scanPorts();
                        ref.invalidate(availablePortsProvider);
                      },
                    ),
                  ]),
                  const SizedBox(height: 8),
                  portsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: kGreen))),
                    ),
                    error: (e, _) => Text('Scan error: $e',
                        style: TextStyle(
                            fontSize: 11, color: Colors.red.shade400)),
                    data: (ports) => ports.isEmpty
                        ? Text(
                            'No ports found. Plug in your device and tap Scan.',
                            style: TextStyle(
                                fontSize: 11, color: context.tTextDim),
                          )
                        : Column(
                            children: ports.map((p) {
                              final isActive = p == device.portName;
                              return GestureDetector(
                                onTap: device.isConnected && isActive
                                    ? null
                                    : () => ref
                                        .read(deviceConnectionProvider.notifier)
                                        .connect(p),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 100),
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? kGreen.withOpacity(0.10)
                                        : context.tSurface,
                                    borderRadius:
                                        const BorderRadius.all(kRadiusSm),
                                    border: Border.all(
                                      color: isActive
                                          ? kGreen.withOpacity(0.5)
                                          : context.tBorder,
                                    ),
                                  ),
                                  child: Row(children: [
                                    Icon(Icons.usb_rounded,
                                        size: 14,
                                        color: isActive
                                            ? kGreen
                                            : context.tTextMuted),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(p,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: isActive
                                                  ? kGreen
                                                  : context.tTextPrimary,
                                              fontWeight: isActive
                                                  ? FontWeight.w600
                                                  : FontWeight.w400)),
                                    ),
                                    if (device.status ==
                                            DeviceConnectionStatus.connecting &&
                                        isActive)
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: kGreen),
                                      )
                                    else if (isActive && device.isConnected)
                                      const Icon(Icons.check_rounded,
                                          size: 14, color: kGreen),
                                  ]),
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ── Serial settings ─────────────────────────────────────────────
        _SettingsGroup(
          label: 'Serial Connection',
          children: [
            _SettingsRow(
              label: 'Baud Rate',
              description: 'Data transfer speed to the LED matrix device.',
              child: _DropdownField<int>(
                value: s.baudRate,
                items: _baudRates,
                labelFor: (v) => v.toString(),
                onChanged: (v) =>
                    sn.update((s) => s.copyWith(baudRate: v)),
              ),
            ),
            _SettingsDivider(),
            _SettingsRow(
              label: 'Connection Timeout',
              description: 'Seconds before a connection attempt is abandoned.',
              child: _DropdownField<int>(
                value: s.connectionTimeoutSec,
                items: _timeouts,
                labelFor: (v) => '${v}s',
                onChanged: (v) =>
                    sn.update((s) => s.copyWith(connectionTimeoutSec: v)),
              ),
            ),
            _SettingsDivider(),
            _SettingsRow(
              label: 'Auto-reconnect',
              description:
                  'Automatically attempt to reconnect if the device disconnects unexpectedly.',
              child: _ToggleField(
                value: s.autoReconnect,
                onChanged: (v) =>
                    sn.update((s) => s.copyWith(autoReconnect: v)),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ── Protocol info ───────────────────────────────────────────────
        _SettingsGroup(
          label: 'Protocol',
          children: [
            _InfoRow(
              icon: Icons.verified_rounded,
              label: 'Protocol Version',
              value: 'FRM v1  (0x46 0x52 0x4D)',
            ),
            _SettingsDivider(),
            _InfoRow(
              icon: Icons.palette_rounded,
              label: 'Pixel Format',
              value: 'RGB565  ·  big-endian',
            ),
            _SettingsDivider(),
            _InfoRow(
              icon: Icons.grid_on_rounded,
              label: 'Matrix Resolution',
              value: '64 × 32 px',
            ),
          ],
        ),
      ],
    );
  }

  Color _statusColor(DeviceConnectionStatus status) => switch (status) {
        DeviceConnectionStatus.connected  => kGreen,
        DeviceConnectionStatus.connecting => const Color(0xFFE6A817),
        DeviceConnectionStatus.sending    => const Color(0xFF378ADD),
        DeviceConnectionStatus.error      => Colors.red,
        DeviceConnectionStatus.lost       => Colors.red,
        _                                  => const Color(0xFF888580),
      };

  String _statusLabel(DeviceConnectionState d) => switch (d.status) {
        DeviceConnectionStatus.connected    => 'Connected  ·  ${d.portName}',
        DeviceConnectionStatus.connecting   => 'Connecting…',
        DeviceConnectionStatus.sending      => 'Sending…',
        DeviceConnectionStatus.scanning     => 'Scanning for ports…',
        DeviceConnectionStatus.error        => 'Error',
        DeviceConnectionStatus.lost         => 'Connection lost',
        DeviceConnectionStatus.disconnected => 'Not connected',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Section: Keyboard Shortcuts
// ─────────────────────────────────────────────────────────────────────────────

class _ShortcutsSection extends StatelessWidget {
  const _ShortcutsSection();

  static const _shortcuts = [
    _ShortcutEntry('Undo', ['⌘', 'Z'], 'Ctrl+Z on Windows/Linux'),
    _ShortcutEntry('Redo', ['⌘', '⇧', 'Z'], 'Ctrl+Shift+Z on Windows/Linux'),
    _ShortcutEntry('Save project', ['⌘', 'S'], 'Ctrl+S on Windows/Linux'),
    _ShortcutEntry('New project', ['⌘', 'N'], 'Ctrl+N on Windows/Linux'),
    _ShortcutEntry('Open project', ['⌘', 'O'], 'Ctrl+O on Windows/Linux'),
    _ShortcutEntry('Send to device', ['⌘', '↵'], 'Ctrl+Enter on Windows/Linux'),
    _ShortcutEntry('Toggle theme', ['⌘', 'T'], 'Ctrl+T on Windows/Linux'),
    _ShortcutEntry('Delete layer', ['⌫', ''], 'Backspace or Delete'),
    _ShortcutEntry('Move layer up', ['⌘', '↑'], 'Ctrl+↑ on Windows/Linux'),
    _ShortcutEntry('Move layer down', ['⌘', '↓'], 'Ctrl+↓ on Windows/Linux'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SettingsGroup(
          label: 'Editor',
          children: _shortcuts
              .asMap()
              .entries
              .map((e) => Column(
                    children: [
                      _ShortcutRow(entry: e.value),
                      if (e.key < _shortcuts.length - 1) _SettingsDivider(),
                    ],
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        Text(
          '⌘ = Cmd on macOS  ·  Ctrl on Windows / Linux',
          style: TextStyle(fontSize: 11, color: context.tTextDim),
        ),
      ],
    );
  }
}

class _ShortcutEntry {
  final String action;
  final List<String> keys;
  final String note;
  const _ShortcutEntry(this.action, this.keys, this.note);
}

class _ShortcutRow extends StatelessWidget {
  final _ShortcutEntry entry;
  const _ShortcutRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.action,
                  style: TextStyle(
                      fontSize: 12, color: context.tTextPrimary)),
              if (entry.note.isNotEmpty)
                Text(entry.note,
                    style: TextStyle(
                        fontSize: 10, color: context.tTextDim)),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: entry.keys
              .where((k) => k.isNotEmpty)
              .map((k) => Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _KeyBadge(label: k),
                  ))
              .toList(),
        ),
      ]),
    );
  }
}

class _KeyBadge extends StatelessWidget {
  final String label;
  const _KeyBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: context.tSurfaceLow,
        borderRadius: const BorderRadius.all(kRadiusSm),
        border: Border.all(color: context.tBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.tTextMuted,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section: Hardware
// Now reads real connection state from deviceConnectionProvider.
// ─────────────────────────────────────────────────────────────────────────────

class _HardwareSection extends ConsumerStatefulWidget {
  const _HardwareSection();

  @override
  ConsumerState<_HardwareSection> createState() => _HardwareSectionState();
}

class _HardwareSectionState extends ConsumerState<_HardwareSection> {
  // System stats remain as placeholders (would need platform channels for real data).
  final double _cpuUsage     = 0.18;
  final double _memUsage     = 0.54;
  final double _diskUsage    = 0.67;
  final double _batteryLevel = 0.82;
  final bool   _onAcPower    = true;

  @override
  Widget build(BuildContext context) {
    // Read live device connection state from the provider.
    final device = ref.watch(deviceConnectionProvider);
    final deviceOnline = device.isConnected;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SettingsGroup(
          label: 'System',
          children: [
            _HardwareBar(
              icon: Icons.developer_board_rounded,
              label: 'CPU',
              value: _cpuUsage,
              valueLabel: '${(_cpuUsage * 100).round()}%',
              color: _cpuUsage > 0.8
                  ? Colors.red.shade400
                  : _cpuUsage > 0.6
                      ? Colors.orange.shade400
                      : kGreen,
            ),
            _SettingsDivider(),
            _HardwareBar(
              icon: Icons.memory_rounded,
              label: 'Memory',
              value: _memUsage,
              valueLabel:
                  '${(_memUsage * 100).round()}%  ·  8.6 GB used of 16 GB',
              color: _memUsage > 0.85
                  ? Colors.red.shade400
                  : _memUsage > 0.65
                      ? Colors.orange.shade400
                      : kGreen,
            ),
            _SettingsDivider(),
            _HardwareBar(
              icon: Icons.storage_rounded,
              label: 'Disk',
              value: _diskUsage,
              valueLabel:
                  '${(_diskUsage * 100).round()}%  ·  335 GB used of 512 GB',
              color: _diskUsage > 0.9
                  ? Colors.red.shade400
                  : _diskUsage > 0.75
                      ? Colors.orange.shade400
                      : kGreen,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          label: 'Power',
          children: [
            _HardwareBar(
              icon: _onAcPower
                  ? Icons.power_rounded
                  : Icons.battery_full_rounded,
              label: _onAcPower ? 'Power  ·  Charging' : 'Battery',
              value: _batteryLevel,
              valueLabel: '${(_batteryLevel * 100).round()}%',
              color: !_onAcPower && _batteryLevel < 0.2
                  ? Colors.red.shade400
                  : kGreen,
            ),
            _SettingsDivider(),
            _InfoRow(
              icon: Icons.electrical_services_rounded,
              label: 'Power Source',
              value: _onAcPower ? 'AC Adapter connected' : 'Battery',
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── LED matrix device — reads from real provider ──────────────────
        _SettingsGroup(
          label: 'Device',
          children: [
            _InfoRow(
              icon: Icons.usb_rounded,
              label: 'Matrix Status',
              value: _deviceStatusLabel(device.status),
              valueColor: deviceOnline ? kGreen : context.tTextDim,
            ),
            _SettingsDivider(),
            _InfoRow(
              icon: Icons.settings_input_hdmi_rounded,
              label: 'Port',
              value: device.portName ?? '—',
            ),
            _SettingsDivider(),
            _InfoRow(
              icon: Icons.settings_ethernet_rounded,
              label: 'Firmware',
              value: deviceOnline ? 'FRM-ESP32  v2.1.4' : '—',
            ),
            _SettingsDivider(),
            _InfoRow(
              icon: Icons.thermostat_rounded,
              label: 'Device Temp',
              value: deviceOnline ? '38 °C' : '—',
            ),
            if (device.errorMessage != null) ...[
              _SettingsDivider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Icon(Icons.error_outline_rounded,
                      size: 13, color: Colors.red.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      device.errorMessage!,
                      style: TextStyle(
                          fontSize: 11, color: Colors.red.shade400),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),

        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.info_outline_rounded,
              size: 11, color: context.tTextDim),
          const SizedBox(width: 5),
          Text(
            'Connect to a device via the Device tab or the USB chip in the top bar.',
            style: TextStyle(fontSize: 10, color: context.tTextDim),
          ),
        ]),
      ],
    );
  }

  String _deviceStatusLabel(DeviceConnectionStatus s) => switch (s) {
        DeviceConnectionStatus.connected    => 'Connected',
        DeviceConnectionStatus.connecting   => 'Connecting…',
        DeviceConnectionStatus.sending      => 'Sending…',
        DeviceConnectionStatus.scanning     => 'Scanning…',
        DeviceConnectionStatus.error        => 'Error',
        DeviceConnectionStatus.lost         => 'Connection lost',
        DeviceConnectionStatus.disconnected => 'Not connected',
      };
}

class _HardwareBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final String valueLabel;
  final Color color;

  const _HardwareBar({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 13, color: context.tTextMuted),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: context.tTextPrimary)),
            const Spacer(),
            Text(
              valueLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ]),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: const BorderRadius.all(kRadiusSm),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: context.tBorder,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section: General
// ─────────────────────────────────────────────────────────────────────────────

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SettingsGroup(
          label: 'Application Behavior',
          children: [
            _SettingsRow(
              label: 'Run in Background',
              description:
                  'Keep Frameon running after the window is closed. '
                  'The app stays in the system tray and continues refreshing the connected device.',
              tooltipText:
                  'When enabled, closing the window does not quit Frameon. '
                  'Use the tray icon to fully exit.',
              child: _ToggleField(
                value: s.runInBackground,
                onChanged: (v) =>
                    n.update((s) => s.copyWith(runInBackground: v)),
              ),
            ),
            _SettingsDivider(),
            _SettingsRow(
              label: 'Start on Startup',
              description:
                  'Automatically launch Frameon when you log in to your computer.',
              tooltipText:
                  'Frameon will be added to your system login items. '
                  'It will launch minimised to the tray if "Run in Background" is also enabled.',
              child: _ToggleField(
                value: s.startOnStartup,
                onChanged: (v) =>
                    n.update((s) => s.copyWith(startOnStartup: v)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section: About
// ─────────────────────────────────────────────────────────────────────────────

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.tSurfaceLow,
            borderRadius: const BorderRadius.all(kRadiusMd),
            border: Border.all(color: context.tBorder),
          ),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: kGreen,
                borderRadius: BorderRadius.all(kRadiusMd),
              ),
              child: const Icon(Icons.grid_on_rounded,
                  size: 28, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Frameon',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.tTextPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'LED Matrix Editor',
                style: TextStyle(fontSize: 12, color: context.tTextMuted),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.12),
                  borderRadius: const BorderRadius.all(kRadiusSm),
                  border: Border.all(color: kGreen.withOpacity(0.3)),
                ),
                child: const Text(
                  'v1.0.0',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: kGreen,
                  ),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          label: 'Build Info',
          children: [
            _InfoRow(icon: Icons.tag_rounded, label: 'Version',
                value: '1.0.0  (build 42)'),
            _SettingsDivider(),
            _InfoRow(icon: Icons.code_rounded, label: 'Framework',
                value: 'Flutter 3.x  ·  Dart 3.x'),
            _SettingsDivider(),
            _InfoRow(icon: Icons.devices_rounded, label: 'Platform',
                value: 'macOS · Windows · Linux'),
            _SettingsDivider(),
            _InfoRow(icon: Icons.calendar_today_rounded, label: 'Release Date',
                value: 'April 2026'),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          label: 'Legal',
          children: [
            _LinkRow(icon: Icons.article_outlined, label: 'License',
                value: 'MIT License'),
            _SettingsDivider(),
            _LinkRow(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy',
                value: 'View online →'),
            _SettingsDivider(),
            _LinkRow(icon: Icons.bug_report_outlined, label: 'Report a Bug',
                value: 'Open GitHub →'),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            '© 2026 Frameon. All rights reserved.',
            style: TextStyle(fontSize: 11, color: context.tTextDim),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared primitives
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _SettingsGroup({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.12,
            color: context.tTextDim,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: context.tSurfaceLow,
            borderRadius: const BorderRadius.all(kRadiusMd),
            border: Border.all(color: context.tBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: context.tBorder);
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String description;
  final String? tooltipText;
  final Widget child;

  const _SettingsRow({
    required this.label,
    required this.description,
    this.tooltipText,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: context.tTextPrimary,
                    ),
                  ),
                  if (tooltipText != null) ...[
                    const SizedBox(width: 5),
                    Tooltip(
                      message: tooltipText!,
                      preferBelow: false,
                      child: Icon(Icons.help_outline_rounded,
                          size: 12, color: context.tTextDim),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(description,
                    style: TextStyle(fontSize: 11, color: context.tTextDim)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Icon(icon, size: 13, color: context.tTextMuted),
        const SizedBox(width: 8),
        Text(label,
            style:
                TextStyle(fontSize: 12, color: context.tTextPrimary)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: valueColor ?? context.tTextMuted,
          ),
        ),
      ]),
    );
  }
}

class _LinkRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;

  const _LinkRow({required this.icon, required this.label, required this.value});

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

class _LinkRowState extends State<_LinkRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(widget.icon, size: 13, color: context.tTextMuted),
            const SizedBox(width: 8),
            Text(widget.label,
                style: TextStyle(
                    fontSize: 12, color: context.tTextPrimary)),
            const Spacer(),
            Text(
              widget.value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _hovered ? kGreen : context.tTextMuted,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ToggleField extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Transform.scale(
        scale: 0.75,
        alignment: Alignment.centerRight,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
}

class _DropdownField<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  const _DropdownField({
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: context.tSurface,
        borderRadius: const BorderRadius.all(kRadiusSm),
        border: Border.all(color: context.tBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: context.tTextMuted),
          style: TextStyle(fontSize: 12, color: context.tTextPrimary),
          dropdownColor: context.tSurface,
          items: items
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(labelFor(e)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Small inline action button used in the Device section.
class _SmallBtn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;

  const _SmallBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: const BorderRadius.all(kRadiusSm),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ]),
        ),
      );
}