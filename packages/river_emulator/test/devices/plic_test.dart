import 'dart:async';

import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

import '../constants.dart';

void main() {
  cpuTests('PLIC Device', (config) {
    late SramEmulator sram;
    late RiscVPlicEmulator plic;
    late RiverCoreEmulator core;

    const plicAddr = 0x40000;

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

      plic = RiscVPlicEmulator(
        RiscVPlic(
          name: 'plic',
          address: plicAddr,
          interrupt: 0,
          clock: config.clock,
        ),
        numSources: 8,
      );

      core = RiverCoreEmulator(
        config,
        memDevices: Map.fromEntries([sram.mem!, plic.mem!]),
      );
    });

    Future<void> writeWord(int addr, int val) =>
        core.mmu.write(addr, val, MicroOpMemSize.word.bytes);

    Future<int> readWord(int addr) =>
        core.mmu.read(addr, MicroOpMemSize.word.bytes);

    test('No interrupt when pending=0', () {
      final irq = plic.interrupts(0)[0];
      expect(irq, isFalse);
    });

    test('Interrupt does not fire unless enabled', () {
      plic.setSourcePending(1, true);
      expect(plic.interrupts(0)[0], isFalse);
    });

    test('Interrupt fires when pending AND enabled', () async {
      await writeWord(plicAddr + 0, 1);
      await writeWord(plicAddr + 0x200, 1 << 1);
      await writeWord(plicAddr + 0x200000, 0);

      plic.setSourcePending(1, true);

      expect(plic.interrupts(0)[0], isTrue);
    });

    test('Claim returns correct ID and clears pending', () async {
      await writeWord(plicAddr + 0, 1);
      await writeWord(plicAddr + 0x200, 1 << 1);
      await writeWord(plicAddr + 0x200000, 0);

      // Assert interrupt
      plic.setSourcePending(1, true);
      expect(plic.interrupts(0)[0], isTrue);

      final id = await readWord(plicAddr + 0x200004);
      expect(id, 1);

      final pending = await readWord(plicAddr + 0x100);
      expect((pending & (1 << 1)) != 0, isFalse);

      expect(plic.interrupts(0)[0], isFalse);
    });

    test('Threshold blocks lower priority interrupts', () async {
      await writeWord(plicAddr + 0, 1);
      await writeWord(plicAddr + 0x200, 1 << 1);
      await writeWord(plicAddr + 0x200000, 2);

      plic.setSourcePending(1, true);
      expect(plic.interrupts(0)[0], isFalse);
    });

    test('Higher priority interrupt wins', () async {
      await writeWord(plicAddr + 0, 1);

      plic.setPriority(2, 3);

      await writeWord(plicAddr + 0x200, (1 << 1) | (1 << 2));
      await writeWord(plicAddr + 0x200000, 0);

      plic.setSourcePending(1, true);
      plic.setSourcePending(2, true);

      expect(await readWord(plicAddr + 0x200004), 2);
    });
  });
}
