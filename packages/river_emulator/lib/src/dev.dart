import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'core.dart';
import 'soc.dart';

typedef DeviceEmulatorFactory =
    DeviceEmulator Function(Device, Map<String, String>, RiverSoCEmulator);

class DeviceEmulator {
  final Device config;

  const DeviceEmulator(this.config);

  void reset() {}
  void increment() {}

  DeviceAccessorEmulator? get memAccessor {
    if (config.accessor != null && config.mmap != null)
      return DeviceFieldAccessorEmulator(this);
    return null;
  }

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

class DeviceFieldAccessorEmulator extends DeviceAccessorEmulator {
  final DeviceEmulator device;

  DeviceFieldAccessorEmulator(this.device) : super(device.config.accessor!);

  int readPath(String name) {
    throw TrapException(Trap.loadAccess, config.fieldAddress(name)!);
  }

  void writePath(String name, int _value) {
    throw TrapException(Trap.storeAccess, config.fieldAddress(name)!);
  }

  int read(int addr, Mxlen mxlen) {
    final fields = config.getFields(addr, mxlen.width);

    if (fields.isEmpty) {
      throw TrapException(Trap.loadAccess, addr);
    }

    final end = addr + mxlen.width;

    int result = 0;
    int offset = 0;
    for (final field in fields) {
      final fieldStart = offset;
      final fieldEnd = offset + field.width;
      offset = fieldEnd;

      if (fieldEnd <= addr || fieldStart >= end) continue;

      final overlapStart = addr > fieldStart ? addr : fieldStart;
      final overlapEnd = end < fieldEnd ? end : fieldEnd;
      final overlapBytes = overlapEnd - overlapStart;

      final sliceOffset = overlapStart - fieldStart;

      final fieldValue = readPath(field.name);

      final slice =
          (fieldValue >> (sliceOffset * 8)) & ((1 << (overlapBytes * 8)) - 1);

      final shift = (overlapStart - addr) * 8;

      result |= (slice << shift);
    }

    return result;
  }

  void write(int addr, int value, Mxlen mxlen) {
    final fields = config.getFields(addr, mxlen.width);

    if (fields.isEmpty) {
      throw TrapException(Trap.storeAccess, addr);
    }

    final end = addr + mxlen.width;

    int offset = 0;
    for (final field in fields) {
      final fieldStart = offset;
      final fieldEnd = offset + field.width;
      offset = fieldEnd;

      if (fieldEnd <= addr || fieldStart >= end) continue;

      final overlapStart = addr > fieldStart ? addr : fieldStart;
      final overlapEnd = end < fieldEnd ? end : fieldEnd;
      final overlapBytes = overlapEnd - overlapStart;

      final sliceOffset = overlapStart - fieldStart;

      final valueOffset = overlapStart - addr;

      final slice =
          (value >> (valueOffset * 8)) & ((1 << (overlapBytes * 8)) - 1);

      final result = slice << (sliceOffset * 8);

      writePath(field.name, result);
    }
  }
}
