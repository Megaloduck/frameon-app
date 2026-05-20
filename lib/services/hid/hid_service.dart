// lib/services/hid/hid_service.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// FrameonHidService — reads USB HID reports from the Frameon controller on
// Windows via SetupAPI + CreateFileW + ReadFile.
//
// Design decisions vs. the previous version
// ──────────────────────────────────────────
// ❌ REMOVED: HidD_GetHidGuid   — not in the Dart win32 package
// ❌ REMOVED: HidD_GetAttributes / HIDD_ATTRIBUTES — not in the win32 package
//
// ✅ REPLACED with:
//   • HID class GUID hardcoded (well-known constant, never changes)
//   • VID/PID matched by reading the device path string — Windows always
//     encodes it as "...vid_303a&pid_4001..." — no extra API calls needed
//   • Background isolate opens its own handle (avoids HANDLE-passing between
//     isolates, which is valid but adds complexity)
//   • Background isolate uses raw DynamicLibrary FFI for CreateFileW +
//     ReadFile — avoids any win32-package initialisation state issues in a
//     secondary Dart isolate
//
// pubspec.yaml requirements
// ─────────────────────────
//   dependencies:
//     ffi: ^2.1.0
//     win32: ^5.5.0        (only used in the main isolate for SetupAPI)
//
// Usage
// ─────
//   final hid = FrameonHidService();
//   if (await hid.open()) {
//     hid.reports.listen((r) { ... });
//   }
//   await hid.close();
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'hid_report.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const int _kVid        = 0x303A;
const int _kPid        = 0x4001;
const int _kReportSize = 8;       // report ID (1 byte) + payload (7 bytes)

// ─────────────────────────────────────────────────────────────────────────────
// FrameonHidService
// ─────────────────────────────────────────────────────────────────────────────

class FrameonHidService {
  final StreamController<FrameonHidReport> _ctrl =
      StreamController<FrameonHidReport>.broadcast();

  Stream<FrameonHidReport> get reports => _ctrl.stream;

  bool     _open  = false;
  Isolate? _isolate;
  ReceivePort? _port;

  // Joystick centre auto-calibrated from first idle reports.
  int _centreX = 2047, _centreY = 2047, _calibN = 0;
  void setJoyCentre(int x, int y) { _centreX = x; _centreY = y; }
  int get joyCentreX => _centreX;
  int get joyCentreY => _centreY;
  bool get isOpen => _open;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  Future<bool> open() async {
    if (_open) return true;

    final path = _findDevicePath();
    if (path == null) return false;

    _port = ReceivePort();
    _port!.listen(_onMessage);

    _isolate = await Isolate.spawn(
      _readerMain,
      _ReaderArgs(_port!.sendPort, path, _kReportSize),
    );

    _open = true;
    return true;
  }

