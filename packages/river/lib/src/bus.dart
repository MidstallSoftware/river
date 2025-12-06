import 'dev.dart';

enum BusArbitration { fixed, roundRobin, priority }

class BusAddressRange {
  final int start;
  final int size;

  const BusAddressRange(this.start, this.size);

  BusAddressRange.from(BusAddressRange base, {int offset = 0, int? size})
    : start = base.start + offset,
      size = size ?? base.size;

  bool contains(int addr) => addr >= start && addr < end;

  int get end => start + size;

  BusAddressRange shift({int offset = 0, int? size}) =>
      BusAddressRange(start + offset, size ?? this.size);

  @override
  String toString() => 'BusAddressRange(start: $start, end: $end, size: $size)';
}

abstract class BusPort {
  String get name;

  const BusPort();

  bool inRange(int addr);

  @override
  String toString() => 'BusPort($name)';
}

class BusClientPort extends BusPort {
  @override
  final String name;

  final BusAddressRange range;
  final DeviceAccessor accessor;

  const BusClientPort({
    required this.name,
    required this.range,
    required this.accessor,
  });

  factory BusClientPort.simple({
    required String name,
    required BusAddressRange range,
    required Map<int, DeviceField> fields,
  }) => BusClientPort(
    name: name,
    range: range,
    accessor: DeviceAccessor(name, fields),
  );

  @override
  bool inRange(int addr) => range.contains(addr);

  @override
  String toString() =>
      'BusClientPort(name: $name, range: $range, accessor: $accessor)';
}

class BusHostPort extends BusPort {
  @override
  final String name;

  const BusHostPort(this.name);

  @override
  bool inRange(int addr) => false;

  @override
  String toString() => 'BusHostPort($name)';
}

class BusRead {
  final int addr;
  final int width;
  const BusRead(this.addr, {this.width = 4});
}

class BusWrite {
  final int addr;
  final int width;

  const BusWrite(this.addr, {this.width = 4});
}
