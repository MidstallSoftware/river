import 'dart:async';

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
  Map<int, int> memStates = const {},
  Map<Register, int> initRegisters = const {},
  int nextPc = 4,
  int latency = 0,
  int memLatency = 0,
}) async {
  final clk = SimpleClockGenerator(20).clk;
  final reset = Logic();
  final enable = Logic();

  final memFetchRead = DataPortInterface(config.mxlen.size, config.mxlen.size);
  final memExecRead = DataPortInterface(config.mxlen.size, config.mxlen.size);
  final memWrite = DataPortInterface(config.mxlen.size + 7, config.mxlen.size);

  final backingMemRead = DataPortInterface(
    config.mxlen.size,
    config.mxlen.size,
  );
  final backingMemWrite = DataPortInterface(
    config.mxlen.size,
    config.mxlen.size,
  );

  SizedWriteSingleDataPort(
    clk,
    reset,
    backingRead: backingMemRead,
    backingWrite: backingMemWrite,
    source: memWrite,
  );

  final storage = SparseMemoryStorage(
    addrWidth: config.mxlen.size,
    dataWidth: config.mxlen.size,
    alignAddress: (addr) => addr,
    onInvalidRead: (addr, dataWidth) =>
        LogicValue.filled(dataWidth, LogicValue.zero),
  );

  final mem = MemoryModel(
    clk,
    reset,
    [backingMemWrite],
    [memFetchRead, memExecRead, backingMemRead],
    readLatency: latency,
    storage: storage,
  );

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

  reset.inject(1);
  enable.inject(0);

  Simulator.registerAction(20, () {
    reset.put(0);

    for (final regState in initRegisters.entries) {
      core.regs.setData(
        LogicValue.ofInt(regState.key.value, 5),
        LogicValue.ofInt(regState.value, config.mxlen.size),
      );
    }

    storage.loadMemString(memString);

    enable.put(1);
  });

  //Simulator.setMaxSimTime(1200000);
  unawaited(Simulator.run());

  await clk.nextPosedge;

  while (reset.value.toBool()) {
    await clk.nextPosedge;
  }

  while (core.pipeline.nextPc.value.toInt() != nextPc) {
    await clk.nextPosedge;
  }

  await Simulator.endSimulation();
  await Simulator.simulationEnded;

  expect(core.pipeline.done.value.toBool(), isTrue);
  expect(core.pipeline.nextPc.value.toInt(), nextPc);

  for (final regState in regStates.entries) {
    expect(
      core.regs.getData(LogicValue.ofInt(regState.key.value, 5))!.toInt(),
      regState.value,
    );
  }

  for (final memState in memStates.entries) {
    expect(
      storage
          .getData(LogicValue.ofInt(memState.key, config.mxlen.size))!
          .toInt(),
      memState.value,
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
93 02 82 3E 13 00 00 00
''',
        {
          Register.x1: 0x3E8,
          Register.x2: 0xBB8,
          Register.x3: 0x7D0,
          Register.x4: 0,
          Register.x5: 0x3E8,
        },
        config,
        nextPc: 0x18,
      ),
    );
  });
}
