import 'dart:io';
import 'dart:convert';

import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import '../core.dart';
import '../dev.dart';
import '../soc.dart';

class BootromEmulator extends DeviceEmulator {
  final List<int> data;
  bool enabled;

  BootromEmulator(super.config, this.data) : enabled = true;

  @override
  DeviceAccessorEmulator? get memAccessor => BootromAccessorEmulator(this);

  @override
  String toString() => 'BootromEmulator(config: $config)';

  static DeviceEmulator create(
    Device config,
    Map<String, String> options,
    RiverSoCEmulator _soc,
  ) {
    var data = List.filled(config.mmap!.size, 0);

    if (options.containsKey('file')) {
      data = File(options['file']!).readAsBytesSync();
    } else if (options.containsKey('bytes')) {
      data = utf8.encode(options['bytes']!);
    }

    if (data.length < config.mmap!.size) {
      data = [...data, ...List.filled(config.mmap!.size - data.length, 0)];
    }

    return BootromEmulator(config, data);
  }
}

class BootromAccessorEmulator extends DeviceAccessorEmulator {
  final BootromEmulator rom;

  BootromAccessorEmulator(this.rom) : super(rom.config.accessor!);

  @override
  int read(int addr, Mxlen mxlen) {
    if (!rom.enabled) throw TrapException(Trap.loadAccess, addr);
    return rom.data
        .getRange(addr, addr + mxlen.width)
        .toList()
        .reversed
        .fold(0, (v, i) => (v << 8) | (i & 0xFF));
  }
}
