import 'package:riscv/riscv.dart';

import '../../bus.dart';
import '../../clock.dart';
import '../../dev.dart';

/// A NS16550-compatible UART for River
class RiverUart extends Device {
  RiverUart({
    required String name,
    required int address,
    required ClockConfig clock,
  }) : super(
         name: name,
         compatible: 'river,uart',
         interrupts: const [1],
         range: BusAddressRange(address, 0x20),
         clock: clock,
         accessor: DeviceAccessor('/$name', const {
           0: DeviceField('rbr_thr_dll', 1),
           1: DeviceField('ier_dlm', 1),
           2: DeviceField('iir_fcr', 1),
           3: DeviceField('lcr', 1),
           4: DeviceField('mcr', 1),
           5: DeviceField('lsr', 1),
           6: DeviceField('msr', 1),
           7: DeviceField('scr', 1),
         }),
       );

  static const lcr = BitStruct({
    'wordLength': BitRange(0, 2),
    'stopBits': BitRange.single(2),
    'parityEnable': BitRange.single(3),
    'evenParity': BitRange.single(4),
    'stickParity': BitRange.single(5),
    'breakEnable': BitRange.single(6),
    'dlab': BitRange.single(7),
  });

  static const ier = BitStruct({
    'rxAvailable': BitRange.single(0),
    'txEmpty': BitRange.single(1),
    'lsr': BitRange.single(2),
    'msr': BitRange.single(3),
  });

  static const iir = BitStruct({
    'interruptPending': BitRange.single(0),
    'interruptId': BitRange(1, 3),
    'fifoEnabled': BitRange(2, 6),
  });

  static const fcr = BitStruct({
    'fifoEnable': BitRange.single(0),
    'rxReset': BitRange.single(1),
    'txReset': BitRange.single(2),
    'dmaMode': BitRange.single(3),
    'triggerLevel': BitRange(2, 6),
  });

  static const lsr = BitStruct({
    'dataReady': BitRange.single(0),
    'overrunError': BitRange.single(1),
    'parityError': BitRange.single(2),
    'framingError': BitRange.single(3),
    'breakInterrupt': BitRange.single(4),
    'thrEmpty': BitRange.single(5),
    'tsrEmpty': BitRange.single(6),
    'fifoError': BitRange.single(7),
  });

  static const mcr = BitStruct({
    'dtr': BitRange.single(0),
    'rts': BitRange.single(1),
    'out1': BitRange.single(2),
    'out2': BitRange.single(3),
    'loopback': BitRange.single(4),
  });

  static const msr = BitStruct({
    'deltaCts': BitRange.single(0),
    'deltaDsr': BitRange.single(1),
    'deltaRi': BitRange.single(2),
    'deltaDcd': BitRange.single(3),
    'cts': BitRange.single(4),
    'dsr': BitRange.single(5),
    'ri': BitRange.single(6),
    'dcd': BitRange.single(7),
  });
}
