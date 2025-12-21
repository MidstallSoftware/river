import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_hdl/river_hdl.dart';
import 'package:test/test.dart';

Future<void> execTest(
  int instr,
  Map<Register, int> regStates,
  Microcode microcode,
  Mxlen mxlen, {
  Map<int, int> memStates = const {},
  Map<int, int> initMem = const {},
  Map<Register, int> initRegisters = const {},
  int nextPc = 4,
  int memLatency = 0,
}) async {
  final clk = SimpleClockGenerator(20).clk;
  final reset = Logic();
  final enable = Logic();

  final input = Const(instr, width: 32);

  final decoder = InstructionDecoder(
    clk,
    reset,
    enable,
    input,
    microcode: microcode,
    mxlen: mxlen,
  );

  final csrRead = DataPortInterface(mxlen.size, 32);
  final csrWrite = DataPortInterface(mxlen.size, 32);

  final memRead = DataPortInterface(mxlen.size, mxlen.size);
  final memWrite = DataPortInterface(mxlen.size + 7, mxlen.size);

  final backingMemRead = DataPortInterface(mxlen.size, mxlen.size);
  final backingMemWrite = DataPortInterface(mxlen.size, mxlen.size);

  final storage = SparseMemoryStorage(
    addrWidth: mxlen.size,
    dataWidth: mxlen.size,
    alignAddress: (addr) => addr,
    onInvalidRead: (addr, dataWidth) =>
        LogicValue.filled(dataWidth, LogicValue.zero),
  );

  final mem = MemoryModel(
    clk,
    reset,
    [backingMemWrite],
    [memRead, backingMemRead],
    readLatency: memLatency,
    storage: storage,
  );

  SizedWriteSingleDataPort(
    clk,
    reset,
    backingRead: backingMemRead,
    backingWrite: backingMemWrite,
    source: memWrite,
  );

  final rs1Read = DataPortInterface(mxlen.size, 5);
  final rs2Read = DataPortInterface(mxlen.size, 5);
  final rdWrite = DataPortInterface(mxlen.size, 5);

  final regs = RegisterFile(
    clk,
    reset,
    [rdWrite],
    [rs1Read, rs2Read],
    numEntries: 32,
  );

  final exec = ExecutionUnit(
    clk,
    reset,
    decoder.valid & decoder.done,
    Const(0, width: mxlen.size),
    Const(0, width: mxlen.size),
    Const(PrivilegeMode.machine.id, width: 3),
    decoder.index,
    decoder.instrTypeMap,
    decoder.fields,
    csrRead,
    csrWrite,
    memRead,
    memWrite,
    rs1Read,
    rs2Read,
    rdWrite,
    microcode: microcode,
    mxlen: mxlen,
  );

  await exec.build();

  reset.inject(1);
  enable.inject(0);

  Simulator.registerAction(15, () {
    reset.put(0);

    for (final regState in initRegisters.entries) {
      regs.setData(
        LogicValue.ofInt(regState.key.value, 5),
        LogicValue.ofInt(regState.value, mxlen.size),
      );
    }

    for (final memState in initMem.entries) {
      storage.setData(
        LogicValue.ofInt(memState.key, mxlen.size),
        LogicValue.ofInt(memState.value, mxlen.size),
      );
    }

    enable.inject(1);
  });

  unawaited(Simulator.run());

  await clk.nextPosedge;

  while (reset.value.toBool()) {
    await clk.nextPosedge;
  }

  while (!exec.done.value.toBool()) {
    await clk.nextPosedge;
  }

  while (exec.nextPc.value.toInt() != nextPc) {
    await clk.nextPosedge;
  }

  await Simulator.endSimulation();

  expect(exec.done.value.toBool(), isTrue);
  expect(exec.nextPc.value.toInt(), nextPc);

  for (final regState in regStates.entries) {
    expect(
      regs.getData(LogicValue.ofInt(regState.key.value, 5))!.toInt(),
      regState.value,
    );
  }

  for (final memState in memStates.entries) {
    expect(
      storage.getData(LogicValue.ofInt(memState.key, mxlen.size))!.toInt(),
      memState.value,
    );
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('RV32I', () {
    final microcode = Microcode(Microcode.buildDecodeMap([rv32i]));

    test(
      'addi increments register',
      () => execTest(0x00a08293, {Register.x5: 10}, microcode, Mxlen.mxlen_32),
    );

    test(
      'add performs register addition',
      () => execTest(
        0x005303B3,
        {Register.x7: 16},
        microcode,
        Mxlen.mxlen_32,
        initRegisters: {Register.x5: 7, Register.x6: 9},
      ),
    );

    test(
      'lw loads from memory',
      () => execTest(
        0x0042A303,
        {Register.x6: 0xDEADBEEF},
        microcode,
        Mxlen.mxlen_32,
        initRegisters: {Register.x5: 0x20},
        initMem: {0x24: 0xDEADBEEF},
      ),
    );

    test(
      'sw stores to memory',
      () => execTest(
        0x0062A223,
        {},
        microcode,
        Mxlen.mxlen_32,
        initRegisters: {Register.x5: 0x20, Register.x6: 0xDEADBEEF},
        initMem: {},
      ),
    );

    test(
      'beq takes branch when equal',
      () => execTest(
        0x00628463,
        {},
        microcode,
        Mxlen.mxlen_32,
        initRegisters: {Register.x5: 5, Register.x6: 5},
        nextPc: 8,
      ),
    );

    test(
      'beq does not branch when not equal',
      () => execTest(
        0x00628463,
        {},
        microcode,
        Mxlen.mxlen_32,
        initRegisters: {Register.x5: 5, Register.x6: 7},
        nextPc: 4,
      ),
    );

    test(
      'lui loads upper immediate',
      () => execTest(
        0x123452B7,
        {Register.x5: 0x12345000},
        microcode,
        Mxlen.mxlen_32,
      ),
    );

    test(
      'jal writes ra and jumps',
      () => execTest(
        0x100002EF,
        {Register.x5: 4},
        microcode,
        Mxlen.mxlen_32,
        nextPc: 0x100,
      ),
    );

    test(
      'auipc adds immediate to PC',
      () => execTest(
        0x00010297,
        {Register.x5: 0x10000},
        microcode,
        Mxlen.mxlen_32,
      ),
    );

    test(
      'slti sets when less-than immediate',
      () => execTest(
        0x00A22293,
        {Register.x5: 1},
        microcode,
        Mxlen.mxlen_32,
        initRegisters: {Register.x4: 5},
      ),
    );
  });
}
