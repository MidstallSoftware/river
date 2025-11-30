import 'dart:async';
import 'dart:io';
import 'package:river/river.dart';
import '../dev.dart';
import '../soc.dart';

class UartEmulator extends DeviceEmulator {
  final Stream<List<int>> input;
  final StreamSink<List<int>> output;

  bool enabled;
  int divisor;
  int error;

  UartEmulator(super.config, {required this.input, required this.output})
    : enabled = false,
      divisor = 0,
      error = 0;

  int get baud {
    if (divisor == 0) return 0;
    return config.clock!.baseFreqHz ~/ divisor;
  }

  @override
  void reset() {
    enabled = false;
    divisor = 0;
    error = 0;
  }

  @override
  DeviceAccessorEmulator? get memAccessor => UartAccessorEmulator(this);

  @override
  String toString() =>
      'UartEmulator(name: ${config.name}, address: ${config.range!.start.toRadixString(16)}, enabled: $enabled, divisor: $divisor, baud: $baud)';

  static DeviceEmulator create(
    Device config,
    Map<String, String> options,
    RiverSoCEmulator _soc,
  ) {
    Stream<List<int>>? input;
    IOSink? output;

    if (options.containsKey('path')) {
      final file = File(options['path']!);
      input = file.openRead();
      output = file.openWrite();
    }

    if (options.containsKey('input.path')) {
      final file = File(options['input.path']!);
      input = file.openRead();
    }

    if (options.containsKey('output.path')) {
      final file = File(options['output.path']!);
      output = file.openWrite();
    }

    return UartEmulator(
      config,
      input: input ?? stdin,
      output: output ?? stdout,
    );
  }
}

class UartAccessorEmulator extends DeviceFieldAccessorEmulator<UartEmulator> {
  UartAccessorEmulator(super.device);

  int readPath(String name) {
    switch (name) {
      case 'status':
        return RiverUart.status.encode({
          'enable': device.enabled ? 1 : 0,
          'txRead': 0,
          'rxReady': 0,
          'error': device.error,
        });
      case 'baud':
        return device.baud;
      default:
        return super.readPath(name);
    }
  }

  void writePath(String name, int value) {
    switch (name) {
      case 'tx':
        print(String.fromCharCode(value));
        break;
      case 'status':
        final status = RiverUart.status.decode(value);
        device.enabled = status['enable'] == 1;
        break;
      case 'divisor':
        device.divisor = value;
        break;
      default:
        super.writePath(name, value);
        break;
    }
  }
}
