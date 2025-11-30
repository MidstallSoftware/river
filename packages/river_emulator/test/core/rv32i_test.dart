import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

import '../constants.dart';

void main() {
  cpuTests('RV32I', (config) {
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
        core.mmu.store(addr, value, MicroOpMemSize.word);

    int readWord(int addr) => core.mmu.load(addr, MicroOpMemSize.word);

    void writeDword(int addr, int value) =>
        core.mmu.store(addr, value, MicroOpMemSize.dword);

    int readDword(int addr) => core.mmu.load(addr, MicroOpMemSize.dword);

    test('addi increments register', () {
      core.reset();

      final instr = 0x00A00293;
      final nextPc = core.cycle(pc, instr);

      expect(core.xregs[Register.x5], equals(10));
      expect(nextPc, pc + 4);
    });

    test('add performs register addition', () {
      core.reset();

      core.xregs[Register.x5] = 7;
      core.xregs[Register.x6] = 9;

      final instr = 0x005303B3;
      final nextPc = core.cycle(pc, instr);

      expect(core.xregs[Register.x7], equals(16));
      expect(nextPc, pc + 4);
    });

    test('lw loads from memory', () {
      core.reset();

      core.xregs[Register.x5] = 0x20;
      writeWord(0x24, 0xDEADBEEF);

      final instr = 0x0042A303;
      final nextPc = core.cycle(pc, instr);

      expect(core.xregs[Register.x6], equals(0xDEADBEEF));
      expect(nextPc, pc + 4);
    });

    test('sw stores to memory', () {
      core.reset();

      core.xregs[Register.x5] = 0x20;
      core.xregs[Register.x6] = 0xCAFEBABE;

      const instr = 0x0062A223;
      final nextPc = core.cycle(pc, instr);

      expect(readWord(0x24), equals(0xCAFEBABE));
      expect(nextPc, pc + 4);
    });

    test('beq takes branch when equal', () {
      core.reset();

      core.xregs[Register.x5] = 5;
      core.xregs[Register.x6] = 5;

      const instr = 0x00628463;
      final nextPc = core.cycle(pc, instr);

      expect(nextPc, equals(pc + 8));
    });

    test('beq does not branch when not equal', () {
      core.reset();

      core.xregs[Register.x5] = 5;
      core.xregs[Register.x6] = 7;

      const instr = 0x00628463;
      final nextPc = core.cycle(pc, instr);

      expect(nextPc, equals(pc + 4));
    });

    test('lui loads upper immediate', () {
      core.reset();

      const instr = 0x123452B7;
      final nextPc = core.cycle(pc, instr);

      expect(core.xregs[Register.x5], equals(0x12345000));
      expect(nextPc, equals(pc + 4));
    });

    test('jal writes ra and jumps', () {
      core.reset();

      const instr = 0x100002EF;
      final nextPc = core.cycle(pc, instr);

      expect(core.xregs[Register.x5], equals(pc + 4));
      expect(nextPc, equals(pc + 0x100));
    });

    test('auipc adds immediate to PC', () {
      const instr = 0x00010297;
      final nextPc = core.cycle(pc, instr);

      expect(core.xregs[Register.x5], equals(pc + 0x10000));
      expect(nextPc, equals(pc + 4));
    });

    test('slti sets when less-than immediate', () {
      core.xregs[Register.x4] = 5;

      const instr = 0x00A22293;
      final nextPc = core.cycle(pc, instr);

      expect(core.xregs[Register.x5], equals(1));
      expect(nextPc, equals(pc + 4));
    });
  });
}
