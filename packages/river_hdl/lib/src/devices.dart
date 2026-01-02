import 'devices/flash.dart';
import 'devices/sram.dart';
import 'devices/uart.dart';
import 'dev.dart';

export 'devices/flash.dart';
export 'devices/sram.dart';
export 'devices/uart.dart';

const Map<String, DeviceModuleFactory> kDeviceModuleFactory = {
  'river,flash': RiverFlashModule.create,
  'river,sram': RiverSramModule.create,
  'river,uart': RiverUartModule.create,
};
