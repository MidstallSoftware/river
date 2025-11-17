import 'bus.dart';
import 'dev.dart';

enum CacheAccessorMethod {
  mem('mem'),
  bus('bus');

  const CacheAccessorMethod(this.name);

  final String name;

  static CacheAccessorMethod? from(dynamic value) {
    if (value is CacheAccessorMethod) return value as CacheAccessorMethod;
    if (value is String) {
      for (final i in CacheAccessorMethod.values) {
        if (i.name == value) return i;
      }
    }
    return null;
  }
}

class CacheAccessor {
  final BusClientPort clientPort;
  final CacheAccessorMethod method;

  const CacheAccessor({required this.clientPort, required this.method});

  const CacheAccessor.mem(this.clientPort) : method = CacheAccessorMethod.mem;
  const CacheAccessor.bus(this.clientPort) : method = CacheAccessorMethod.bus;

  @override
  String toString() =>
      'CacheAccessor(clientPort: $clientPort, method: $method)';
}

class Cache {
  final int size;
  final int lineSize;
  final int ways;
  final CacheAccessor accessor;

  const Cache({
    required this.size,
    required this.lineSize,
    required this.ways,
    required this.accessor,
  });

  int get lines => size ~/ lineSize;

  @override
  String toString() =>
      'Cache(size: $size, lineSize: $lineSize, ways: $ways, accessor: $accessor)';
}

class L1iCache extends Cache {
  const L1iCache({
    required super.size,
    required super.lineSize,
    required super.ways,
    required super.accessor,
  });
}

class L1dCache extends Cache {
  const L1dCache({
    required super.size,
    required super.lineSize,
    required super.ways,
    required super.accessor,
  });
}

class L1Cache {
  final L1iCache? i;
  final L1dCache d;

  const L1Cache({required this.i, required this.d});

  const L1Cache.unified(this.d) : i = null;

  L1Cache.split({
    required CacheAccessor accessor,
    required int iSize,
    required int dSize,
    required int ways,
    required int lineSize,
  }) : i = L1iCache(
         size: iSize,
         lineSize: lineSize,
         ways: ways,
         accessor: CacheAccessor(
           clientPort: BusClientPort(
             name: 'l1icache',
             range: accessor.clientPort.range.shift(size: iSize),
             accessor: accessor.clientPort.accessor,
           ),
           method: accessor.method,
         ),
       ),
       d = L1dCache(
         size: dSize,
         lineSize: lineSize,
         ways: ways,
         accessor: CacheAccessor(
           clientPort: BusClientPort(
             name: 'l1dcache',
             range: accessor.clientPort.range.shift(offset: iSize, size: dSize),
             accessor: accessor.clientPort.accessor,
           ),
           method: accessor.method,
         ),
       );

  bool get unified => i == null;

  @override
  String toString() => 'L1Cache(i: $i, d: $d)';
}
