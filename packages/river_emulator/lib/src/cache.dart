import 'package:river/river.dart';

typedef CacheFill = Future<List<int>> Function(int addr, int size);
typedef CacheWriteback = Future<void> Function(int addr, int value, int size);

class CacheLineEmulator {
  final List<int> data;
  int tag;
  int lru;
  bool valid;

  CacheLineEmulator({
    required this.data,
    required this.tag,
    this.lru = 0,
    this.valid = true,
  });

  @override
  String toString() =>
      'CacheLineEmulator(tag: $tag, data: $data, lru: $lru, valid: $bool)';
}

class CacheEmulator {
  final Cache config;
  final CacheFill fill;
  final CacheWriteback writeback;
  final Map<int, List<CacheLineEmulator>> _lines;

  int get _sets => (config.size ~/ config.lineSize) ~/ config.ways;

  CacheEmulator(Cache config, {required this.fill, required this.writeback})
    : this.config = config,
      _lines = Map.fromEntries(
        List.generate(
          (config.size ~/ config.lineSize) ~/ config.ways,
          (i) => MapEntry(
            i,
            List.generate(
              config.ways,
              (_) => CacheLineEmulator(
                tag: 0,
                data: List.filled(config.lineSize, 0),
                valid: false,
              ),
            ),
          ),
        ),
      );

  int _setIndex(int addr) => (addr ~/ config.lineSize) % _sets;

  int _tag(int addr) => addr ~/ config.lineSize ~/ _sets;

  int _offset(int addr) => addr % config.lineSize;

  CacheLineEmulator? _findLine(int addr) {
    final set = _lines[_setIndex(addr)]!;
    final t = _tag(addr);

    for (final line in set) {
      if (line.valid && line.tag == t) {
        return line;
      }
    }

    return null;
  }

  CacheLineEmulator _allocateLine(int addr) {
    final set = _lines[_setIndex(addr)]!;
    final t = _tag(addr);

    set.sort((a, b) => a.lru.compareTo(b.lru));
    final victim = set.last;

    victim.tag = t;
    victim.valid = true;
    victim.lru = 0;

    return victim;
  }

  void _markUsed(CacheLineEmulator line) {
    final set = _lines.values.firstWhere((s) => s.contains(line));
    for (final l in set) {
      l.lru++;
    }
    line.lru = 0;
  }

  void reset() {
    for (final set in _lines.values) {
      for (final line in set) {
        line.valid = false;
        line.lru = 0;
      }
    }
  }

  Future<int>? read(int addr, int size) async {
    final line = _findLine(addr);
    if (line != null) {
      _markUsed(line);

      final off = _offset(addr);

      int value = 0;
      for (int i = 0; i < size; i++) {
        value |= (line.data[off + i] & 0xFF) << (8 * i);
      }
      return value;
    }

    final newLine = _allocateLine(addr);
    final base = addr - _offset(addr);
    final block = await fill(base, config.lineSize);
    newLine.data.setAll(0, block);

    _markUsed(newLine);

    final off = _offset(addr);
    int value = 0;
    for (int i = 0; i < size; i++) {
      value |= (newLine.data[off + i] & 0xFF) << (8 * i);
    }
    return value;
  }

  Future<void> write(int addr, int value, int size) async {
    final off = _offset(addr);

    if (off + size > config.lineSize) {
      for (int i = 0; i < size; i++) {
        final byte = (value >> (8 * i)) & 0xFF;
        await write(addr + i, byte, 1);
      }
      return;
    }

    CacheLineEmulator? line = _findLine(addr);

    if (line == null) {
      line = _allocateLine(addr);
      final base = addr - _offset(addr);

      final block = await fill(base, config.lineSize);
      line.data.setAll(0, block);
    }

    final safeOff = _offset(addr);
    for (int i = 0; i < size; i++) {
      final byte = (value >> (8 * i)) & 0xFF;
      line.data[safeOff + i] = byte;
    }

    _markUsed(line);

    await writeback(addr, value, size);
  }

  bool invalidate(int addr) {
    final line = _findLine(addr);
    if (line != null) {
      line.valid = false;
      return true;
    }
    return false;
  }

  @override
  String toString() => 'CacheEmulator($config)';
}
