import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'core.dart';
import 'dev.dart';

const kPageSize = 4096;

class MmuEmulator {
  final Mmu config;
  final Map<MemoryBlock, DeviceAccessorEmulator> devices;
  PagingMode mode;
  bool _pagingEnabled;
  int _pageTable;

  MmuEmulator(this.config, this.devices)
    : _pagingEnabled = false,
      _pageTable = 0,
      mode = PagingMode.bare;

  bool get pagingEnabled => config.hasPaging && _pagingEnabled;

  set pagingEnabled(bool value) {
    if (config.hasPaging) {
      _pagingEnabled = value;
    } else {
      throw TrapException.illegalInstruction();
    }
  }

  int get pageTable => _pageTable;

  set pageTable(int value) {
    if (config.hasPaging) {
      _pageTable = value;
    } else {
      throw TrapException.illegalInstruction();
    }
  }

  void configure(int modeId, int ppn) {
    final pmode =
        PagingMode.fromId(modeId) ?? (throw TrapException.illegalInstruction());

    if (!pmode.isSupported(config.mxlen)) {
      throw TrapException.illegalInstruction();
    }

    mode = pmode;
    pageTable = ppn * kPageSize;
    pagingEnabled = mode != PagingMode.bare;
  }

  void reset() {
    mode = PagingMode.bare;
    _pagingEnabled = false;
    _pageTable = 0;
  }

  int translate(
    int addr,
    MemoryAccess access, {
    PrivilegeMode privilege = PrivilegeMode.machine,
    bool sum = false,
    bool mxr = false,
  }) {
    if (!pagingEnabled || mode == PagingMode.bare) return addr;

    sum = sum && config.hasSum;
    mxr = mxr && config.hasMxr;

    final levels = mode.levels;
    final vpnBits = mode.vpnBits;
    final vpnMask = (1 << vpnBits) - 1;
    final vpn = List<int>.generate(
      levels,
      (i) => (addr >> (12 + vpnBits * i)) & vpnMask,
    );

    var a = pageTable;
    var i = levels - 1;

    while (true) {
      final pte = read(
        a + vpn[i] * config.mxlen.width,
        pageTranslate: false,
        privilege: privilege,
      );

      final v = pte & 1;
      final r = (pte >> 1) & 1;
      final w = (pte >> 2) & 1;
      final x = (pte >> 3) & 1;
      final u = (pte >> 4) & 1;

      if (v == 0 || (r == 0 && w == 1)) {
        throw TrapException(
          access == MemoryAccess.read ? Trap.loadAccess : Trap.storeAccess,
          addr,
        );
      }

      if (privilege == PrivilegeMode.user && u == 0) {
        throw TrapException(
          access == MemoryAccess.read ? Trap.loadAccess : Trap.storeAccess,
          addr,
        );
      }

      if (privilege == PrivilegeMode.supervisor && u == 1) {
        final isExec = access == MemoryAccess.instr;
        if (!sum && !isExec) {
          throw TrapException(
            access == MemoryAccess.read ? Trap.loadAccess : Trap.storeAccess,
            addr,
          );
        }
      }

      final isLeaf = (r == 1) || (x == 1);
      if (isLeaf) {
        bool allowed = false;
        switch (access) {
          case MemoryAccess.read:
            allowed = (r == 1) || (mxr && x == 1);
            break;
          case MemoryAccess.write:
            allowed = (w == 1);
            break;
          case MemoryAccess.instr:
            allowed = (x == 1);
            break;
        }

        if (!allowed) {
          throw TrapException(
            access == MemoryAccess.read ? Trap.loadAccess : Trap.storeAccess,
            addr,
          );
        }

        final ppn0 = (pte >> 10) & 0x1ff;
        final ppn1 = (pte >> 19) & 0x1ff;
        final ppn2 = (pte >> 28) & 0x3ff_ffff;

        final offset = addr & 0xfff;
        final phys = (ppn2 << 30) | (ppn1 << 21) | (ppn0 << 12) | offset;
        return phys;
      }

      i -= 1;

      if (i < 0) {
        throw TrapException(
          access == MemoryAccess.read ? Trap.loadAccess : Trap.storeAccess,
          addr,
        );
      }

      final nextPpn = (pte >> 10);
      a = nextPpn * kPageSize;
    }
  }

  int read(
    int addr, {
    PrivilegeMode privilege = PrivilegeMode.machine,
    bool pageTranslate = true,
    bool sum = false,
    bool mxr = false,
  }) {
    if (pageTranslate) {
      addr = translate(
        addr,
        MemoryAccess.read,
        privilege: privilege,
        sum: sum,
        mxr: mxr,
      );
    }

    for (final entry in devices.entries) {
      final block = entry.key;
      final dev = entry.value;

      if (addr >= block.start && addr < block.end) {
        return dev.read(addr - block.start, config.mxlen);
      }
    }

    throw TrapException(Trap.loadAccess, addr);
  }

  void write(
    int addr,
    int value, {
    PrivilegeMode privilege = PrivilegeMode.machine,
    bool pageTranslate = true,
    bool sum = false,
    bool mxr = false,
  }) {
    if (pageTranslate) {
      addr = translate(
        addr,
        MemoryAccess.write,
        privilege: privilege,
        sum: sum,
        mxr: mxr,
      );
    }

    for (final entry in devices.entries) {
      final block = entry.key;
      final dev = entry.value;

      if (addr >= block.start && addr < block.end) {
        dev.write(addr - block.start, value, config.mxlen);
        return;
      }
    }

    throw TrapException(Trap.storeAccess, addr);
  }

  @override
  String toString() =>
      'MmuEmulator(config: $config, devices: $devices, pagingEnabled: $pagingEnabled, pageTable: $pageTable)';
}
