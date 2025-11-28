import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

void defineCoreTest(RiverCore config) {
  late RiverCoreEmulator core;
  late int pc;

  int instr(int raw) => raw;

  setUp(() {
    core = RiverCoreEmulator(config);
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
}
