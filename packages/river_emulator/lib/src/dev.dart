import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'core.dart';

typedef DeviceEmulatorFactory =
    DeviceEmulator Function(Device, Map<String, String>);

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

  int read(int addr, Mxlen mxlen) {
    throw TrapException(Trap.loadAccess, addr);
  }

  void write(int addr, int _value, Mxlen mxlen) {
    throw TrapException(Trap.storeAccess, addr);
  }
}
