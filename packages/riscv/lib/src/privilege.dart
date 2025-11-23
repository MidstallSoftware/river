import 'ops.dart';

enum CsrAddress {
  ustatus(0x000),
  uie(0x004),
  utvec(0x005),
  uscratch(0x040),
  uepc(0x041),
  ucause(0x042),
  utval(0x043),
  uip(0x044),

  sstatus(0x100),
  sedeleg(0x102),
  sideleg(0x103),
  sie(0x104),
  stvec(0x105),
  scounteren(0x106),

  sscratch(0x140),
  sepc(0x141),
  scause(0x142),
  stval(0x143),
  sip(0x144),

  satp(0x180),

  mvendorid(0xF11),
  marchid(0xF12),
  mimpid(0xF13),
  mhartid(0xF14),

  mstatus(0x300),
  misa(0x301),
  medeleg(0x302),
  mideleg(0x303),
  mie(0x304),
  mtvec(0x305),
  mcounteren(0x306),

  mscratch(0x340),
  mepc(0x341),
  mcause(0x342),
  mtval(0x343),
  mip(0x344),
  pmpcfg0(0x3A0),
  pmpcfg1(0x3A1),
  pmpcfg2(0x3A2),
  pmpcfg3(0x3A3),
  pmpaddr0(0x3B0),
  pmpaddr1(0x3B1),
  pmpaddr2(0x3B2),
  pmpaddr3(0x3B3),
  pmpaddr4(0x3B4),
  pmpaddr5(0x3B5),
  pmpaddr6(0x3B6),
  pmpaddr7(0x3B7),

  mcycle(0xB00),
  minstret(0xB02),
  mhpmcounter3(0xB03),
  mhpmcounter4(0xB04),
  mhpmcounter5(0xB05),
  mhpmcounter6(0xB06),
  mhpmcounter7(0xB07),
  mhpmcounter8(0xB08),
  mhpmcounter9(0xB09),
  mhpmcounter10(0xB0A),
  mhpmcounter11(0xB0B),

  mcycleh(0xB80),
  minstreth(0xB82),

  mhpmevent3(0x323),
  mhpmevent4(0x324),
  mhpmevent5(0x325),
  mhpmevent6(0x326),
  mhpmevent7(0x327),
  mhpmevent8(0x328),
  mhpmevent9(0x329),
  mhpmevent10(0x32A),
  mhpmevent11(0x32B);

  const CsrAddress(this.address);

  final int address;

  static CsrAddress? find(int addr) {
    for (final csr in CsrAddress.values) {
      if (csr.address == addr) return csr;
    }

    return null;
  }
}
