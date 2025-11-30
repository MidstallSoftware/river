import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

import '../../constants.dart';

void main() {
  cpuTests(
    'C extension',
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

      void writeWord(int addr, int value) =>
          core.mmu.write(addr, value, MicroOpMemSize.word.bytes);

      int readWord(int addr) => core.mmu.read(addr, MicroOpMemSize.word.bytes);

      void writeDword(int addr, int value) =>
          core.mmu.write(addr, value, MicroOpMemSize.dword.bytes);

      int readDword(int addr) =>
          core.mmu.read(addr, MicroOpMemSize.dword.bytes);

      test('c.addi4spn expands to addi rd, x2, nzuimm', () {
        core.xregs[Register.x2] = 0x1000;

        final instr = 0x200;
        final next = core.cycle(pc, instr);

        expect(core.xregs[Register.x8], 0x1000 + 16);
        expect(next, pc + 2);
      });

      test('c.nop decodes as addi x0, x0, 0', () {
        final instr = 0x0001;
        final next = core.cycle(pc, instr);

        expect(core.xregs[Register.x0] ?? 0, 0);
        expect(next, pc + 2);
      });

      test('c.addi sign-extends 6-bit immediate', () {
        core.xregs[Register.x9] = 10;

        final instr = 0x14FD;
        final next = core.cycle(pc, instr);

        expect(core.xregs[Register.x9], 9);
        expect(next, pc + 2);
      });

      test('c.addi4spn rejects imm=0 (illegal)', () {
        final instr = 0x0000;

        expect(() => core.cycle(pc, instr), throwsA(isA<TrapException>()));
      });

      test("c.lw uses rs1' = 8+rs1c and rd' = 8+rdc", () {
        writeWord(0x2000, 0xDEADBEEF);

        core.xregs[Register.x8] = 0x2000;

        final instr = 0x4000;
        final next = core.cycle(pc, instr);

        expect(core.xregs[Register.x8], 0xDEADBEEF);
        expect(next, pc + 2);
      });

      test('c.lwsp loads from sp + imm', () {
        core.xregs[Register.x2] = 0x3000;
        writeWord(0x3008, 0xFACEB00C);

        final instr = 0x4522;

        final next = core.cycle(pc, instr);

        expect(core.xregs[Register.x10], 0xFACEB00C);
        expect(next, pc + 2);
      });

      test("c.sw stores to rs1' + imm", () {
        core.xregs[Register.x8] = 0x4000;
        core.xregs[Register.x9] = 0x12345678;

        final instr = 0xC004;
        core.cycle(pc, instr);

        expect(readWord(0x4000), 0x12345678);
      });

      test('c.swsp stores from rs2 to sp + imm', () {
        core.xregs[Register.x2] = 0x5000;
        core.xregs[Register.x9] = 0xCAFEBABE;

        final instr = 0xC226;
        core.cycle(pc, instr);

        expect(readWord(0x5004), 0xCAFEBABE);
      });

      test('c.srli shifts logically and zero-fills', () {
        core.xregs[Register.x8] = 0xF0000000;

        final instr = 0x9005;
        final next = core.cycle(pc, instr);

        expect(core.xregs[Register.x8], 0x78000000);
        expect(next, pc + 2);
      });

      test('c.srai shifts arithmetically and sign-extends', () {
        core.xregs[Register.x8] = -4;

        final instr = 0x9405;
        final next = core.cycle(pc, instr);

        expect(core.xregs[Register.x8], -2);
        expect(next, pc + 2);
      });

      test('c.and applies bitwise AND', () {
        core.xregs[Register.x8] = 0xF0F0F0F0;
        core.xregs[Register.x9] = 0x0F0F0F0F;

        final instr = 0x8c65;
        core.cycle(pc, instr);

        expect(core.xregs[Register.x8], 0x00000000);
      });

      test('c.beqz skips when rs1 != 0', () {
        core.xregs[Register.x8] = 1;

        final instr = 0xC00D;
        final next = core.cycle(pc, instr);

        expect(next, pc + 2);
      });

      test('c.beqz branches when rs1 == 0', () {
        core.xregs[Register.x8] = 0;

        final instr = 0xC00D;
        final next = core.cycle(pc, instr);

        expect(next, isNot(pc + 2));
      });

      test('c.j jumps with sign-extended immediate', () {
        final instr = 0xBFFD;
        final next = core.cycle(pc, instr);

        expect(next, pc - 2);
      });

      test('c.jr jumps to rs1 and does NOT write ra', () {
        core.xregs[Register.x10] = 0x6000;

        final instr = 0x8502;
        final next = core.cycle(pc, instr);

        expect(next, 0x6000);
        expect(core.xregs[Register.x1] ?? 0, 0);
      });

      test('c.jalr writes ra and jumps to rs1', () {
        core.xregs[Register.x10] = 0x7000;

        final instr = 0x9502;
        final next = core.cycle(pc, instr);

        expect(core.xregs[Register.x1], pc + 2);
        expect(next, 0x7000);
      });

      test('c.mv moves rs2 to rd', () {
        core.xregs[Register.x9] = 0xABC;

        final instr = 0x8426;
        core.cycle(pc, instr);

        expect(core.xregs[Register.x8], 0xABC);
      });

      test('c.add adds rs2 to rs1 and writes rd', () {
        core.xregs[Register.x8] = 10;
        core.xregs[Register.x9] = 20;

        final instr = 0x9426;
        core.cycle(pc, instr);

        expect(core.xregs[Register.x8], 30);
      });

      test('c.lui loads rd with imm<<12', () {
        final instr = 0x6405;
        final next = core.cycle(pc, instr);

        expect(core.xregs[Register.x8], 1 << 12);
        expect(next, pc + 2);
      });
    },
    condition: (config) => config.extensions.any((e) => e.name == 'RVC'),
  );
}
