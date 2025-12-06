import 'bus.dart';
import 'dev.dart';

class Cache {
  final int size;
  final int lineSize;
  final int ways;

  const Cache({required this.size, required this.lineSize, required this.ways});

  int get lines => size ~/ lineSize;

  @override
  String toString() => 'Cache(size: $size, lineSize: $lineSize, ways: $ways)';
}

class L1iCache extends Cache {
  const L1iCache({
    required super.size,
    required super.lineSize,
    required super.ways,
  });
}

class L1dCache extends Cache {
  const L1dCache({
    required super.size,
    required super.lineSize,
    required super.ways,
  });
}

class L1Cache {
  final L1iCache? i;
  final L1dCache d;

  const L1Cache({required this.i, required this.d});

  const L1Cache.unified(this.d) : i = null;

  L1Cache.split({
    required int iSize,
    required int dSize,
    required int ways,
    required int lineSize,
  }) : i = L1iCache(size: iSize, lineSize: lineSize, ways: ways),
       d = L1dCache(size: dSize, lineSize: lineSize, ways: ways);

  bool get unified => i == null;

  @override
  String toString() => 'L1Cache(i: $i, d: $d)';
}
