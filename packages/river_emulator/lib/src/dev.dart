import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'core.dart';

typedef DeviceFactory = DeviceEmulator Function(Device);

class DeviceEmulator {
  final Device config;

  const DeviceEmulator(this.config);

  void reset() {}
  void increment() {}

  DeviceAccessorEmulator? get memAccessor => null;

  MapEntry<MemoryBlock, DeviceAccessorEmulator>? get mem {
    if (memAccessor == null || config.mmap == null) return null;
    return MapEntry(config.mmap!, memAccessor!);
  }

  @override
  String toString() => 'DeviceEmulator(config: $config)';
}

class DeviceAccessorEmulator {
  final DeviceAccessor config;

  const DeviceAccessorEmulator(this.config);

  int read(int addr) {
    throw TrapException(Trap.loadAccess, addr);
  }

  void write(int addr, int _value) {
    throw TrapException(Trap.storeAccess, addr);
  }
}
