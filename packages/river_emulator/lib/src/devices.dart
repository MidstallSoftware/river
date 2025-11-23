import 'devices/bootrom.dart';
import 'dev.dart';

export 'devices/bootrom.dart';

const Map<String, DeviceEmulatorFactory> kDeviceEmulatorFactory = {
  'river,bootrom': BootromEmulator.create,
};
