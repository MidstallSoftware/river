import 'dart:async';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_hdl/river_hdl.dart';
import 'package:test/test.dart';
import 'constants.dart';

void coreTest(
  String memString,
  Map<Register, int> regStates,
  RiverCore config, {
  Map<Register, int> initRegisters = const {},
  int maxSimTime = 1200,
  int cycleCount = 8,
  int nextPc = 4,
  int latency = 0,
}) async {
  final clk = SimpleClockGenerator(20).clk;
  final reset = Logic();
  final enable = Logic();

  final memFetchRead = DataPortInterface(config.mxlen.size, config.mxlen.size);
  final memExecRead = DataPortInterface(config.mxlen.size, config.mxlen.size);
  final memWrite = DataPortInterface(config.mxlen.size + 7, config.mxlen.size);

  final storage = SparseMemoryStorage(
    addrWidth: config.mxlen.size,
    dataWidth: config.mxlen.size,
    alignAddress: (addr) => addr,
    onInvalidRead: (addr, dataWidth) =>
        LogicValue.filled(dataWidth, LogicValue.zero),
  )..loadMemString(memString);

  print(storage.getData(LogicValue.ofInt(0, config.mxlen.size)));

  final mem = MemoryModel(
    clk,
    reset,
    [],
    [memFetchRead, memExecRead],
    readLatency: latency,
    storage: storage,
  );

  print(mem.storage.dumpMemString());

  final core = RiverCoreHDL(
    config,
    clk,
    reset,
    enable,
    memFetchRead,
    memExecRead,
    memWrite,
  );

  await core.build();

  WaveDumper(core, outputPath: 'waves_${config.mxlen.size}.vcd');

  reset.inject(1);
  enable.inject(0);

  //File('core_${config.mxlen.size}.sv').writeAsStringSync(core.generateSynth());

  Simulator.registerAction(20, () {
    reset.put(0);

    for (final regState in initRegisters.entries) {
      core.regs.setData(
        LogicValue.ofInt(regState.key.value, 5),
        LogicValue.ofInt(regState.value, config.mxlen.size),
      );
    }

    enable.put(1);
  });

  Simulator.setMaxSimTime(maxSimTime * ((latency ~/ 36) + 1));
  unawaited(Simulator.run());

  for (var i = 0; i < cycleCount; i++) {
    await clk.nextPosedge;
  }

  await Simulator.simulationEnded;

  expect(core.pipeline.done.value.toBool(), isTrue);
  expect(core.pipeline.nextPc.value.toInt(), nextPc);

  for (final regState in regStates.entries) {
    expect(
      core.regs.getData(LogicValue.ofInt(regState.key.value, 5))!.toInt(),
      regState.value,
    );
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  cpuTests('RV32I', (config) {
    test(
      'Small program',
      () => coreTest(
        '''@${config.resetVector.toRadixString(16)}
93 00 80 3E 13 81 00 7D 93 01 81 C1 13 82 01 83
93 02 82 3E
''',
        {},
        config,
        // FIXME TODO: the memory isn't working correctly
        nextPc: 2,
      ),
    );
  });
}
