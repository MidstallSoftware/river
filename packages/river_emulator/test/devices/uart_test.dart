import 'dart:io';

import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

import '../constants.dart';

void main() {
  cpuTests('UART Device', (config) {
    late SramEmulator sram;
    late UartEmulator uart;
    late RiverCoreEmulator core;
    late StringBuffer input;
    late StringBuffer output;
    late int pc;

    setUp(() {
      input = StringBuffer();
      output = StringBuffer();

      sram = SramEmulator(
        Device.simple(
          name: 'sram',
          compatible: 'river,sram',
          range: BusAddressRange(0, 0xFFFF),
          fields: const {0: DeviceField('data', 4)},
          clock: config.clock,
        ),
      );

      uart = UartEmulator(
        RiverUart(name: 'uart0', address: 0x20000, clock: config.clock),
        input: stdin,
        output: stdout,
      );

      core = RiverCoreEmulator(
        config,
        memDevices: Map.fromEntries([sram.mem!, uart.mem!]),
      );

      pc = config.resetVector;
    });

    void writeWord(int addr, int value) =>
        core.mmu.write(addr, value, MicroOpMemSize.word.bytes);

    int readWord(int addr) => core.mmu.read(addr, MicroOpMemSize.word.bytes);

    void writeDword(int addr, int value) =>
        core.mmu.write(addr, value, MicroOpMemSize.dword.bytes);

    int readDword(int addr) => core.mmu.read(addr, MicroOpMemSize.dword.bytes);

    test('Reset', () {
      final prog = [
        0x000204b7,
        0x00100793,
        0x00f48123,
        0x00300793,
        0x00f49223,
        0x00000013,
        0x00000793,
      ];

      for (int i = 0; i < prog.length; i++) {
        final instr = prog[i];
        final pc = core.cycle(i * 4, instr);
        expect(pc, equals((i * 4) + 4));
      }

      expect(uart.enabled, true);
      expect(uart.divisor, 3);
    });
  });
}
