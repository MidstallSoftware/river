import 'package:riscv/riscv.dart';

import '../../bus.dart';
import '../../clock.dart';
import '../../dev.dart';

class RiscVPlic extends Device {
  RiscVPlic({
    required String name,
    required int address,
    required ClockConfig clock,
    required int interrupt,
    int hartCount = 1,
  }) : super(
         name: name,
         compatible: 'riscv,plic',
         range: BusAddressRange(address, 0x4000000),
         interrupts: [interrupt],
         clock: clock,
         accessor: DeviceAccessor('/$name', {
           0: DeviceField('priority', 4, offset: 0),
           1: DeviceField('pending', 4, offset: 0x000100),
           ...{
             for (
               int hart = 0, idx = 2;
               hart < hartCount;
               hart++, idx += 3
             ) ...{
               idx: DeviceField(
                 'enable_cpu$hart',
                 4,
                 offset: 0x00000200 + (hart * 0x80),
               ),
               idx + 1: DeviceField(
                 'threshold_cpu$hart',
                 4,
                 offset: 0x00200000 + (hart * 0x1000),
               ),
               idx + 2: DeviceField(
                 'claim_cpu$hart',
                 4,
                 offset: 0x00200004 + (hart * 0x1000),
               ),
             },
           },
         }, type: DeviceAccessorType.io),
       );
}
