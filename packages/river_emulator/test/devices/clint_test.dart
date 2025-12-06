import 'dart:async';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

import '../constants.dart';

void main() {
  cpuTests('CLINT Device', (config) {
    late SramEmulator sram;
    late RiscVClintEmulator clint;
    late RiverCoreEmulator core;

    const clintAddr = 0x2000000;

    setUp(() {
      // Simple SRAM backing store
      sram = SramEmulator(
        Device.simple(
          name: 'sram',
          compatible: 'river,sram',
          range: BusAddressRange(0, 0xFFFF),
          fields: const {0: DeviceField('data', 4)},
          clock: config.clock,
        ),
      );

      // CLINT instance
      clint = RiscVClintEmulator(
        RiscVClint(name: 'clint', address: clintAddr, clock: config.clock),
      );

      core = RiverCoreEmulator(
        config,
        memDevices: Map.fromEntries([sram.mem!, clint.mem!]),
      );
    });

    Future<void> writeWord(int addr, int val) =>
        core.mmu.write(addr, val, MicroOpMemSize.word.bytes);

    Future<int> readWord(int addr) =>
        core.mmu.read(addr, MicroOpMemSize.word.bytes);

    Future<void> writeDouble(int addr, int val) =>
        core.mmu.write(addr, val, MicroOpMemSize.dword.bytes);

    Future<int> readDouble(int addr) =>
        core.mmu.read(addr, MicroOpMemSize.dword.bytes);

    // Memory map offsets:
    final msipAddr = clintAddr + 0x0000;
    final mtimecmpAddr = clintAddr + 0x4000;
    final mtimeAddr = clintAddr + 0xBFF8;

    test('No interrupts initially', () {
      final irq = clint.interrupts(0);
      expect(irq[0], isFalse, reason: 'MSIP should be false');
      expect(irq[1], isFalse, reason: 'MTIP should be false');
    });

    test('MSIP interrupt fires when msip bit is set', () async {
      await writeWord(msipAddr, 1);
      expect(clint.interrupts(0)[0], isTrue);
    });

    test('MSIP clears when written with 0', () async {
      await writeWord(msipAddr, 1);
      expect(clint.interrupts(0)[0], isTrue);

      await writeWord(msipAddr, 0);
      expect(clint.interrupts(0)[0], isFalse);
    });

    test('MTIP fires when mtime >= mtimecmp', () async {
      await writeDouble(mtimecmpAddr, 10);

      await Future.delayed(Duration(milliseconds: 5));

      expect(clint.interrupts(0)[1], isTrue);
    });

    test('MTIP does not fire when mtime < mtimecmp', () async {
      await writeDouble(mtimecmpAddr, 0xFFFFFFFF);

      expect(clint.interrupts(0)[1], isFalse);
    });

    test('Write mtime resets the base (mtime decreases)', () async {
      await Future.delayed(Duration(milliseconds: 5));
      final before = await readDouble(mtimeAddr);

      await writeDouble(mtimeAddr, 5);

      final after = await readDouble(mtimeAddr);
      expect(after, lessThan(before), reason: 'mtime should reset to new base');
    });

    test('MTIP clears when mtimecmp is set higher again', () async {
      await writeDouble(mtimecmpAddr, 5);
      await Future.delayed(Duration(milliseconds: 5));
      expect(clint.interrupts(0)[1], isTrue);

      await writeDouble(mtimecmpAddr, 0xFFFFFFFF);
      expect(clint.interrupts(0)[1], isFalse);
    });

    test('mtime increases over real time', () async {
      final t1 = await readDouble(mtimeAddr);

      await Future.delayed(Duration(milliseconds: 2));

      final t2 = await readDouble(mtimeAddr);

      expect(t2, greaterThan(t1), reason: 'mtime must advance monotonically');
    });
  });
}
