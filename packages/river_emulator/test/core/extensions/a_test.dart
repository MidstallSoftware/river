import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

import '../../constants.dart';

void main() {
  cpuTests('A extension', (config) {
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

      final scw = 0x1862A1AF;
      core.cycle(pc, scw);

      expect(readWord(0x1000), 0x1111);
      expect(core.xregs[Register.x3] ?? 0, isNot(0));
    });

    test('amoswap.w swaps correctly', () {
      writeWord(0x1000, 0xAAAA);
      core.xregs[Register.x5] = 0x1000;
      core.xregs[Register.x6] = 0x5555;

      final amoswap = 0x0862A1AF;

      core.cycle(pc, amoswap);

      expect(core.xregs[Register.x3], 0xAAAA);
      expect(readWord(0x1000), 0x5555);
    });

    test('amoadd.w adds correctly', () {
      writeWord(0x1000, 10);
      core.xregs[Register.x5] = 0x1000;
      core.xregs[Register.x6] = 3;

      final amoadd = 0x0062A1AF;

      core.cycle(pc, amoadd);

      expect(core.xregs[Register.x3], 10);
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

        final scd = 0x1862B1AF;
        core.cycle(pc, scd);

        expect(readDword(0x2000), 0x9999);
        expect(core.xregs[Register.x3], isNot(0));
      });
    }
  }, condition: (config) => config.extensions.any((e) => e.name == 'A'));
}
