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

class DeviceAccessor {
  final String path;
  final Map<int, DeviceField> fields;

  const DeviceAccessor(this.path, this.fields);

  DeviceField? getField(int addr) {
    var offset = 0;
    for (final entry in fields.entries) {
      final field = entry.value;
      if (addr >= offset && addr < offset + field.width) {
        return field;
      }
      offset += field.width;
    }
    return null;
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
    ClockConfig? clock,
  }) {
    path ??= '/$name';
    final accessor = fields != null ? DeviceAccessor(path, fields) : null;
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
