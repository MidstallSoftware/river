import 'dart:collection';
import 'package:river/river.dart';
import 'core.dart';
import 'dev.dart';
import 'devices.dart';

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
    Map<String, Map<String, String>> deviceOptions = const {},
    Map<String, DeviceEmulatorFactory> deviceFactory = kDeviceEmulatorFactory,
  }) : _cores = const [],
       _devices = const [] {
    _devices = config.devices.map((dev) {
      if (deviceFactory.containsKey(dev.compatible)) {
        return deviceFactory[dev.compatible]!(
          dev,
          deviceOptions[dev.name] ?? {},
          this,
        );
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

  DeviceEmulator? getDevice(String name) {
    for (final dev in devices) {
      if (dev.config.name == name) return dev;
    }
    return null;
  }

  void reset() {
    for (final core in _cores) core.reset();
    for (final dev in _devices) dev.reset();
  }

  void increment() {
    for (final dev in _devices) dev.increment();
    for (final core in _cores) core.csrs.increment();
  }

  Future<Map<int, int>> runPipelines(Map<int, int> pcs) async {
    return Map.fromEntries(
      await Future.wait(
        cores.map((core) async {
          var pc = pcs[core.config.hartId] ?? core.config.resetVector;
          return MapEntry(core.config.hartId, await core.runPipeline(pc));
        }),
      ),
    );
  }

  Future<Map<int, int>> run(Map<int, int> pcs) {
    increment();
    return runPipelines(pcs);
  }

  @override
  String toString() => 'RiverSoCEmulator(cores: $cores, devices: $devices)';
}
