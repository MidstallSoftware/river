import 'dart:async';
import 'dart:io';

import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

import '../constants.dart';

/**
 * ```
 * li x5, 0x20000
 *
 * /* Set divisor to 3 */
 * li x6, 3
 * sb x6, 12(x5)
 *
 * /* Set enable bit in status */
 * li x6, 1 << 0
 * sb x6, 8(x5)
 * ```
 */
const kInitProg = [0x000202b7, 0x00300313, 0x00628623, 0x00100313, 0x00628423];

void main() {
  cpuTests('UART Device', (config) {
    late SramEmulator sram;
    late UartEmulator uart;
    late RiverCoreEmulator core;
    late StreamController<List<int>> inputController;
    late StreamController<List<int>> outputController;
    late List<int> uartOutput;
    late int pc;

    setUp(() {
      inputController = StreamController<List<int>>();
      outputController = StreamController<List<int>>();
      uartOutput = [];

      outputController.stream.listen(uartOutput.addAll);

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
        input: inputController.stream,
        output: outputController.sink,
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

    void exec(List<int> prog) {
      int i = 0;
      while (i < prog.length) {
        final instr = prog[i];
        if (instr == 0x13) break;

        final pc = core.cycle(i * 4, instr);
        i = pc ~/ 4;
      }
    }

    test('Reset', () {
      core.reset();
      uart.reset();
      uartOutput.clear();

      exec(kInitProg);

      expect(uart.enabled, true);
      expect(uart.divisor, 3);
    });

    test('Write A', () async {
      core.reset();
      uart.reset();
      uartOutput.clear();

      final prog = [...kInitProg, 0x04100313, 0x00628023];

      exec(prog);

      await Future.delayed(Duration.zero);

      expect(uart.enabled, true);
      expect(uart.divisor, 3);
      expect(String.fromCharCodes(uartOutput), 'A');
    });
  });
}
