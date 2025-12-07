import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_hdl/river_hdl.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('Execution', () async {
    final microcode = Microcode(Microcode.buildDecodeMap([rv32i]));

    final clk = SimpleClockGenerator(15).clk;
    final reset = Logic();

    final input = Logic(width: 32);
    input <= Const(0x00A08293, width: 32);

    final decoder = InstructionDecoder(
      input,
      microcode: microcode,
      mxlen: Mxlen.mxlen_32,
    );

    final csrRead = DataPortInterface(32, 32);
    final csrWrite = DataPortInterface(32, 32);

    final memRead = DataPortInterface(32, 32);
    final memWrite = DataPortInterface(32, 32);

    final rs1Read = DataPortInterface(32, 5);
    final rs2Read = DataPortInterface(32, 5);
    final rdWrite = DataPortInterface(32, 5);

    final reg = RegisterFile(
      clk,
      reset,
      [rdWrite],
      [rs1Read, rs2Read],
      numEntries: 32,
    );

    final exec = ExecutionUnit(
      clk,
      reset,
      Const(0, width: 32),
      Const(0, width: 32),
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
      mxlen: Mxlen.mxlen_32,
    );

    await exec.build();

    //print(exec.generateSynth());
    //WaveDumper(exec);

    reset.inject(1);

    Simulator.registerAction(15, () => reset.put(0));

    Simulator.setMaxSimTime(120000);
    unawaited(Simulator.run());

    for (var i = 0; i < 30; i++) {
      await clk.nextPosedge;
    }

    await Simulator.simulationEnded;

    /*print(exec.done.value);

    for (var i = 0; i < 32; i++) {
      print('$i - ${reg.getData(LogicValue.ofInt(i, 5))}');
    }*/
  });
}
