import 'package:riscv/riscv.dart';

import '../../bus.dart';
import '../../clock.dart';
import '../../dev.dart';

/// The platform UART device for River
class RiverUart extends Device {
  RiverUart({
    required String name,
    required int address,
    required ClockConfig clock,
  }) : super(
         name: name,
         compatible: 'river,uart',
         interrupts: const [1],
         range: BusAddressRange(address, 0x100),
         clock: clock,
         accessor: DeviceAccessor('/$name', const {
           0: DeviceField('tx', 4),
           1: DeviceField('rx', 4),
           2: DeviceField('status', 4),
           3: DeviceField('divisor', 8),
         }),
       );

  /// Structure of the status register when read
  static const status = BitStruct({
    'enable': const BitRange.single(0),
    'txReady': const BitRange.single(1),
    'rxReady': const BitRange.single(2),
    'error': const BitRange.single(3),
  });
}
