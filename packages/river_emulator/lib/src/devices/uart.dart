import 'dart:async';
import 'dart:io';
import 'package:river/river.dart';
import '../dev.dart';
import '../soc.dart';

class UartEmulator extends DeviceEmulator {
  final Stream<List<int>> input;
  final StreamSink<List<int>> output;

  final List<int> _rxFifo = [];
  final List<int> _txFifo = [];

  late final StreamSubscription _inputSubscription;

  int dll = 0;
  int dlm = 0;
  int ier = 0;
  int iir = 0x01;
  int lcr = 0;
  int mcr = 0;
  int lsr = 0x60;
  int msr = 0;
  int scr = 0;
  int fcr = 0;

  UartEmulator(super.config, {required this.input, required this.output}) {
    _inputSubscription = input.listen((data) {
      _rxFifo.addAll(data);
      _updateLineStatus();
      _updateIIR();
    });
  }

  bool get dlab => (lcr & 0x80) != 0;

  int get divisor => (dlm << 8) | dll;

  int get baud {
    if (divisor == 0) return 0;
    return config.clock!.baseFreqHz ~/ divisor;
  }

  void _updateLineStatus() {
    lsr = 0;

    if (_rxFifo.isNotEmpty) lsr |= 0x01;
    if (_txFifo.isEmpty) lsr |= 0x20;

    lsr |= 0x40;
  }

  Future<void> flush() async {
    while (_txFifo.isNotEmpty) await Future.delayed(Duration.zero);
    await Future.delayed(Duration.zero);
  }

  void _updateIIR() {
    if ((ier & 0x04) != 0 && (_lineStatusInterrupt())) {
      iir = 0x06;
      return;
    }

    if ((ier & 0x01) != 0 && _rxFifo.isNotEmpty) {
      iir = 0x04;
      return;
    }

    if ((ier & 0x02) != 0 && (_txFifo.isEmpty)) {
      iir = 0x02;
      return;
    }

    iir = 0x01;
  }

  bool _lineStatusInterrupt() {
    // Typically parity/framing/overrun/break errors
    // For now: no errors
    return false;
  }

  Duration txDelay() {
    if (baud == 0) return Duration.zero;
    final seconds = 10 / baud;
    return Duration(microseconds: (seconds * 1e6).toInt());
  }

  int _readRBR() {
    if (_rxFifo.isEmpty) {
      return 0;
    }
    final byte = _rxFifo.removeAt(0);
    _updateLineStatus();
    _updateIIR();
    return byte;
  }

  void _writeTHR(int value) {
    _txFifo.add(value & 0xFF);
    _updateLineStatus();
    _updateIIR();

    if (_txFifo.isNotEmpty) {
      _scheduleNextTx();
    }
  }

  void _scheduleNextTx() {
    if (_txFifo.isEmpty) return;

    final byte = _txFifo.first;

    Future.delayed(txDelay(), () {
      output.add([byte]);
      _txFifo.removeAt(0);

      _updateLineStatus();
      _updateIIR();

      if (_txFifo.isNotEmpty) {
        _scheduleNextTx();
      }
    });
  }

  @override
  Map<int, bool> interrupts(int hartId) {
    final pending = (iir & 0x01) == 0;
    return {0: pending};
  }

  @override
  void reset() {
    dll = 0;
    dlm = 0;
    ier = 0;
    iir = 0x01;
    lcr = 0;
    mcr = 0;
    lsr = 0x60;
    msr = 0;
    scr = 0;
    fcr = 0;

    _rxFifo.clear();
    _txFifo.clear();
  }

  @override
  DeviceAccessorEmulator? get memAccessor => UartAccessorEmulator(this);

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

  @override
  Future<int> readPath(String name) async {
    switch (name) {
      case 'rbr_thr_dll':
        await Future.delayed(Duration.zero);
        return device.dlab ? device.dll : device._readRBR();
      case 'ier_dlm':
        return device.dlab ? device.dlm : device.ier;
      case 'iir_fcr':
        return device.iir | (device.fcr & 0xC0);
      case 'lcr':
        return device.lcr;
      case 'mcr':
        return device.mcr;
      case 'lsr':
        await Future.delayed(Duration.zero);
        return device.lsr;
      case 'msr':
        return device.msr;
      case 'scr':
        return device.scr;
    }

    return 0;
  }

  @override
  Future<void> writePath(String name, int value) async {
    value &= 0xFF;

    switch (name) {
      case 'rbr_thr_dll':
        if (device.dlab)
          device.dll = value;
        else
          device._writeTHR(value);
        break;
      case 'ier_dlm':
        if (device.dlab)
          device.dlm = value;
        else
          device.ier = value;
        device._updateIIR();
        break;
      case 'iir_fcr':
        device.fcr = value;
        if ((value & 0x02) != 0) device._rxFifo.clear();
        if ((value & 0x04) != 0) device._txFifo.clear();
        device._updateLineStatus();
        device._updateIIR();
        break;
      case 'lcr':
        device.lcr = value;
        device._updateLineStatus();
        break;
      case 'mcr':
        device.mcr = value;
        break;
      case 'scr':
        device.scr = value;
        break;
    }
  }
}
