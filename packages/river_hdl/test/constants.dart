import 'package:rohd/rohd.dart';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:test/test.dart';

const kCpuConfigs = <String, RiverCore>{
  'RC1.n': const RiverCoreV1.nano(
    mmu: Mmu(mxlen: Mxlen.mxlen_32, blocks: []),
    interrupts: [],
    clock: ClockConfig(name: 'test', baseFreqHz: 10000),
  ),
  'RC1.mi': const RiverCoreV1.micro(
    mmu: Mmu(mxlen: Mxlen.mxlen_32, blocks: []),
    interrupts: [],
    clock: ClockConfig(name: 'test', baseFreqHz: 10000),
  ),
  // FIXME: this breaks tests in core_tests.dart after adding the MMU */
  'RC1.s': const RiverCoreV1.small(
    mmu: Mmu(mxlen: Mxlen.mxlen_64, blocks: []),
    interrupts: [],
    clock: ClockConfig(name: 'test', baseFreqHz: 10000),
  ),
};

void cpuTests(
  String name,
  dynamic Function(RiverCore) body, {
  bool Function(RiverCore)? condition,
}) {
  for (final entry in kCpuConfigs.entries) {
    if (condition != null) {
      if (!condition!(entry.value)) continue;
    }
    group('${entry.key} - $name', () => body(entry.value));
  }
}
