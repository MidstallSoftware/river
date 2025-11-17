import 'dart:collection';
import 'package:river/river.dart';
import 'core.dart';

/// Emulator of the SoC
class RiverSoCEmulator {
  List<RiverCoreEmulator> cores;

  final RiverSoC config;

  //UnmodifiableListView<RiverCoreEmulator> get cores => UnmodifiableListView(_cores);

  RiverSoCEmulator(this.config)
    : cores = config.cores.map((core) => RiverCoreEmulator(core)).toList();

  void reset() {
    for (final core in cores) core.reset();
  }

  @override
  String toString() => 'RiverSoCEmulator(cores: $cores)';
}
