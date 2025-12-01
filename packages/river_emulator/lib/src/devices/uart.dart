import 'dart:async';
import 'dart:io';
import 'package:river/river.dart';
import '../dev.dart';
import '../soc.dart';

class UartEmulator extends DeviceEmulator {
  final Stream<List<int>> input;
  final StreamSink<List<int>> output;

  final List<int> _inputBuffer;
  late final StreamSubscription _inputSubscription;

  bool enabled;
  int divisor;
  int error;

  UartEmulator(super.config, {required this.input, required this.output})
    : enabled = false,
      divisor = 0,
      error = 0,
      _inputBuffer = [] {
    _inputSubscription = input.listen(_inputBuffer.addAll);
  }

  int get baud {
    if (divisor == 0) return 0;
    return config.clock!.baseFreqHz ~/ divisor;
  }

  bool get rxReady => _inputBuffer.isNotEmpty;

  int get rx {
    if (_inputBuffer.isEmpty) return -1;
    return _inputBuffer.removeAt(0) & 0xFF;
  }

  set tx(int byte) {
    output.add([byte & 0xFF]);
  }

  @override
  void reset() {
    enabled = false;
    divisor = 0;
    error = 0;
    _inputBuffer.clear();
  }

  @override
  DeviceAccessorEmulator? get memAccessor => UartAccessorEmulator(this);

  @override
  String toString() =>
      'UartEmulator(name: ${config.name}, address: ${config.range!.start.toRadixString(16)}, enabled: $enabled, divisor: $divisor, baud: $baud, rxReady: $rxReady)';

  static DeviceEmulator create(
    Device config,
    Map<String, String> options,
    RiverSoCEmulator _soc,
  ) {
    Stream<List<int>>? input;
    StreamSink<List<int>>? output;

    if (options.containsKey('path')) {
      final file = File(options['path']!);
      input = file.openRead();
      output = file.openWrite();
    }

    if (options.containsKey('input.path')) {
      final file = File(options['input.path']!);
      input = file.openRead();
    } else if (options.containsKey('input.string')) {
      input = Stream.value(options['input.string']!.codeUnits);
    } else if (options.containsKey('input.empty')) {
      input = Stream.empty();
    }

    if (options.containsKey('output.path')) {
      final file = File(options['output.path']!);
      output = file.openWrite();
    } else if (options.containsKey('output.empty')) {
      output = StreamController<List<int>>().sink;
    }

    if (input == null) {
      if (stdioType(stdin) == StdioType.terminal) {
        stdin.echoMode = false;
        stdin.lineMode = false;
      }

      input = stdin;
    }

    return UartEmulator(config, input: input!, output: output ?? stdout);
  }
}

class UartAccessorEmulator extends DeviceFieldAccessorEmulator<UartEmulator> {
  UartAccessorEmulator(super.device);

  Future<int> readPath(String name) async {
    switch (name) {
      case 'rx':
        return device.rx;
      case 'status':
        await Future.delayed(Duration.zero);
        return RiverUart.status.encode({
          'enable': device.enabled ? 1 : 0,
          'txReady': 1,
          'rxReady': device.rxReady ? 1 : 0,
          'error': device.error,
        });
      case 'divisor':
        return device.baud;
      default:
        return super.readPath(name);
    }
  }

  Future<void> writePath(String name, int value) async {
    switch (name) {
      case 'tx':
        device.tx = value & 0xFF;
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
