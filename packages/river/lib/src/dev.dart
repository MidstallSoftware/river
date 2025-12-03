import 'bus.dart';
import 'clock.dart';
import 'mem.dart';
import 'river_base.dart';

class DeviceField {
  final String name;
  final int width;

  const DeviceField(this.name, this.width);

  @override
  String toString() => 'DeviceField($name, $width)';
}

enum DeviceAccessorType { memory, io }

class DeviceAccessor {
  final String path;
  final Map<int, DeviceField> fields;
  final DeviceAccessorType type;

  const DeviceAccessor(
    this.path,
    this.fields, {
    this.type = DeviceAccessorType.io,
  });

  int? fieldAddress(String name) {
    var offset = 0;
    for (final entry in fields.entries) {
      final field = entry.value;
      if (name == field.name) {
        return offset;
      }
      offset += field.width;
    }
    return null;
  }

  DeviceField? getField(int addr) {
    var offset = 0;
    for (final entry in fields.entries) {
      final field = entry.value;
      if (addr >= offset && addr < (offset + field.width)) {
        return field;
      }
      offset += field.width;
    }
    return null;
  }

  List<DeviceField> getFields(int addr, int width) {
    final end = addr + width;

    var offset = 0;
    List<DeviceField> list = [];
    for (final entry in fields.entries) {
      final field = entry.value;

      final fieldStart = offset;
      final fieldEnd = offset + field.width;

      final overlaps = (addr < fieldEnd) && (end > fieldStart);

      if (overlaps) {
        list.add(field);
      }

      offset = fieldEnd;
    }
    return list;
  }

  String? readPath(int addr) {
    final field = getField(addr);
    if (field == null) return null;
    return '$path/${field.name}%read';
  }

  String? writePath(int addr) {
    final field = getField(addr);
    if (field == null) return null;
    return '$path/${field.name}%write';
  }

  @override
  String toString() => 'DeviceAccessor($path, $fields)';
}

class Device {
  final String name;
  final String compatible;
  final BusAddressRange? range;
  final List<int> interrupts;
  final DeviceAccessor? accessor;
  final BusClientPort? clientPort;
  final ClockConfig? clock;

  const Device({
    required this.name,
    required this.compatible,
    this.range,
    this.interrupts = const [],
    this.accessor,
    this.clientPort,
    this.clock,
  });

  factory Device.simple({
    required String name,
    required String compatible,
    String? path,
    BusAddressRange? range,
    List<int> interrupts = const [],
    Map<int, DeviceField>? fields,
    DeviceAccessorType type = DeviceAccessorType.memory,
    ClockConfig? clock,
  }) {
    path ??= '/$name';
    final accessor = fields != null
        ? DeviceAccessor(path, fields, type: type)
        : null;
    final clientPort = fields != null && range != null
        ? BusClientPort(
            name: path,
            range: range!,
            accessor: DeviceAccessor(path, fields),
          )
        : null;

    return Device(
      name: name,
      compatible: compatible,
      range: range,
      interrupts: interrupts,
      accessor: accessor,
      clientPort: clientPort,
      clock: clock,
    );
  }

  MemoryBlock? get mmap {
    if (range != null && accessor != null) {
      return MemoryBlock(range!.start, range!.end, accessor!);
    }
    return null;
  }

  @override
  String toString() =>
      'Device(name: \"$name\", compatible: \"$compatible\", range: $range,'
      ' interrupts: $interrupts, accessor: $accessor, clientPort: $clientPort, clock: $clock)';
}
