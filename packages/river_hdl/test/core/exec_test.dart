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
  Map<Register, int> initRegisters = const {},
  int maxSimTime = 200,
  int cycleCount = 4,
  int nextPc = 4,
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

  final csrRead = DataPortInterface(32, 32);
  final csrWrite = DataPortInterface(32, 32);

  final memRead = DataPortInterface(32, 32);
  final memWrite = DataPortInterface(39, 32);

  final rs1Read = DataPortInterface(32, 5);
  final rs2Read = DataPortInterface(32, 5);
  final rdWrite = DataPortInterface(32, 5);

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
    Const(0, width: 32),
    Const(0, width: 32),
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

    enable.inject(1);
  });

  Simulator.setMaxSimTime(maxSimTime);
  unawaited(Simulator.run());

  for (var i = 0; i < cycleCount; i++) {
    await clk.nextPosedge;
  }

  await Simulator.simulationEnded;

  expect(exec.done.value.toBool(), isTrue);
  expect(exec.nextPc.value.toInt(), nextPc);

  for (final regState in regStates.entries) {
    expect(
      regs.getData(LogicValue.ofInt(regState.key.value, 5))!.toInt(),
      regState.value,
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
        maxSimTime: 800,
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
        maxSimTime: 800,
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
        maxSimTime: 800,
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
        maxSimTime: 800,
      ),
    );

    test(
      'auipc adds immediate to PC',
      () => execTest(
        0x00010297,
        {Register.x5: 0x10000},
        microcode,
        Mxlen.mxlen_32,
        maxSimTime: 800,
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
        maxSimTime: 800,
      ),
    );
  });
}
