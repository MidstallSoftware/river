import 'devices/bootrom.dart';
import 'devices/sram.dart';
import 'devices/uart.dart';
import 'dev.dart';

export 'devices/bootrom.dart';
export 'devices/sram.dart';
export 'devices/uart.dart';

const Map<String, DeviceEmulatorFactory> kDeviceEmulatorFactory = {
  'river,bootrom': BootromEmulator.create,
  'river,sram': SramEmulator.create,
  'river,uart': UartEmulator.create,
};
