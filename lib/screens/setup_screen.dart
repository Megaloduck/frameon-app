import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../services/providers.dart';
import '../services/web_serial_service.dart';
import '../theme/app_theme.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _ipController = TextEditingController();
  bool _obscurePassword = true;
  bool _isProvisioning = false;
  String? _statusMessage;

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serial = ref.watch(webSerialServiceProvider);
    final api = ref.watch(deviceApiServiceProvider);
    final deviceState = ref.watch(deviceStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('DEVICE SETUP'),
        actions: [
          if (deviceState.isConnected)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                label: Text(
                  'Connected — ${deviceState.deviceIp}',
                  style: const TextStyle(
                    color: AppColors.connected,
                    fontSize: 12,
                  ),
                ),
                backgroundColor: AppColors.accentGlow,
                side: const BorderSide(color: AppColors.accent, width: 0.5),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _SectionHeader(
                  icon: Icons.developer_board_outlined,
                  label: 'CONNECT YOUR MATRIX PANEL',
                ),
                const Gap(8),
                Text(
                  'Two ways to connect your ESP32 to the app. '
                  'Use USB provisioning the first time to set Wi-Fi credentials, '
                  'then switch to direct IP connection.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Gap(32),

                // ── Option 1: USB / WebSerial ──────────────────────────────
                _OptionCard(
                  index: '01',
                  title: 'USB provisioning',
                  subtitle: 'Send Wi-Fi credentials over USB (browser only)',
                  accentColor: AppColors.accent,
                  available: serial.isAvailable,
                  unavailableNote: 'Requires a Chromium browser (Chrome, Edge, Arc)',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (serial.status == WebSerialStatus.connected) ...[
                        _SerialLog(messages: serial.log),
                        const Gap(16),
                        _WifiCredentialsForm(
                          ssidController: _ssidController,
                          passwordController: _passwordController,
                          obscurePassword: _obscurePassword,
                          onToggleObscure: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        const Gap(16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isProvisioning ? null : () => _provision(serial, api),
                            child: _isProvisioning
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.bg,
                                    ),
                                  )
                                : const Text('Send credentials & get IP'),
                          ),
                        ),
                        if (_statusMessage != null) ...[
                          const Gap(10),
                          Text(
                            _statusMessage!,
                            style: TextStyle(
                              fontSize: 13,
                              color: _statusMessage!.startsWith('✓')
                                  ? AppColors.connected
                                  : AppColors.disconnected,
                            ),
                          ),
                        ],
                        const Gap(8),
                        TextButton.icon(
                          onPressed: serial.disconnect,
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Disconnect port'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                          ),
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: serial.status == WebSerialStatus.requestingPort ||
                                    serial.status == WebSerialStatus.connecting
                                ? null
                                : () => serial.requestPort(),
                            icon: const Icon(Icons.usb, size: 18),
                            label: Text(
                              serial.status == WebSerialStatus.requestingPort
                                  ? 'Waiting for port selection…'
                                  : serial.status == WebSerialStatus.connecting
                                      ? 'Opening port…'
                                      : 'Select USB port',
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.accent),
                              foregroundColor: AppColors.accent,
                            ),
                          ),
                        ),
                        const Gap(10),
                        Text(
                          'Connect your ESP32 via USB-C, then click above to select the COM/tty port.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                const Gap(16),

                // ── Option 2: Direct IP ────────────────────────────────────
                _OptionCard(
                  index: '02',
                  title: 'Direct IP connection',
                  subtitle: 'Connect over Wi-Fi if you already know the device IP',
                  accentColor: AppColors.clock,
                  available: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          hintText: '192.168.1.xxx',
                          prefixIcon: Icon(Icons.wifi, size: 18, color: AppColors.textMuted),
                          labelText: 'Device IP address',
                        ),
                        keyboardType: TextInputType.url,
                      ),
                      const Gap(12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _ipController.text.isEmpty
                              ? null
                              : () => _connectByIp(api),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.clock,
                          ),
                          child: const Text('Connect'),
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(40),

                // ── Firmware hint ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 15, color: AppColors.textMuted),
                          const Gap(6),
                          Text(
                            'ESP32 SERIAL PROTOCOL',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const Gap(10),
                      _CodeLine('Serial.begin(115200);'),
                      _CodeLine('// Reads JSON on Serial port:'),
                      _CodeLine('// {"cmd":"wifi","ssid":"x","password":"y"}'),
                      _CodeLine('// Responds: "IP:192.168.1.42"'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _provision(WebSerialService serial, dynamic api) async {
    if (_ssidController.text.isEmpty) return;
    setState(() {
      _isProvisioning = true;
      _statusMessage = null;
    });

    await serial.sendWifiCredentials(_ssidController.text, _passwordController.text);
    final ip = await serial.requestDeviceIp();

    if (ip != null && mounted) {
      final connected = await api.connect(ip);
      setState(() {
        _isProvisioning = false;
        _statusMessage = connected
            ? '✓ Connected to device at $ip'
            : '✗ Device found at $ip but API not responding';
      });
    } else {
      setState(() {
        _isProvisioning = false;
        _statusMessage = '✗ No IP response — check firmware serial output';
      });
    }
  }

  Future<void> _connectByIp(dynamic api) async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    await api.connect(ip);
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const Gap(8),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.accent,
          letterSpacing: 1.2,
        )),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String index;
  final String title;
  final String subtitle;
  final Color accentColor;
  final bool available;
  final String? unavailableNote;
  final Widget child;

  const _OptionCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.available,
    required this.child,
    this.unavailableNote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: available ? accentColor.withOpacity(0.3) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                index,
                style: TextStyle(
                  fontFamily: 'SpaceMono',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentColor.withOpacity(0.6),
                ),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              if (!available)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('BROWSER ONLY',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5)),
                ),
            ],
          ),
          if (!available && unavailableNote != null) ...[
            const Gap(12),
            Text(unavailableNote!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted)),
          ] else ...[
            const Gap(16),
            child,
          ],
        ],
      ),
    );
  }
}