  Future<void> close() async {
    _open = false;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.close();
    _port = null;
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  void _onMessage(dynamic msg) {
    if (msg is! List<int>) return;
    final report = FrameonHidReport.tryParse(msg);
    if (report == null || _ctrl.isClosed) return;

    // Auto-calibrate joystick centre from the first 30 idle samples
    // (no encoder movement, no buttons held).
    if (_calibN < 30 && report.encDelta == 0 && report.buttons == 0) {
      _centreX = ((_centreX * _calibN + report.joyX) / (_calibN + 1)).round();
      _centreY = ((_centreY * _calibN + report.joyY) / (_calibN + 1)).round();
      _calibN++;
    }

    _ctrl.add(report);
  }

  // ── Device discovery — SetupAPI (main isolate only) ─────────────────────────

  /// Find the device path of the Frameon HID controller.
  ///
  /// Windows always encodes VID and PID in the device path string, e.g.:
  ///   \\?\hid#vid_303a&pid_4001#5&1a2b3c4d&0&0000#{4d1e55b2-...}
  ///
  /// We match on `vid_303a` and `pid_4001` instead of calling
  /// HidD_GetAttributes (which requires hid.lib and isn't in the win32 package).
  static String? _findDevicePath() {
    // ── Fill HID class GUID: {4D1E55B2-F16F-11CF-88CB-001111000030} ─────────
    // This is the well-known Windows HID class GUID and never changes.
    final guid = calloc<GUID>();
    guid.ref.Data1 = 0x4D1E55B2;
    guid.ref.Data2 = 0xF16F;
    guid.ref.Data3 = 0x11CF;
    // Data4 is an Array<Uint8> in the win32 package
    const d4 = [0x88, 0xCB, 0x00, 0x11, 0x11, 0x00, 0x00, 0x30];
    for (int i = 0; i < 8; i++) guid.ref.Data4[i] = d4[i];

    final infoSet = SetupDiGetClassDevs(
      guid, nullptr, NULL,
      DIGCF_PRESENT | DIGCF_DEVICEINTERFACE,
    );

    if (infoSet == INVALID_HANDLE_VALUE) {
      calloc.free(guid);
      return null;
    }

    String? result;
    final iface = calloc<SP_DEVICE_INTERFACE_DATA>();
    iface.ref.cbSize = sizeOf<SP_DEVICE_INTERFACE_DATA>();
    int index = 0;

    while (SetupDiEnumDeviceInterfaces(
          infoSet, nullptr, guid, index++, iface) != 0) {
      // ── Query required buffer size ────────────────────────────────────────
      final pSize = calloc<Uint32>();
      SetupDiGetDeviceInterfaceDetail(
        infoSet, iface, nullptr, 0, pSize, nullptr,
      );
      final int bufSize = pSize.value;
      calloc.free(pSize);
      if (bufSize == 0) continue;

      // ── Allocate detail buffer and set cbSize ─────────────────────────────
      // SP_DEVICE_INTERFACE_DETAIL_DATA_W layout:
      //   DWORD  cbSize;           // bytes 0-3
      //   WCHAR  DevicePath[1];    // bytes 4+
      // cbSize must be: 8 on 64-bit Windows, 6 on 32-bit Windows.
      final buf = calloc<Uint8>(bufSize);
      buf.cast<Uint32>().value = sizeOf<IntPtr>() == 8 ? 8 : 6;

      if (SetupDiGetDeviceInterfaceDetail(
            infoSet, iface,
            buf.cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W>(),
            bufSize, nullptr, nullptr) != 0) {
        // DevicePath starts at byte offset 4 (after the DWORD cbSize).
        final pathPtr = Pointer<Utf16>.fromAddress(buf.address + 4);
        final path    = pathPtr.toDartString();

        if (_matchesDevice(path)) {
          result = path;
          calloc.free(buf);
          break;
        }
      }
      calloc.free(buf);
    }

    SetupDiDestroyDeviceInfoList(infoSet);
    calloc.free(iface);
    calloc.free(guid);
    return result;
  }

  /// True when [path] encodes our target VID and PID.
  static bool _matchesDevice(String path) {
    final p = path.toLowerCase();
    final vid = 'vid_${_kVid.toRadixString(16).padLeft(4, '0')}';
    final pid = 'pid_${_kPid.toRadixString(16).padLeft(4, '0')}';
    return p.contains(vid) && p.contains(pid);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background isolate
//
// Uses raw DynamicLibrary FFI so there are no win32-package initialisation
// concerns in a secondary isolate (all Dart isolates share the same native
// heap so DynamicLibrary.open is safe, but this keeps the isolate lean).
//
// ReadFile on a HID device opened without FILE_FLAG_OVERLAPPED blocks until
// the device sends a report — for HID that is at most one USB poll interval
// (1–4 ms).  Blocking in the isolate thread is intentional and correct.
// ─────────────────────────────────────────────────────────────────────────────

final class _ReaderArgs {
  final SendPort sendPort;
  final String   devicePath;
  final int      reportSize;
  const _ReaderArgs(this.sendPort, this.devicePath, this.reportSize);
}

void _readerMain(_ReaderArgs args) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');

  // CreateFileW
  final createFile = kernel32.lookupFunction<
    IntPtr Function(Pointer<Utf16>, Uint32, Uint32,
                    Pointer<Void>, Uint32, Uint32, IntPtr),
    int Function(Pointer<Utf16>, int, int,
                 Pointer<Void>, int, int, int)
  >('CreateFileW');

  // ReadFile
  final readFile = kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint8>, Uint32,
                   Pointer<Uint32>, Pointer<Void>),
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
  >('ReadFile');

  // CloseHandle
  final closeHandle = kernel32.lookupFunction<
    Int32 Function(IntPtr),
    int Function(int)
  >('CloseHandle');

  // Open the HID device (synchronous, no overlapped).
  final pathPtr = args.devicePath.toNativeUtf16();
  final handle  = createFile(
    pathPtr,
    0x80000000,   // GENERIC_READ
    0x00000003,   // FILE_SHARE_READ | FILE_SHARE_WRITE
    nullptr,
    3,            // OPEN_EXISTING
    0,            // no FILE_FLAG_OVERLAPPED — synchronous blocking reads
    0,
  );
  calloc.free(pathPtr);

  if (handle == -1 || handle == 0) return; // INVALID_HANDLE_VALUE

  final buf      = calloc<Uint8>(args.reportSize);
  final pRead    = calloc<Uint32>();

  try {
    while (true) {
      pRead.value = 0;
      final ok = readFile(handle, buf, args.reportSize, pRead, nullptr);
      if (ok == 0) break; // error or device disconnected — stop loop

      if (pRead.value == args.reportSize) {
        // Copy to List<int> (primitive — sendable across isolate boundary)
        args.sendPort.send(buf.asTypedList(args.reportSize).toList());
      }
    }
  } finally {
    closeHandle(handle);
    calloc.free(buf);
    calloc.free(pRead);
  }
}