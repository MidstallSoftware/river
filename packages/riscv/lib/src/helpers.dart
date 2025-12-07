class BitRange {
  final int start;
  final int end;

  const BitRange(this.start, this.end)
    : assert(start <= end, 'start must be greater than or equal to end');
  const BitRange.single(this.start) : end = start;

  int get width => end - start + 1;
  int get mask => (1 << width) - 1;

  int encode(int value) => (value & mask) << start;
  int decode(int value) => (value >> start) & mask;

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
