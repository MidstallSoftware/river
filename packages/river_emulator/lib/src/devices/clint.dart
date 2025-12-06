import 'dart:async';
import 'dart:math';

import 'package:river/river.dart';

import '../dev.dart';
import '../soc.dart';

class RiscVClintEmulator extends DeviceEmulator {
  int msip = 0;
  int _mtimecmp = 0;
  int _mtimeBase = 0;

  final Stopwatch _stopwatch = Stopwatch();

  RiscVClintEmulator(super.config) {
    _stopwatch.start();
  }

  int get mtimecmp => _mtimecmp;

  set mtimecmp(int value) {
    _mtimecmp = value;
  }

  int get mtime {
    final hz = config.clock?.baseFreqHz ?? 0;
    if (hz <= 0) {
      return _mtimeBase + _stopwatch.elapsedMicroseconds;
    }

    final elapsedUs = _stopwatch.elapsedMicroseconds;
    final ticks = elapsedUs * hz ~/ 1000000;
    return _mtimeBase + ticks;
  }

  set mtime(int value) {
    _mtimeBase = value;
    _stopwatch
      ..reset()
      ..start();
  }

  bool get softwareInterruptPending => (msip & 0x1) != 0;

  bool get timerInterruptPending => mtimecmp != 0 && mtime >= mtimecmp;

  @override
  Map<int, bool> interrupts(int hartId) {
    return {0: softwareInterruptPending, 1: timerInterruptPending};
  }

  @override
  void reset() {
    msip = 0;
    _mtimecmp = 0;
    _mtimeBase = 0;
    _stopwatch
      ..reset()
      ..start();
  }

  @override
  DeviceAccessorEmulator? get memAccessor => RiscVClintAccessorEmulator(this);

  static DeviceEmulator create(
    Device config,
    Map<String, String> options,
    RiverSoCEmulator _soc,
  ) {
    return RiscVClintEmulator(config);
  }
}

class RiscVClintAccessorEmulator
    extends DeviceFieldAccessorEmulator<RiscVClintEmulator> {
  RiscVClintAccessorEmulator(super.device);

  @override
  Future<int> readPath(String name) async {
    switch (name) {
      case 'msip':
        return device.msip & 0xFFFFFFFF;
      case 'mtimecmp':
        return device.mtimecmp;
      case 'mtime':
        return device.mtime;
    }
    return 0;
  }

  @override
  Future<void> writePath(String name, int value) async {
    switch (name) {
      case 'msip':
        device.msip = value & 0x1;
        break;
      case 'mtimecmp':
        device.mtimecmp = value;
        break;
      case 'mtime':
        device.mtime = value;
        break;
    }
  }
}
