// lib/features/device/device_event.dart
//
// EVT protocol v3 — joystick is now a layer z-order modifier.
//
//   EVT PRESET +/−/CHECK      encoder navigation
//   EVT LOCK <0|1>            encoder long hold
//   EVT JOY LAYER PREV        joystick up   → bringForward selected layer
//   EVT JOY LAYER NEXT        joystick down → sendBackward selected layer
//   EVT JOY OPACITY +/−       joystick X-axis → selected layer opacity
//   EVT JOY CENTER/PRESS/HOLD joystick dead-zone / button
//   EVT BTN 1 SYNC/RESET      global buttons
//   EVT BTN 2 DISCONNECT/RECONNECT
//   EVT BTN 3-5 S/L           layer-specific buttons

enum DeviceEventKind {
  // ── Encoder ──────────────────────────────────────────────────────────────
  presetNext,
  presetPrev,
  presetCheck,
  lockToggle,     // value = 0 unlocked, 1 locked

  // ── Joystick Y-axis — layer z-order ──────────────────────────────────────
  joyLayerPrev,   // joystick UP   → bringForward selected layer
  joyLayerNext,   // joystick DOWN → sendBackward selected layer

  // ── Joystick X-axis — selected layer opacity ──────────────────────────────
  opacityUp,
  opacityDown,

  // ── Joystick dead-zone / button ───────────────────────────────────────────
  joyCenter,
  joyPress,       // toggle layer visibility
  joyHold,        // save / confirm

  // ── BTN1 / BTN2 — Global ─────────────────────────────────────────────────
  btn1Sync,
  btn1Reset,
  btn2Disconnect,
  btn2Reconnect,

  // ── BTN3-5 — Layer-specific ───────────────────────────────────────────────
  btn3Short, btn3Long,
  btn4Short, btn4Long,
  btn5Short, btn5Long,
}

class DeviceEvent {
  final DeviceEventKind kind;
  final int value;   // lockToggle: 0/1.  All others: 0.

  const DeviceEvent({required this.kind, this.value = 0});

  // ── Parser ────────────────────────────────────────────────────────────────

  static DeviceEvent? tryParse(String line) {
    if (!line.startsWith('EVT ')) return null;
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) return null;

    switch (parts[1]) {

      case 'PRESET':
        switch (parts[2]) {
          case '+':     return const DeviceEvent(kind: DeviceEventKind.presetNext);
          case '-':     return const DeviceEvent(kind: DeviceEventKind.presetPrev);
          case 'CHECK': return const DeviceEvent(kind: DeviceEventKind.presetCheck);
          default: return null;
        }

      case 'LOCK': {
        final n = int.tryParse(parts[2]);
        if (n == null) return null;
        return DeviceEvent(kind: DeviceEventKind.lockToggle, value: n.clamp(0, 1));
      }

      case 'JOY':
        if (parts.length < 3) return null;
        switch (parts[2]) {

          // ── Layer z-order (Y-axis, new in v3) ──────────────────────────
          case 'LAYER':
            if (parts.length < 4) return null;
            if (parts[3] == 'PREV') return const DeviceEvent(kind: DeviceEventKind.joyLayerPrev);
            if (parts[3] == 'NEXT') return const DeviceEvent(kind: DeviceEventKind.joyLayerNext);
            return null;

          // ── Opacity (X-axis) ────────────────────────────────────────────
          case 'OPACITY':
            if (parts.length < 4) return null;
            if (parts[3] == '+') return const DeviceEvent(kind: DeviceEventKind.opacityUp);
            if (parts[3] == '-') return const DeviceEvent(kind: DeviceEventKind.opacityDown);
            return null;

          case 'CENTER': return const DeviceEvent(kind: DeviceEventKind.joyCenter);
          case 'PRESS':  return const DeviceEvent(kind: DeviceEventKind.joyPress);
          case 'HOLD':   return const DeviceEvent(kind: DeviceEventKind.joyHold);
          default: return null;
        }

      case 'BTN': {
        if (parts.length < 4) return null;
        final btn    = parts[2];
        final action = parts[3];
        switch (btn) {
          case '1':
            if (action == 'SYNC')  return const DeviceEvent(kind: DeviceEventKind.btn1Sync);
            if (action == 'RESET') return const DeviceEvent(kind: DeviceEventKind.btn1Reset);
            return null;
          case '2':
            if (action == 'DISCONNECT') return const DeviceEvent(kind: DeviceEventKind.btn2Disconnect);
            if (action == 'RECONNECT')  return const DeviceEvent(kind: DeviceEventKind.btn2Reconnect);
            return null;
          case '3':
            if (action == 'S') return const DeviceEvent(kind: DeviceEventKind.btn3Short);
            if (action == 'L') return const DeviceEvent(kind: DeviceEventKind.btn3Long);
            return null;
          case '4':
            if (action == 'S') return const DeviceEvent(kind: DeviceEventKind.btn4Short);
            if (action == 'L') return const DeviceEvent(kind: DeviceEventKind.btn4Long);
            return null;
          case '5':
            if (action == 'S') return const DeviceEvent(kind: DeviceEventKind.btn5Short);
            if (action == 'L') return const DeviceEvent(kind: DeviceEventKind.btn5Long);
            return null;
          default: return null;
        }
      }

      // ── DEBUG lines (e.g. EVT DEBUG JOYCAL x y) — silently ignored ──────
      case 'DEBUG':
        return null;

      default:
        return null;
    }
  }

  bool get isLocked   => kind == DeviceEventKind.lockToggle && value == 1;
  bool get isUnlocked => kind == DeviceEventKind.lockToggle && value == 0;

  @override
  String toString() => 'DeviceEvent(${kind.name}, value=$value)';
}