import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_hdl/river_hdl.dart';
import 'package:test/test.dart';

Future<void> fetcherTest(
  int instr, {
  bool isCompressed = false,
  bool hasCompressed = false,
  int latency = 0,
}) async {
  final clk = SimpleClockGenerator(20).clk;
  final reset = Logic();
  final enable = Logic();

  final memRead = DataPortInterface(32, 32);

  final mem = MemoryModel(
    clk,
    reset,
    [],
    [memRead],
    readLatency: latency,
    storage: SparseMemoryStorage(
      addrWidth: 32,
      dataWidth: 32,
      alignAddress: (addr) => addr,
      onInvalidRead: (addr, dataWidth) =>
          LogicValue.ofInt(addr.toInt() == 0 ? instr : 0, dataWidth),
    ),
  );

  final fetcher = FetchUnit(
    clk,
    reset,
    enable,
    Const(0, width: 32),
    memRead,
    hasCompressed: hasCompressed,
  );

  await fetcher.build();

  Simulator.registerAction(15, () {
    reset.put(0);
    enable.put(1);
  });

  reset.inject(1);
  enable.inject(0);

  unawaited(Simulator.run());

  await clk.nextPosedge;

  while (reset.value.toBool()) {
    await clk.nextPosedge;
  }

  await clk.nextPosedge;

  while (!fetcher.done.value.toBool()) {
    await clk.nextPosedge;
  }

  await clk.nextPosedge;

  await Simulator.endSimulation();
  await Simulator.simulationEnded;

  expect(fetcher.done.value.toBool(), isTrue);
  expect(fetcher.result.value.toInt(), instr);

  if (hasCompressed) {
    expect(fetcher.compressed.value.toBool(), isCompressed);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('Fetch non-compressed', () {
    test('Simple', () => fetcherTest(0x00a08293));

    const latencies = <int>[12, 24, 36, 120, 240, 360, 1200];

    for (final latency in latencies) {
      test('Latency $latency', () => fetcherTest(0x00a08293, latency: latency));
    }
  });

  group('Compressed', () {
    test(
      'Simple',
      () => fetcherTest(0x200, hasCompressed: true, isCompressed: true),
    );

    const latencies = <int>[12, 24, 36, 120, 240, 360, 1200];

    for (final latency in latencies) {
      test(
        'Latency $latency',
        () => fetcherTest(
          0x200,
          latency: latency,
          hasCompressed: true,
          isCompressed: true,
        ),
      );
    }
  });
}
