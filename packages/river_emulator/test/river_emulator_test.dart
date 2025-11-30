import 'dart:convert';

import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

void main() {
  group('Stream V1 - iCESugar', () {
    final config = StreamV1SoC.icesugar();
    late RiverSoCEmulator soc;

    setUp(() {
      soc = RiverSoCEmulator(config);
    });

    test('Configure', () {
      soc.reset();

      expect(soc.devices.length, 8);
      expect(soc.cores.length, 1);
    });

    test('Read data', () {
      final soc = RiverSoCEmulator(
        config,
        deviceOptions: {
          'bootrom': {'bytes': '002081B3'},
        },
      );

      final mmap = soc.getDevice('bootrom')!.config.mmap!;

      soc.reset();
      expect(
        soc.cores[0].read(mmap.start, soc.cores[0].config.mxlen.width),
        0x002081B3,
      );
    });

    test('Reset & execute', () {
      final soc = RiverSoCEmulator(
        config,
        deviceOptions: {
          'bootrom': {'bytes': '00A08293'},
        },
      );

      final mmap = soc.getDevice('bootrom')!.config.mmap!;

      soc.reset();

      soc.cores[0].xregs[Register.x1] = 12;

      final pc = soc.runPipelines({})[0]!;
      expect(config.cores[0].resetVector, mmap!.start);
      expect(config.cores[0].resetVector, pc - 4);
      expect(soc.cores[0].xregs[Register.x5], 22);
    });
  });
}
