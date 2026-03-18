import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../models/device_state.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_badge.dart';

// ── Shared placeholder card ───────────────────────────────────────────────

class _ComingSoonCard extends StatelessWidget {
  final String title;
  final String description;
  final Color accentColor;
  final IconData icon;
  final List<String> plannedFeatures;

  const _ComingSoonCard({
    required this.title,
    required this.description,
    required this.accentColor,
    required this.icon,
    required this.plannedFeatures,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withOpacity(0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const Gap(20),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .displayMedium
                      ?.copyWith(fontSize: 20)),
              const Gap(6),
              Text(description,
                  style: Theme.of(context).textTheme.bodyMedium),
              const Gap(24),
              Text('PLANNED FEATURES',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: accentColor, letterSpacing: 1.2)),
              const Gap(12),
              ...plannedFeatures.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Gap(10),
                      Text(f,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Disconnected overlay ──────────────────────────────────────────────────

class _DisconnectedOverlay extends StatelessWidget {
  const _DisconnectedOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.developer_board_off_outlined,
              size: 40, color: AppColors.textMuted),
          const Gap(16),
          Text('No device connected',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.textMuted)),
          const Gap(8),
          Text('Go to Setup to connect your ESP32 matrix panel',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ── Spotify Screen ────────────────────────────────────────────────────────

class SpotifyScreen extends ConsumerWidget {
  const SpotifyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(deviceStateProvider).isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SPOTIFY'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: ConnectionBadge(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: isConnected
            ? const _ComingSoonCard(
                title: 'Spotify Control',
                description:
                    'Mirror your Spotify playback on the LED matrix. '
                    'Shows album art (scaled to 32×64), track name, and '
                    'playback controls.',
                accentColor: AppColors.spotify,
                icon: Icons.music_note_outlined,
                plannedFeatures: [
                  'OAuth2 login — authorize via browser',
                  'Album art scaled & dithered to 32×64 pixels',
                  'Play / pause / previous / next controls',
                  'Scrolling track name & artist on matrix',
                  'Auto-push state to ESP32 on track change',
                ],
              )
            : const _DisconnectedOverlay(),
      ),
    );
  }
}

// ── Clock Screen ──────────────────────────────────────────────────────────

class ClockScreen extends ConsumerWidget {
  const ClockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceApiServiceProvider);
    final isConnected = ref.watch(deviceStateProvider).isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CLOCK'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: ConnectionBadge(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: isConnected
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick toggles available immediately
                  _QuickClockToggles(device: device),
                  const Gap(24),
                  const _ComingSoonCard(
                    title: 'Clock & Calendar',
                    description:
                        'Full-screen clock on the matrix with NTP sync, '
                        'date display, and customizable format.',
                    accentColor: AppColors.clock,
                    icon: Icons.access_time_outlined,
                    plannedFeatures: [
                      '12H / 24H format toggle',
                      'NTP time sync (configurable server)',
                      'Date display (day / month)',
                      'Timezone selector',
                      'Custom font styles on matrix',
                    ],
                  ),
                ],
              )
            : const _DisconnectedOverlay(),
      ),
    );
  }
}

class _QuickClockToggles extends StatefulWidget {
  final dynamic device;
  const _QuickClockToggles({required this.device});

  @override
  State<_QuickClockToggles> createState() => _QuickClockTogglesState();
}

class _QuickClockTogglesState extends State<_QuickClockToggles> {
  bool _is24h = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 18, color: AppColors.clock),
          const Gap(10),
          const Text('24-hour format',
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          const Spacer(),
          Switch(
            value: _is24h,
            activeColor: AppColors.clock,
            onChanged: (v) {
              setState(() => _is24h = v);
              widget.device.setClockFormat(v);
            },
          ),
        ],
      ),
    );
  }
}

// ── GIF Screen ────────────────────────────────────────────────────────────

class GifScreen extends ConsumerWidget {
  const GifScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(deviceStateProvider).isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GIF DISPLAY'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: ConnectionBadge(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: isConnected
            ? const _ComingSoonCard(
                title: 'GIF Player',
                description:
                    'Upload GIF animations to the ESP32 filesystem and '
                    'play them on the LED matrix. Optimized with Larry Bank\'s '
                    'AnimatedGIF library.',
                accentColor: AppColors.gif,
                icon: Icons.gif_box_outlined,
                plannedFeatures: [
                  'Upload GIF files to ESP32 SPIFFS via HTTP',
                  'Browse & manage stored GIFs',
                  'Preview GIF in app before displaying',
                  'Auto-scale to 32×64 resolution',
                  'Loop / single-play mode',
                ],
              )
            : const _DisconnectedOverlay(),
      ),
    );
  }
}

// ── Pomodoro Screen ───────────────────────────────────────────────────────

class PomodoroScreen extends ConsumerWidget {
  const PomodoroScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceApiServiceProvider);
    final isConnected = ref.watch(deviceStateProvider).isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POMODORO'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: ConnectionBadge(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: isConnected
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PomodoroControls(device: device),
                  const Gap(24),
                  const _ComingSoonCard(
                    title: 'Pomodoro Timer',
                    description:
                        'Full-screen countdown timer on the matrix. '
                        'Control it from the app or let it run autonomously.',
                    accentColor: AppColors.pomodoro,
                    icon: Icons.timer_outlined,
                    plannedFeatures: [
                      'Configurable work / break durations',
                      'Start, pause, reset from app',
                      'Visual progress bar on matrix',
                      'Session counter display',
                      'Alert animation when time is up',
                    ],
                  ),
                ],
              )
            : const _DisconnectedOverlay(),
      ),
    );
  }
}

class _PomodoroControls extends StatelessWidget {
  final dynamic device;
  const _PomodoroControls({required this.device});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.pomodoro.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 18, color: AppColors.pomodoro),
          const Gap(10),
          const Text('Timer controls',
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          const Spacer(),
          _CmdButton(
            icon: Icons.play_arrow,
            color: AppColors.pomodoro,
            onTap: () => device.pomodoroCommand('start'),
          ),
          const Gap(8),
          _CmdButton(
            icon: Icons.pause,
            color: AppColors.textSecondary,
            onTap: () => device.pomodoroCommand('pause'),
          ),
          const Gap(8),
          _CmdButton(
            icon: Icons.replay,
            color: AppColors.textSecondary,
            onTap: () => device.pomodoroCommand('reset'),
          ),
        ],
      ),
    );
  }
}

class _CmdButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CmdButton(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