class _WifiCredentialsForm extends StatelessWidget {
  final TextEditingController ssidController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;

  const _WifiCredentialsForm({
    required this.ssidController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: ssidController,
          decoration: const InputDecoration(
            labelText: 'Wi-Fi SSID',
            prefixIcon: Icon(Icons.wifi, size: 18, color: AppColors.textMuted),
          ),
        ),
        const Gap(10),
        TextField(
          controller: passwordController,
          obscureText: obscurePassword,
          decoration: InputDecoration(
            labelText: 'Wi-Fi Password',
            prefixIcon:
                const Icon(Icons.lock_outline, size: 18, color: AppColors.textMuted),
            suffixIcon: IconButton(
              onPressed: onToggleObscure,
              icon: Icon(
                obscurePassword ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SerialLog extends StatelessWidget {
  final List<WebSerialMessage> messages;
  const _SerialLog({required this.messages});

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 120,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.builder(
        reverse: true,
        itemCount: messages.length,
        itemBuilder: (_, i) {
          final msg = messages[messages.length - 1 - i];
          return Text(
            '${msg.isOutgoing ? "→" : "←"} ${msg.text}',
            style: TextStyle(
              fontFamily: 'SpaceMono',
              fontSize: 11,
              color: msg.isOutgoing ? AppColors.accent : AppColors.textSecondary,
            ),
          );
        },
      ),
    );
  }
}

class _CodeLine extends StatelessWidget {
  final String code;
  const _CodeLine(this.code);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Text(
        code,
        style: const TextStyle(
          fontFamily: 'SpaceMono',
          fontSize: 12,
          color: AppColors.textSecondary,
          height: 1.6,
        ),
      ),
    );
  }
}
