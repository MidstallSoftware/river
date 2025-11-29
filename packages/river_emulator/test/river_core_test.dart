import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

void defineCoreTest(RiverCore config) {
  late SramEmulator sram;
  late RiverCoreEmulator core;
  late int pc;

  int instr(int raw) => raw;

  setUp(() {
    sram = SramEmulator(
      Device.simple(
        name: 'sram',
        compatible: 'river,sram',
        range: BusAddressRange(0, 0xFFFF),
        fields: const {0: DeviceField('data', 4)},
        clock: config.clock,
      ),
    );

    core = RiverCoreEmulator(config, memDevices: Map.fromEntries([sram.mem!]));
    pc = config.resetVector;
  });

  if (config.hasSupervisor && config.hasUser) {
    group('Privilege ISA', () {
      test('MRET returns from trap', () {
        core.reset();

        core.csrs.write(CsrAddress.mtvec.address, 0x80000000, core);
        core.csrs.write(CsrAddress.mepc.address, 0x200, core);

        var mstatus = core.csrs.read(CsrAddress.mstatus.address, core);
        mstatus = (mstatus & ~(0x3 << 11)) | (3 << 11);
        core.csrs.write(CsrAddress.mstatus.address, mstatus, core);

        final nextPc = core.cycle(0x1000, 0x30200073);

        expect(nextPc, 0x200);
        expect(core.mode, PrivilegeMode.machine);
      });
    });
  }

  if (config.extensions.any((e) => e.name == 'A')) {
    group('A extension', () {
      void writeWord(int addr, int value) {
        core.mmu.store(addr, value, MicroOpMemSize.word);
      }

      int readWord(int addr) {
        return core.mmu.load(addr, MicroOpMemSize.word);
      }

      void writeDword(int addr, int value) {
        core.mmu.store(addr, value, MicroOpMemSize.dword);
      }

      int readDword(int addr) {
        return core.mmu.load(addr, MicroOpMemSize.dword);
      }

      test('lr.w loads a word and reserves the address', () {
        writeWord(0x1000, 0x1234);
        writeWord(0x1234, 10);

        core.xregs[Register.x5] = 0x1000;

        final lrw = 0x1002A0AF;

        core.cycle(pc, lrw);

        expect(core.xregs[Register.x1], 0x1234);
        expect(core.reservationSet.contains(0x1000), true);
      });

      test('sc.w succeeds when reservation matches', () {
        writeWord(0x1000, 0x1111);
        core.xregs[Register.x5] = 0x1000;
        core.xregs[Register.x6] = 0x2222;

        final lrw = 0x1002A0AF;
        core.cycle(pc, lrw);

        final scw = 0x1862A12F;
        core.cycle(pc, scw);

        expect(readWord(0x1000), 0x2222);
        expect(core.xregs[Register.x2], 0);
      });

      test('sc.w fails when reservation is lost', () {
        writeWord(0x1000, 0x1111);
        core.xregs[Register.x5] = 0x1000;
        core.xregs[Register.x6] = 0x2222;

        final lrw = 0x1002A0AF;
        core.cycle(pc, lrw);

        core.clearReservationSet();

        final scw = 0x1862A12F;
        core.cycle(pc, scw);

        expect(readWord(0x1000), 0x1111);
        expect(core.xregs[Register.x2] ?? 0, isNot(0));
      });

      test('amoswap.w swaps correctly', () {
        writeWord(0x1000, 0xAAAA);
        core.xregs[Register.x5] = 0x1000;
        core.xregs[Register.x6] = 0x5555;

        final amoswap = 0x0862A12F;

        core.cycle(pc, amoswap);

        expect(core.xregs[Register.x2], 0xAAAA);
        expect(readWord(0x1000), 0x5555);
      });

      test('amoadd.w adds correctly', () {
        writeWord(0x1000, 10);
        core.xregs[Register.x5] = 0x1000;
        core.xregs[Register.x6] = 3;

        final amoadd = 0x0062A12F;

        core.cycle(pc, amoadd);

        expect(core.xregs[Register.x2], 10);
        expect(readWord(0x1000), 13);
      });

      if (config.mxlen == Mxlen.mxlen_64) {
        test('lr.d loads a doubleword and reserves address', () {
          writeDword(0x2000, 0x1122334455667788);
          core.xregs[Register.x5] = 0x2000;

          final lrd = 0x1002B0AF;

          core.cycle(pc, lrd);

          expect(core.xregs[Register.x1], 0x1122334455667788);
          expect(core.reservationSet.contains(0x2000), true);
        });

        test('sc.d succeeds when reservation matches', () {
          writeDword(0x2000, 0x1111);
          core.xregs[Register.x5] = 0x2000;
          core.xregs[Register.x6] = 0x2222333344445555;

          final lrd = 0x1002B0AF;
          core.cycle(pc, lrd);

          final scd = 0x1862B12F;
          core.cycle(pc, scd);

          expect(readDword(0x2000), 0x2222333344445555);
          expect(core.xregs[Register.x2], 0);
        });

        test('sc.d fails when reservation lost', () {
          writeDword(0x2000, 0x9999);
          core.xregs[Register.x5] = 0x2000;
          core.xregs[Register.x6] = 0x1111;

          final lrd = 0x1002B0AF;
          core.cycle(pc, lrd);

          core.clearReservationSet();

          final scd = 0x1862B12F;
          core.cycle(pc, scd);

          expect(readDword(0x2000), 0x9999);
          expect(core.xregs[Register.x2], isNot(0));
        });
      }
    });
  }

  if (config.extensions.any((e) => e.name == 'M')) {
    group('M extension', () {
      test('mul multiplies two registers', () {
        core.xregs[Register.x5] = 6;
        core.xregs[Register.x6] = 7;

        final mul = 0x025303b3;
        core.cycle(pc, mul);

        expect(core.xregs[Register.x7], 42);
      });

      test('mulh high part is zero for small operands', () {
        core.xregs[Register.x5] = 1234;
        core.xregs[Register.x6] = 5678;

        final mulh = 0x025313b3;
        core.cycle(pc, mulh);

        expect(core.xregs[Register.x7], 0);
      });

      test('div signed division truncates toward zero', () {
        core.xregs[Register.x5] = 3;
        core.xregs[Register.x6] = -7;

        final div = 0x025343b3;
        core.cycle(pc, div);

        expect(core.xregs[Register.x7], -2);
      });

      test('rem signed remainder has same sign as dividend', () {
        core.xregs[Register.x5] = 3;
        core.xregs[Register.x6] = -7;

        final rem = 0x025363b3;
        core.cycle(pc, rem);

        expect(core.xregs[Register.x7], -1);
      });

      test('divu unsigned division', () {
        core.xregs[Register.x5] = 3;
        core.xregs[Register.x6] = 7;

        final divu = 0x025353b3;
        core.cycle(pc, divu);

        expect(core.xregs[Register.x7], 2);
      });

      test('remu unsigned remainder', () {
        core.xregs[Register.x5] = 3;
        core.xregs[Register.x6] = 7;

        final remu = 0x025373b3;
        core.cycle(pc, remu);

        expect(core.xregs[Register.x7], 1);
      });

      test('div by zero returns -1 (all ones)', () {
        core.xregs[Register.x5] = 0;
        core.xregs[Register.x6] = 123;

        final div = 0x025343b3;
        core.cycle(pc, div);

        expect(core.xregs[Register.x7], -1);
      });

      test('divu by zero returns all ones (-1)', () {
        core.xregs[Register.x5] = 0;
        core.xregs[Register.x6] = 123;

        final divu = 0x025353b3;
        core.cycle(pc, divu);

        expect(
          core.xregs[Register.x7],
          ((BigInt.one << config.mxlen.size) - BigInt.one).toInt(),
        );
      });

      test('rem/div by zero leaves remainder equal to dividend', () {
        core.xregs[Register.x5] = 0;
        core.xregs[Register.x6] = -42;

        final rem = 0x025363b3;
        core.cycle(pc, rem);

        expect(core.xregs[Register.x7], -42);
      });

      if (config.mxlen == Mxlen.mxlen_64) {
        test('mulw uses 32-bit product and sign-extends to XLEN', () {
          core.xregs[Register.x5] = 2;
          core.xregs[Register.x6] = 0x00000000FFFFFFFF;

          final mulw = 0x025303bb;
          core.cycle(pc, mulw);

          expect(core.xregs[Register.x7], -2);
        });

        test('divw truncates toward zero and sign-extends', () {
          core.xregs[Register.x5] = 2;
          core.xregs[Register.x6] = -7;

          final divw = 0x025343bb;
          core.cycle(pc, divw);

          expect(core.xregs[Register.x7], -3);
        });

        test('remw has remainder with sign of dividend and sign-extends', () {
          core.xregs[Register.x5] = 2;
          core.xregs[Register.x6] = -7;

          final remw = 0x025363bb;
          core.cycle(pc, remw);

          expect(core.xregs[Register.x7], -1);
        });

        test('divuw uses unsigned 32-bit semantics', () {
          core.xregs[Register.x5] = 2;
          core.xregs[Register.x6] = 0x00000000FFFFFFFE;

          final divuw = 0x025353bb;
          core.cycle(pc, divuw);

          expect(core.xregs[Register.x7], 0x7FFFFFFF);
        });

        test('remuw returns unsigned 32-bit remainder, zero-extended', () {
          core.xregs[Register.x5] = 3;
          core.xregs[Register.x6] = 0x00000000FFFFFFFE;

          final remuw = 0x025373bb;
          core.cycle(pc, remuw);

          expect(core.xregs[Register.x7], 2);
        });
      }
    });
  }

  if (config.extensions.any((e) => e.name == 'Zicsr')) {
    group("Zicsr extension", () {
      int read(CsrAddress csr) => core.csrs.read(csr.address, core);
      void write(CsrAddress csr, int v) =>
          core.csrs.write(csr.address, v, core);

      test("csrrw: atomic swap (rd=old, CSR=new)", () {
        write(CsrAddress.mscratch, 0xAAAA);
        core.xregs[Register.x5] = 0x1234;

        final csrrw = 0x34029373;

        final newPc = core.cycle(pc, csrrw);

        expect(core.xregs[Register.x6], 0xAAAA);
        expect(read(CsrAddress.mscratch), 0x1234);
        expect(newPc, pc + 4);
      });

      test("csrrw with rd=x0 still writes CSR but suppresses rd write", () {
        write(CsrAddress.mscratch, 0x1111);
        core.xregs[Register.x5] = 0x2222;

        final csrrw = 0x34029073;

        core.cycle(pc, csrrw);

        expect(read(CsrAddress.mscratch), 0x2222);
        expect(core.xregs[Register.x0] ?? 0, 0);
      });

      test("csrrs: rd=old, CSR |= rs1", () {
        write(CsrAddress.mscratch, 0x100);
        core.xregs[Register.x5] = 0x0F;

        final csrrs = 0x3402A373;

        core.cycle(pc, csrrs);

        expect(core.xregs[Register.x6], 0x100);
        expect(read(CsrAddress.mscratch), 0x10F);
      });

      test("csrrs with rs1=x0 only reads CSR", () {
        write(CsrAddress.mstatus, 0xABCDE);

        final csrrs = 0x3000A073;

        core.cycle(pc, csrrs);

        expect(read(CsrAddress.mstatus), 0xABCDE);
      });

      test("csrrc: CSR &= ~rs1", () {
        write(CsrAddress.mstatus, 0xFF);
        core.xregs[Register.x5] = 0x0F;

        final csrrc = 0x3002B373;

        core.cycle(pc, csrrc);

        expect(core.xregs[Register.x6], 0xFF);
        expect(read(CsrAddress.mstatus), 0xF0);
      });

      test("csrrwi: CSR = imm, rd = old CSR", () {
        write(CsrAddress.mscratch, 0x7777);

        final csrrwi = 0x3402D373;

        core.cycle(pc, csrrwi);

        expect(core.xregs[Register.x6], 0x7777);
        expect(read(CsrAddress.mscratch), 5);
      });

      test("csrrsi: CSR |= imm", () {
        write(CsrAddress.mscratch, 0x10);

        final csrrsi = 0x3401E073;

        core.cycle(pc, csrrsi);

        expect(read(CsrAddress.mscratch), 0x13);
      });

      test("csrrci: CSR &= ~imm", () {
        write(CsrAddress.mscratch, 0xF);

        final csrrci = 0x3401F073;

        core.cycle(pc, csrrci);

        expect(read(CsrAddress.mscratch), 0xC);
      });

      test("Accessing an invalid CSR causes illegal instruction", () {
        const bogusCsr = 0xFFF;

        final instr = (bogusCsr << 20) | (2 << 15) | (1 << 7) | 0x1073;

        expect(() => core.cycle(pc, instr), throwsA(isA<TrapException>()));
      });

      test("User-mode attempting to write mstatus traps", () {
        core.mode = PrivilegeMode.user;

        final instr =
            (CsrAddress.mstatus.address << 20) | (2 << 15) | (1 << 7) | 0x1073;

        expect(() => core.cycle(pc, instr), throwsA(isA<TrapException>()));
      });

      test("Writing to read-only CSR (misa) traps", () {
        final instr =
            (CsrAddress.misa.address << 20) | (2 << 15) | (1 << 7) | 0x1073;
        expect(() => core.cycle(pc, instr), throwsA(isA<TrapException>()));
      });
    });
  }
}

void main() {
  group('RC1.n', () {
    defineCoreTest(
      const RiverCoreV1.nano(
        mmu: Mmu(mxlen: Mxlen.mxlen_32, blocks: []),
        interrupts: [],
        clock: ClockConfig(name: 'test', baseFreqHz: 1000),
      ),
    );
  });

  group('RC1.mi', () {
    defineCoreTest(
      const RiverCoreV1.micro(
        mmu: Mmu(mxlen: Mxlen.mxlen_32, blocks: []),
        interrupts: [],
        clock: ClockConfig(name: 'test', baseFreqHz: 1000),
      ),
    );
  });

  group('RC1.s', () {
    defineCoreTest(
      const RiverCoreV1.small(
        mmu: Mmu(mxlen: Mxlen.mxlen_64, blocks: []),
        interrupts: [],
        clock: ClockConfig(name: 'test', baseFreqHz: 1000),
      ),
    );
  });
}
