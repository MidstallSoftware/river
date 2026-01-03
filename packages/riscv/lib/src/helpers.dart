class BitRange {
  final int start;
  final int end;

  const BitRange(this.start, this.end)
    : assert(start <= end, 'start must be greater than or equal to end');
  const BitRange.single(this.start) : end = start;

  int get width => end - start + 1;
  int get mask => (1 << width) - 1;

  BigInt get bigMask => (BigInt.one << width) - BigInt.one;

  int encode(int value) => (value & mask) << start;
  int decode(int value) => (value >> start) & mask;

  BigInt bigEncode(BigInt value) => (value & bigMask) << start;
  BigInt bigDecode(BigInt value) => (value >> start) & bigMask;

  @override
  String toString() => 'BitRange($start, $end)';
}

class BitStruct {
  final Map<String, BitRange> mapping;

  const BitStruct(this.mapping);

  Map<String, int> decode(int value) {
    final result = <String, int>{};
    mapping.forEach((name, range) {
      result[name] = range!.decode(value);
    });
    return result;
  }

  int encode(Map<String, int> fields) {
    int result = 0;
    fields.forEach((name, val) {
      final range = mapping[name];
      result |= range!.encode(val);
    });
    return result;
  }

  Map<String, int> bigDecode(BigInt value) {
    final result = <String, int>{};
    mapping.forEach((name, range) {
      result[name] = range!.bigDecode(value).toInt();
    });
    return result;
  }

  BigInt bigEncode(Map<String, int> fields) {
    BigInt result = BigInt.zero;
    fields.forEach((name, val) {
      final range = mapping[name];
      result |= range!.bigEncode(BigInt.from(val));
    });
    return result;
  }

  int getField(int value, String name) {
    final range = mapping[name];
    return range!.decode(value);
  }

  int setField(int value, String name, int fieldValue) {
    final range = mapping[name];
    value &= ~(range!.mask << range!.start);
    value |= range!.encode(fieldValue);
    return value;
  }

  int get mask {
    var map = <String, int>{};
    for (final field in mapping.entries) {
      map[field.key] = field.value.mask;
    }
    return encode(map);
  }

  int get width {
    var i = 0;
    mapping.forEach((name, val) {
      i = (val.end + 1) > i ? (val.end + 1) : i;
    });
    return i;
  }

  @override
  String toString() => 'BitStruct($mapping)';
}

int signExtend(int value, int bits) {
  final mask = (1 << bits) - 1;
  value &= mask;
  final signBit = 1 << (bits - 1);
  if ((value & signBit) != 0) {
    return value | ~mask;
  } else {
    return value;
  }
}
