import 'package:riscv/riscv.dart';
import 'core.dart';

abstract class Csr {
  final int address;

  const Csr(this.address);

  int read(RiverCoreEmulator core);
  void write(RiverCoreEmulator core, int value);
}

class SimpleCsr extends Csr {
  int value = 0;

  SimpleCsr(super.address);

  @override
  int read(RiverCoreEmulator core) => value;

  @override
  void write(RiverCoreEmulator core, int newValue) {
    value = newValue;
  }
}

class ReadOnlyCsr extends Csr {
  final int value;

  const ReadOnlyCsr(super.address, this.value);

  @override
  int read(RiverCoreEmulator core) => value;

  @override
  void write(RiverCoreEmulator _core, int _value) {
    throw TrapException.illegalInstruction();
  }
}

class MaskedCsr extends Csr {
  int value = 0;
  final int writableMask;

  MaskedCsr(super.address, this.writableMask);

  @override
  int read(RiverCoreEmulator core) => value;

  @override
  void write(RiverCoreEmulator core, int newValue) {
    value = (value & ~writableMask) | (newValue & writableMask);
  }
}

class LinkCsr extends Csr {
  final Csr target;
  final int? mask;
  final bool writable;

  const LinkCsr(super.address, this.target, {this.mask, this.writable = true});

  @override
  int read(RiverCoreEmulator core) {
    final value = target.read(core);
    return mask != null ? (value & mask!) : value;
  }

  @override
  void write(RiverCoreEmulator core, int newValue) {
    if (!writable) {
      throw TrapException.illegalInstruction();
    }

    if (mask != null) {
      final masked = newValue & mask!;
      final preserved = target.read(core) & ~mask!;
      target.write(core, preserved | masked);
    } else {
      target.write(core, newValue);
    }
  }
}

class IdCsr extends Csr {
  const IdCsr(super.address);

  @override
  int read(RiverCoreEmulator core) => switch (CsrAddress.find(address)) {
    CsrAddress.mvendorid => core.config.vendorId,
    CsrAddress.marchid => core.config.archId,
    CsrAddress.mimpid => core.config.impId,
    CsrAddress.mhartid => core.config.hartId,
    CsrAddress.misa =>
      core.config.extensions.map((ext) => ext.mask).fold(0, (t, i) => t | i) |
          core.config.mxlen.misa |
          ((core.config.hasSupervisor ? 1 : 0) << 18) |
          ((core.config.hasUser ? 1 : 0) << 20),
    _ => throw TrapException.illegalInstruction(),
  };

  @override
  void write(RiverCoreEmulator _core, int _value) {
    throw TrapException.illegalInstruction();
  }

  static const List<CsrAddress> registers = [
    CsrAddress.mvendorid,
    CsrAddress.marchid,
    CsrAddress.mimpid,
    CsrAddress.mhartid,
    CsrAddress.misa,
  ];
}

class CsrFile {
  final Mxlen mxlen;
  final Map<int, Csr> csrs = {};

  CsrFile(this.mxlen, {bool hasSupervisor = false, bool hasUser = false}) {
    for (final csr in IdCsr.registers) csrs[csr.address] = IdCsr(csr.address);

    csrs[CsrAddress.mstatus.address] = MaskedCsr(
      CsrAddress.mstatus.address,
      0xFFFFFFFF,
    );

    csrs[CsrAddress.mie.address] = SimpleCsr(CsrAddress.mie.address);
    csrs[CsrAddress.mip.address] = SimpleCsr(CsrAddress.mip.address);

    csrs[CsrAddress.mtvec.address] = MaskedCsr(
      CsrAddress.mtvec.address,
      0xFFFFFFFC,
    );
    csrs[CsrAddress.mscratch.address] = SimpleCsr(CsrAddress.mscratch.address);
    csrs[CsrAddress.mepc.address] = SimpleCsr(CsrAddress.mepc.address);
    csrs[CsrAddress.mcause.address] = SimpleCsr(CsrAddress.mcause.address);
    csrs[CsrAddress.mtval.address] = SimpleCsr(CsrAddress.mtval.address);

    csrs[CsrAddress.satp.address] = MaskedCsr(
      CsrAddress.satp.address,
      0xFFFFFFFF,
    );

    if (hasSupervisor) _initSupervisor();
    if (hasUser) _initUser();
  }

