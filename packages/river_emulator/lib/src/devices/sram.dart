import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import '../core.dart';
import '../dev.dart';
import '../soc.dart';

class SramEmulator extends DeviceEmulator {
  List<int> data;

  SramEmulator(super.config) : data = List.filled(config.mmap!.size, 0);

  @override
  void reset() {
    data.fillRange(0, data.length, 0);
  }

  @override
  DeviceAccessorEmulator? get memAccessor => SramAccessorEmulator(this);

  @override
  String toString() => 'SramEmulator(config: $config)';

  static DeviceEmulator create(
    Device config,
    Map<String, String> _options,
    RiverSoCEmulator _soc,
  ) => SramEmulator(config);
}

class SramAccessorEmulator extends DeviceAccessorEmulator {
  final SramEmulator sram;

  SramAccessorEmulator(this.sram) : super(sram.config.accessor!);

  @override
  Future<int> read(int addr, int width) {
    int value = sram.data
        .getRange(addr, addr + width)
        .toList()
        .reversed
        .fold(0, (v, i) => (v << 8) | (i & 0xFF));
    return Future.value(value);
  }

  @override
  Future<void> write(int addr, int value, int width) async {
    for (int i = 0; i < width; i++) {
      final byte = (value >> (8 * i)) & 0xFF;

      sram.data[addr + i] = byte;
    }
  }
}
