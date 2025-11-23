import 'package:riscv/riscv.dart';
import 'dev.dart';

enum MemoryAccess { instr, read, write }

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
      _ => null,
    };
  }

  @override
  String toString() => 'MemoryBlock($start, $size, $accessor)';
}

class Mmu {
  final Mxlen mxlen;
  final List<MemoryBlock> blocks;
  final bool hasPaging;
  final bool hasSum;
  final bool hasMxr;

  const Mmu({
    required this.mxlen,
    required this.blocks,
    this.hasPaging = true,
    this.hasSum = false,
    this.hasMxr = false,
  });

  String? access(int addr, MemoryAccess access) {
    for (final block in blocks) {
      if (block.start >= addr && block.end < addr) {
        return block.access(block.end - addr, access);
      }
    }

    return null;
  }

  @override
  String toString() => 'Mmu(blocks: $blocks, hasPaging: $hasPaging)';
}
