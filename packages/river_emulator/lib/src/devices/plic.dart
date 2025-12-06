import 'dart:async';
import 'package:river/river.dart';

import '../dev.dart';
import '../soc.dart';

class RiscVPlicEmulator extends DeviceEmulator {
  final int numSources;
  final List<int> _priority;
  final Map<int, int> _enable = {};
  final Map<int, int> _threshold = {};

  int _pending = 0;

  RiscVPlicEmulator(super.config, {this.numSources = 32})
    : _priority = List<int>.filled(33, 1);

  void setPriority(int i, int value) {
    _priority[i] = value;
  }

  void setSourcePending(int source, bool level) {
    if (source <= 0 || source > numSources) return;

    if (level) {
      _pending |= (1 << source);
    } else {
      _pending &= ~(1 << source);
    }
  }

  int _findBest(int hartId) {
    final enableMask = _enable[hartId] ?? 0;
    final threshold = _threshold[hartId] ?? 0;

    int best = 0;
    int bestPrio = 0;

    for (int id = 1; id <= numSources; id++) {
      final mask = 1 << id;
      if ((_pending & mask) == 0) continue;
      if ((enableMask & mask) == 0) continue;

      final prio = _priority[id];
      if (prio <= threshold) continue;

      if (prio >= bestPrio) {
        bestPrio = prio;
        best = id;
      }
    }

    return best;
  }

  @override
  Map<int, bool> interrupts(int hartId) {
    final best = _findBest(hartId);
    return {0: best != 0};
  }

  int claim(int hartId) {
    final id = _findBest(hartId);
    if (id != 0) _pending &= ~(1 << id);
    return id;
  }

  void complete(int hartId, int id) {
    if (id <= 0 || id > numSources) return;
    _pending &= ~(1 << id);
  }

  @override
  void reset() {
    for (int i = 0; i < _priority.length; i++) _priority[i] = 1;
    _pending = 0;
    _enable.clear();
    _threshold.clear();
  }

  @override
  DeviceAccessorEmulator? get memAccessor => RiscVPlicAccessorEmulator(this);

  static DeviceEmulator create(
    Device config,
    Map<String, String> options,
    RiverSoCEmulator _soc,
  ) {
    final sources = int.tryParse(options['sources'] ?? '') ?? 32;
    return RiscVPlicEmulator(config, numSources: sources);
  }
}

class RiscVPlicAccessorEmulator
    extends DeviceFieldAccessorEmulator<RiscVPlicEmulator> {
  RiscVPlicAccessorEmulator(super.device);

  int _parseHart(String name) {
    final match = RegExp(r'cpu(\d+)').firstMatch(name);
    if (match == null) return 0;
    return int.parse(match.group(1)!);
  }

  @override
  Future<int> readPath(String name) async {
    if (name == 'priority') return device._priority[1];
    if (name == 'pending') return device._pending;

    if (name.startsWith('enable_cpu')) {
      final hart = _parseHart(name);
      return device._enable[hart] ?? 0;
    }

    if (name.startsWith('threshold_cpu')) {
      final hart = _parseHart(name);
      return device._threshold[hart] ?? 0;
    }

    if (name.startsWith('claim_cpu')) {
      final hart = _parseHart(name);
      return device.claim(hart);
    }

    return 0;
  }

  @override
  Future<void> writePath(String name, int value) async {
    value &= 0xFFFFFFFF;

    if (name == 'priority') {
      device._priority[1] = value & 0x7;
      return;
    }

    if (name.startsWith('enable_cpu')) {
      final hart = _parseHart(name);
      device._enable[hart] = value;
      return;
    }

    if (name.startsWith('threshold_cpu')) {
      final hart = _parseHart(name);
      device._threshold[hart] = value & 0x7;
      return;
    }

    if (name.startsWith('claim_cpu')) {
      final hart = _parseHart(name);
      device.complete(hart, value);
      return;
    }
  }
}
