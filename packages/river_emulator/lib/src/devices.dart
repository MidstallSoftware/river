import 'devices/bootrom.dart';
import 'devices/sram.dart';
import 'dev.dart';

export 'devices/bootrom.dart';
export 'devices/sram.dart';

const Map<String, DeviceEmulatorFactory> kDeviceEmulatorFactory = {
  'river,bootrom': BootromEmulator.create,
  'river,sram': SramEmulator.create,
};
