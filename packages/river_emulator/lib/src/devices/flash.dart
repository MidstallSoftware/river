import 'dart:io';
import 'dart:convert';

import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import '../core.dart';
import '../dev.dart';
import '../soc.dart';

class FlashEmulator extends DeviceEmulator {
  final List<int> data;
  bool enabled;

  FlashEmulator(super.config, this.data) : enabled = true;

  @override
  DeviceAccessorEmulator? get memAccessor => FlashAccessorEmulator(this);

  @override
  String toString() => 'FlashEmulator(config: $config)';

  static DeviceEmulator create(
    Device config,
    Map<String, String> options,
    RiverSoCEmulator _soc,
  ) {
    var data = List.filled(config.mmap!.size, 0);

    if (options.containsKey('file')) {
      data = File(options['file']!).readAsBytesSync();
    } else if (options.containsKey('bytes')) {
      final bytes = options['bytes']!;
      data = Iterable<int>.generate(bytes.length ~/ 2)
          .map((i) => int.parse(bytes.substring(i * 2, i * 2 + 2), radix: 16))
          .toList()
          .reversed
          .toList();
    }

    if (data.length < config.mmap!.size) {
      data = [...data, ...List.filled(config.mmap!.size - data.length, 0)];
    }

    return FlashEmulator(config, data);
  }
}

class FlashAccessorEmulator extends DeviceAccessorEmulator {
  final FlashEmulator rom;

  FlashAccessorEmulator(this.rom) : super(rom.config.accessor!);

  @override
  Future<int> read(int addr, int width) {
    if (!rom.enabled) throw TrapException(Trap.loadAccess, addr);
    int value = rom.data
        .getRange(addr, addr + width)
        .toList()
        .reversed
        .fold(0, (v, i) => (v << 8) | (i & 0xFF));
    return Future.value(value);
  }
}
