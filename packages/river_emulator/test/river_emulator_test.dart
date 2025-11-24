import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';
import 'package:test/test.dart';

void main() {
  group('Stream V1 - iCESugar', () {
    test('Creation', () {
      final socConfig = RiverSoCChoice.stream_v1.configure({
        'platform': 'icesugar',
      })!;

      final soc = RiverSoCEmulator(socConfig);

      expect(soc.devices.length, 8);
      expect(soc.cores.length, 1);
    });
  });
}
