import 'package:riscv/riscv.dart';

import '../../bus.dart';
import '../../clock.dart';
import '../../dev.dart';

class RiscVClint extends Device {
  RiscVClint({
    required String name,
    required int address,
    required ClockConfig clock,
  }) : super(
         name: name,
         compatible: 'river,clint',
         range: BusAddressRange(address, 0x00010000),
         clock: clock,
         accessor: DeviceAccessor('/$name', const {
           0: DeviceField('msip', 4, offset: 0),
           1: DeviceField('mtimecmp', 8, offset: 0x4000),
           2: DeviceField('mtime', 8, offset: 0xBFF8),
         }, type: DeviceAccessorType.io),
       );
}
