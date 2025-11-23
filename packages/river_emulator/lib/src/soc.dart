import 'dart:collection';
import 'package:river/river.dart';
import 'core.dart';
import 'dev.dart';

/// Emulator of the SoC
class RiverSoCEmulator {
  List<RiverCoreEmulator> _cores;
  List<DeviceEmulator> _devices;

  final RiverSoC config;

  UnmodifiableListView<RiverCoreEmulator> get cores =>
      UnmodifiableListView(_cores);
  UnmodifiableListView<DeviceEmulator> get devices =>
      UnmodifiableListView(_devices);

  RiverSoCEmulator(
    this.config, {
    Map<String, DeviceFactory> deviceFactory = const {},
  }) : _cores = const [],
       _devices = const [] {
    _devices = config.devices.map((dev) {
      if (deviceFactory.containsKey(dev.compatible)) {
        return deviceFactory[dev.compatible]!(dev);
      }

      return DeviceEmulator(dev);
    }).toList();

    final memDevices = Map.fromEntries(
      _devices.map((dev) => dev.mem).nonNulls.toList(),
    );
    _cores = config.cores
        .map((core) => RiverCoreEmulator(core, memDevices: memDevices))
        .toList();
  }

  void reset() {
    for (final core in _cores) core.reset();
    for (final dev in _devices) dev.reset();
  }

  void increment() {
    for (final dev in _devices) dev.increment();
    for (final core in _cores) core.csrs.increment();
  }

  Map<int, int> runPipelines(Map<int, int> pcs) {
    for (final core in _cores) {
      var pc = pcs[core.config.hartId] ?? core.config.resetVector;
      pc = core.runPipeline(pc);
      pcs[core.config.hartId] = pc;
    }

    return pcs;
  }

  Map<int, int> run(Map<int, int> pcs) {
    increment();
    // TODO: check pending interrupts and handle them
    return runPipelines(pcs);
  }

  @override
  String toString() => 'RiverSoCEmulator(cores: $cores, devices: $devices)';
}
