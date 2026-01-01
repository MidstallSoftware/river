import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
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

  final addrWidth = config.mmu.blocks[0].size.bitLength;

  final memRead = DataPortInterface(config.mxlen.size, addrWidth);
  final memWrite = DataPortInterface(config.mxlen.size, addrWidth);

  final mmioRead = MmioReadInterface(config.mxlen.size, addrWidth);
  final mmioWrite = MmioWriteInterface(config.mxlen.size, addrWidth);

  memRead.en <= mmioRead.en;
  memRead.addr <= mmioRead.addr;
  mmioRead.data <= memRead.data;
  mmioRead.done <= memRead.done;
  mmioRead.valid <= memRead.valid;

  memWrite.en <= mmioWrite.en;
  memWrite.addr <= mmioWrite.addr;
  memWrite.data <= mmioWrite.data;
  mmioWrite.done <= memWrite.done;
  mmioWrite.valid <= memWrite.valid;

  final storage = SparseMemoryStorage(
    addrWidth: addrWidth,
    dataWidth: config.mxlen.size,
    alignAddress: (addr) => addr,
    onInvalidRead: (addr, dataWidth) =>
        LogicValue.filled(dataWidth, LogicValue.zero),
  );

  final mem = MemoryModel(
    clk,
    reset,
    [memWrite],
    [memRead],
    readLatency: latency,
    storage: storage,
  );

  final core = RiverCoreIP(config);

  mmioRead.en <=
      (core.interface('mmioRead0').interface as MmioReadInterface).en;
  mmioRead.addr <=
      (core.interface('mmioRead0').interface as MmioReadInterface).addr;
  (core.interface('mmioRead0').interface as MmioReadInterface).data <=
      mmioRead.data;
  (core.interface('mmioRead0').interface as MmioReadInterface).done <=
      mmioRead.done;
  (core.interface('mmioRead0').interface as MmioReadInterface).valid <=
      mmioRead.valid;

  mmioWrite.en <=
      (core.interface('mmioWrite0').interface as MmioWriteInterface).en;
  mmioWrite.addr <=
      (core.interface('mmioWrite0').interface as MmioWriteInterface).addr;
  mmioWrite.data <=
      (core.interface('mmioWrite0').interface as MmioWriteInterface).data;
  (core.interface('mmioWrite0').interface as MmioWriteInterface).done <=
      mmioWrite.done;
  (core.interface('mmioWrite0').interface as MmioWriteInterface).valid <=
      mmioWrite.valid;

  core.input('clk').srcConnection! <= clk;
  core.input('reset').srcConnection! <= reset;

  await core.build();

  reset.inject(1);

  Simulator.registerAction(20, () {
    reset.put(0);

    for (final regState in initRegisters.entries) {
      core.regs.setData(
        LogicValue.ofInt(regState.key.value, 5),
        LogicValue.ofInt(regState.value, config.mxlen.size),
      );
    }

    storage.loadMemString(memString);
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
    final value = core.regs.getData(LogicValue.ofInt(regState.key.value, 5))!;
    expect(value.toInt(), regState.value, reason: '${regState.key}=$value');
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
