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
 * /* Set LCR, DLAB=1 */
 * li x6, 0x80
 * sb x6, 3(x5)
 *
 * /* Set DLL=3 */
 * li x6, 3
 * sb x6, 8(x5)
 *
 * /* Set DLM=0 */
 * li x6, 0
 * sb x6, 1(x5)
 *
 * /* Set LCR=3, DLAB=0, 8N1 */
 * li x6, 0x3,
 * sb x6, 3(x5)
 * ```
 */
const kInitProg = [
  0x000202b7,
  0x08000313,
  0x006281a3,
  0x00300313,
  0x00628023,
  0x00000313,
  0x00628223,
  0x00300313,
  0x006281a3,
];

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
      inputController = StreamController<List<int>>(sync: true);
      outputController = StreamController<List<int>>(sync: true);
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
        RiverUart(
          name: 'uart0',
          address: 0x20000,
          clock: config.clock,
          interrupt: 0,
        ),
        input: inputController.stream,
        output: outputController.sink,
      );

      core = RiverCoreEmulator(
        config,
        memDevices: Map.fromEntries([sram.mem!, uart.mem!]),
      );

      pc = config.resetVector;
    });

    Future<void> writeWord(int addr, int value) =>
        core.mmu.write(addr, value, MicroOpMemSize.word.bytes);

    Future<int> readWord(int addr) =>
        core.mmu.read(addr, MicroOpMemSize.word.bytes);

    void writeDword(int addr, int value) =>
        core.mmu.write(addr, value, MicroOpMemSize.dword.bytes);

    Future<int> readDword(int addr) =>
        core.mmu.read(addr, MicroOpMemSize.dword.bytes);

    Future<void> exec(List<int> prog) async {
      sram.reset();

      int i = 0;
      for (final p in prog) {
        await writeWord(i + config.resetVector, p);
        i += 4;
      }

      int pc = config.resetVector;
      while (true) {
        final instr = await core.fetch(pc);
        if (instr == 0x13) break;

        pc = await core.cycle(pc, instr);
      }

      await uart.flush();
    }

    test('Reset', () async {
      core.reset();
      uart.reset();
      uartOutput.clear();

      final prog = [...kInitProg, 0x00000013];

      await exec(prog);

      expect(uart.lcr & 0x83, 0x03);
      expect(uart.divisor, 3);
    });

    test('Write A', () async {
      core.reset();
      uart.reset();
      uartOutput.clear();

      final prog = [...kInitProg, 0x04100313, 0x00628023, 0x00000013];

      await exec(prog);
      await Future.delayed(Duration.zero);

      expect(uart.lcr & 0x83, 0x03);
      expect(uart.divisor, 3);
      expect(String.fromCharCodes(uartOutput), 'A');
    });

    test('Read A', () async {
      core.reset();
      uart.reset();
      uartOutput.clear();

      inputController.add('A'.codeUnits);

      final prog = [
        ...kInitProg,
        0x00528303,
        0x00137393,
        0xfe038ce3,
        0x00028303,
        0x00628023,
        0x00000013,
        0xffdff06f,
      ];

      await exec(prog);
      await Future.delayed(Duration.zero);

      expect(uart.lcr & 0x83, 0x03);
      expect(uart.divisor, 3);
      expect(String.fromCharCodes(uartOutput), 'A');
    }, timeout: Timeout(Duration(minutes: 1)));
  });
}