  void _initSupervisor() {
    final mstatus = csrs[CsrAddress.mstatus.address]!;
    final mie = csrs[CsrAddress.mie.address]!;
    final mip = csrs[CsrAddress.mip.address]!;

    const sstatusMask = 0x800DE133;
    csrs[CsrAddress.sstatus.address] = LinkCsr(
      CsrAddress.sstatus.address,
      mstatus,
      mask: sstatusMask,
      writable: true,
    );

    const supervisorInterruptMask = 0x222;
    csrs[CsrAddress.sie.address] = LinkCsr(
      CsrAddress.sie.address,
      mie,
      mask: supervisorInterruptMask,
    );

    csrs[CsrAddress.sip.address] = LinkCsr(
      CsrAddress.sip.address,
      mip,
      mask: supervisorInterruptMask,
    );

    csrs[CsrAddress.stvec.address] = MaskedCsr(
      CsrAddress.stvec.address,
      0xFFFFFFFC,
    );
    csrs[CsrAddress.sscratch.address] = SimpleCsr(CsrAddress.sscratch.address);
    csrs[CsrAddress.sepc.address] = SimpleCsr(CsrAddress.sepc.address);
    csrs[CsrAddress.scause.address] = SimpleCsr(CsrAddress.scause.address);
    csrs[CsrAddress.stval.address] = SimpleCsr(CsrAddress.stval.address);

    csrs[CsrAddress.satp.address] = MaskedCsr(
      CsrAddress.satp.address,
      0xFFFFFFFF,
    );
  }

  void _initUser() {
    final mstatus = csrs[CsrAddress.mstatus.address]!;
    const ustatusMask = 0x11;
    csrs[CsrAddress.ustatus.address] = LinkCsr(
      CsrAddress.ustatus.address,
      mstatus,
      mask: ustatusMask,
      writable: true,
    );

    csrs[CsrAddress.utvec.address] = MaskedCsr(
      CsrAddress.utvec.address,
      0xFFFFFFFC,
    );

    csrs[CsrAddress.uscratch.address] = SimpleCsr(CsrAddress.uscratch.address);
    csrs[CsrAddress.uepc.address] = SimpleCsr(CsrAddress.uepc.address);
    csrs[CsrAddress.ucause.address] = SimpleCsr(CsrAddress.ucause.address);
    csrs[CsrAddress.utval.address] = SimpleCsr(CsrAddress.utval.address);

    final mie = csrs[CsrAddress.mie.address]!;
    final mip = csrs[CsrAddress.mip.address]!;

    const userInterruptMask = 0x111;
    csrs[CsrAddress.uie.address] = LinkCsr(
      CsrAddress.uie.address,
      mie,
      mask: userInterruptMask,
    );
    csrs[CsrAddress.uip.address] = LinkCsr(
      CsrAddress.uip.address,
      mip,
      mask: userInterruptMask,
    );
  }

  void reset() {
    for (final csr in csrs.values) {
      if (csr is SimpleCsr)
        csr.value = 0;
      else if (csr is MaskedCsr)
        csr.value = 0;
    }
  }

  Csr operator [](int address) {
    if (!csrs.containsKey(address)) {
      throw TrapException.illegalInstruction();
    }
    return csrs[address]!;
  }

  int read(int address, RiverCoreEmulator core) {
    return this[address].read(core);
  }

  void write(int address, int value, RiverCoreEmulator core) {
    this[address].write(core, value);

    if (address == CsrAddress.satp.address) {
      final modeId = (value >> mxlen.satpModeShift) & mxlen.satpModeMask;
      final ppn = value & mxlen.satpPpnMask;
      core.mmu.configure(modeId, ppn);
    }
  }

  void increment() {}

  String toStringWithCore(RiverCoreEmulator core) =>
      'CsrFile(${Map.fromEntries(csrs.entries.map((entry) => MapEntry(CsrAddress.find(entry.key), entry.value.read(core))))})';

  @override
  String toString() => 'CsrFile()';
}
