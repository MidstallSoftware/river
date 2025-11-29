import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

import '../constants.dart';

void main() {
  cpuTests('Privilege ISA', (config) {
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

    test('MRET returns from trap', () {
      core.reset();

      core.csrs.write(CsrAddress.mtvec.address, 0x80000000, core);
      core.csrs.write(CsrAddress.mepc.address, 0x200, core);

      var mstatus = core.csrs.read(CsrAddress.mstatus.address, core);
      mstatus = (mstatus & ~(0x3 << 11)) | (3 << 11);
      core.csrs.write(CsrAddress.mstatus.address, mstatus, core);

      final nextPc = core.cycle(0x1000, 0x30200073);

      expect(nextPc, 0x200);
      expect(core.mode, PrivilegeMode.machine);
    });
  }, condition: (config) => config.hasSupervisor && config.hasUser);
}
