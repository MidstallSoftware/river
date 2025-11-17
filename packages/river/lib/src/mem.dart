import 'dev.dart';

enum MemoryAccess { read, write }

class MemoryError implements Exception {
  final int address;
  final MemoryAccess access;

  const MemoryError(this.address, this.access);
}

class MemoryBlock {
  final int start;
  final int size;
  final DeviceAccessor accessor;

  const MemoryBlock(this.start, this.size, this.accessor);

  int get end => start + size;

  String? access(int index, MemoryAccess access) {
    if (index > size || index < start) return null;

    return switch (access) {
      MemoryAccess.read => accessor.readPath(index),
      MemoryAccess.write => accessor.writePath(index),
    };
  }

  @override
  String toString() => 'MemoryBlock($start, $size, $accessor)';
}

class Mmu {
  final List<MemoryBlock> blocks;

  const Mmu({required this.blocks});

  String? access(int addr, MemoryAccess access) {
    for (final block in blocks) {
      if (block.start >= addr && block.end < addr) {
        return block.access(block.end - addr, access);
      }
    }

    return null;
  }

  @override
  String toString() => 'Mmu(blocks: $blocks)';
}
