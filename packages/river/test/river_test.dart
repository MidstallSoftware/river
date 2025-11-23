import 'package:river/river.dart';
import 'package:test/test.dart';

void main() {
  group('Stream V1 - iCESugar', () {
    const soc = StreamV1SoC.icesugar();

    test('Reset vector', () {
      final bootrom = soc.getDevice('bootrom')!;
      expect(soc.cores[0].resetVector, bootrom.range!.start);
    });
  });
}
