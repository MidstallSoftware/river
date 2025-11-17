import 'package:river/river.dart';
import 'soc.dart';

class RiverEmulator {
  RiverSoCEmulator soc;

  RiverEmulator({required this.soc});

  void reset() {
    soc.reset();
  }

  @override
  String toString() => 'RiverEmulator(soc: $soc)';
}
