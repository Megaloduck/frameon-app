import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../models/device_state.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_badge.dart';
import 'feature_screens.dart';
import 'setup_screen.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  int _selectedIndex = 0;

  static const _destinations = [
    _NavItem(
      icon: Icons.developer_board_outlined,
      selectedIcon: Icons.developer_board,
      label: 'Setup',
      color: AppColors.accent,
    ),
    _NavItem(
      icon: Icons.music_note_outlined,
      selectedIcon: Icons.music_note,
      label: 'Spotify',
      color: AppColors.spotify,
    ),
    _NavItem(
      icon: Icons.access_time_outlined,
      selectedIcon: Icons.access_time_filled,
      label: 'Clock',
      color: AppColors.clock,
    ),
    _NavItem(
      icon: Icons.gif_box_outlined,
      selectedIcon: Icons.gif_box,
      label: 'GIF',
      color: AppColors.gif,
    ),
    _NavItem(
      icon: Icons.timer_outlined,
      selectedIcon: Icons.timer,
      label: 'Pomodoro',
      color: AppColors.pomodoro,
    ),
  ];

  final _screens = const [
    SetupScreen(),
    SpotifyScreen(),
    ClockScreen(),
    GifScreen(),
    PomodoroScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      body: isWide ? _WideLayout(
        selectedIndex: _selectedIndex,
        destinations: _destinations,
        screens: _screens,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      ) : _NarrowLayout(
        selectedIndex: _selectedIndex,
        destinations: _destinations,
        screens: _screens,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      ),
    );
  }
}

// ── Wide layout (NavigationRail sidebar) ─────────────────────────────────

class _WideLayout extends ConsumerWidget {
  final int selectedIndex;
  final List<_NavItem> destinations;
  final List<Widget> screens;
  final ValueChanged<int> onDestinationSelected;

  const _WideLayout({
    required this.selectedIndex,
    required this.destinations,
    required this.screens,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(deviceStateProvider);

    return Row(
      children: [
        // ── Sidebar ──────────────────────────────────────────────────────
        Container(
          width: 72,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(right: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              // Logo mark
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: _LogoMark(),
              ),
              const Divider(height: 1),
              const Gap(8),
              // Nav items
              ...destinations.asMap().entries.map((e) {
                final i = e.key;
                final dest = e.value;
                final isSelected = selectedIndex == i;
                return _SidebarNavItem(
                  item: dest,
                  isSelected: isSelected,
                  onTap: () => onDestinationSelected(i),
                );
              }),
              const Spacer(),
              // Connection indicator at bottom
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _ConnectionDot(status: deviceState.connectionStatus),
              ),
            ],
          ),
        ),
        // ── Content ───────────────────────────────────────────────────────
        Expanded(
          child: IndexedStack(
            index: selectedIndex,
            children: screens,
          ),
        ),
      ],
    );
  }
}

// ── Narrow layout (BottomNavigationBar) ───────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final int selectedIndex;
  final List<_NavItem> destinations;
  final List<Widget> screens;
  final ValueChanged<int> onDestinationSelected;

  const _NarrowLayout({
    required this.selectedIndex,
    required this.destinations,
    required this.screens,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: onDestinationSelected,
          backgroundColor: AppColors.surface,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: destinations[selectedIndex].color,
          unselectedItemColor: AppColors.textMuted,
          selectedFontSize: 10,
          unselectedFontSize: 10,
          elevation: 0,
          items: destinations
              .map((d) => BottomNavigationBarItem(
                    icon: Icon(d.icon, size: 22),
                    activeIcon: Icon(d.selectedIcon, size: 22),
                    label: d.label,
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ── Sidebar nav item ─────────────────────────────────────────────────────

class _SidebarNavItem extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.label,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? item.color.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: item.color.withOpacity(0.25))
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? item.selectedIcon : item.icon,
                size: 22,
                color: isSelected ? item.color : AppColors.textMuted,
              ),
              const Gap(3),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? item.color : AppColors.textMuted,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Logo mark ─────────────────────────────────────────────────────────────

class _LogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.accentGlow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withOpacity(0.4)),
      ),
      child: const Center(
        child: Text(
          'M',
          style: TextStyle(
            fontFamily: 'SpaceMono',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}

// ── Connection dot (bottom of sidebar) ───────────────────────────────────

class _ConnectionDot extends StatelessWidget {
  final ConnectionStatus status;
  const _ConnectionDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ConnectionStatus.connected => AppColors.connected,
      ConnectionStatus.connecting => AppColors.connecting,
      ConnectionStatus.disconnected => AppColors.textMuted,
    };
    return Tooltip(
      message: switch (status) {
        ConnectionStatus.connected => 'Device connected',
        ConnectionStatus.connecting => 'Connecting…',
        ConnectionStatus.disconnected => 'No device',
      },
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

// ── Nav item data ─────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Color color;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.color,
  });
}
