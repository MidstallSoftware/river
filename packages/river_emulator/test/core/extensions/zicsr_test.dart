import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

import '../../constants.dart';

void main() {
  cpuTests(
    'Zicsr extension',
    (config) {
      late SramEmulator sram;
      late RiverCoreEmulator core;
      late int pc;

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

        core = RiverCoreEmulator(
          config,
          memDevices: Map.fromEntries([sram.mem!]),
        );
        pc = config.resetVector;
      });

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
    },
    condition: (config) => config.extensions.any((e) => e.name == 'Zicsr'),
  );
}
